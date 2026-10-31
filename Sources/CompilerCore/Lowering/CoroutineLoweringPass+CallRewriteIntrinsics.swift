
extension CoroutineLoweringPass {
    func rewriteYieldCall(
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        guard call.callee == rewrite.yieldCallee, call.arguments.isEmpty else {
            return nil
        }
        return .call(callee: rewrite.runtimeYieldCallee, arguments: call.arguments, result: call.result, canThrow: false)
    }

    /// `CoroutineStart.isLazy` is registered as a synthetic member property
    /// with the `kk_coroutine_start_is_lazy` external link name. The enum
    /// entries are symbolic markers with no distinct runtime value, so the
    /// read folds here to a Boolean constant from the entry the receiver
    /// refers to (the same compile-time resolution the launch/async
    /// start-mode rewrite uses). A receiver that is not a compile-time-known
    /// `CoroutineStart` entry folds to `false`, mirroring the launcher's
    /// fallback-to-DEFAULT convention. `kk_coroutine_start_is_lazy` itself is
    /// never emitted, so it needs no runtime entry point.
    func rewriteCoroutineStartIsLazyCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.ctx.interner.intern("kk_coroutine_start_is_lazy"),
              let result = call.result
        else {
            return nil
        }
        let entryName = call.arguments.first.flatMap {
            coroutineStartEntryName($0, symbolByExprRaw: symbolByExprRaw, using: rewrite)
        }
        return [.constValue(result: result, value: .intLiteral(entryName == "LAZY" ? 1 : 0))]
    }

    func rewriteCreateCoroutineUninterceptedCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        if call.callee == rewrite.createCoroutineCallee, hasRealDeclaration(call.symbol, in: rewrite.ctx) {
            return nil
        }
        var call = call
        // A marker call materialized from kklib carries its suspend-function
        // argument as a `(fnPtr, context)` pair — one extra slot versus the
        // source-level argument list. Strip the context slot so the rewrite
        // sees the same shape either mode produces; the link-ABI fallback
        // below re-adds it when the function cannot be resolved. The context
        // half is the callable's closure environment, though — the launcher
        // thunk of a suspend function *value* reads it as its leading slot —
        // so keep it for the resolved-path launcher setup below.
        var contextArgument: KIRExprID? = nil
        if (call.callee == rewrite.createCoroutineUninterceptedWithReceiverCallee
                && call.arguments.count == 4)
            || (call.callee == rewrite.createCoroutineUninterceptedNoReceiverCallee
                && call.arguments.count == 3)
        {
            contextArgument = call.arguments[1]
            call = CallRewriteInput(
                instruction: call.instruction,
                symbol: call.symbol,
                callee: call.callee,
                arguments: [call.arguments[0]] + call.arguments.dropFirst(2),
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult,
                isSuperCall: call.isSuperCall
            )
        }
        guard call.callee == rewrite.createCoroutineUninterceptedCallee || call.callee == rewrite.createCoroutineCallee
                || call.callee == rewrite.createCoroutineUninterceptedNoReceiverCallee
                || call.callee == rewrite.createCoroutineUninterceptedWithReceiverCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            // A source-backed public builder receives an already boxed suspend
            // callable. Keep its entry metadata and adapt the marker's C ABI.
            guard call.callee == rewrite.createCoroutineUninterceptedNoReceiverCallee
                    || call.callee == rewrite.createCoroutineUninterceptedWithReceiverCallee else {
                return nil
            }
            let unusedContext = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            return [
                .constValue(result: unusedContext, value: .intLiteral(0)),
                .call(
                    symbol: call.symbol, callee: call.callee,
                    arguments: [call.arguments[0], unusedContext] + Array(call.arguments.dropFirst()),
                    result: call.result, canThrow: call.canThrow,
                    thrownResult: call.thrownResult
                ),
            ]
        }

        let launcherArguments = resolvedLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            contextArgument: contextArgument,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3 || !launcherArguments.isEmpty,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = call.result ?? rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false
            )
        ]

        appendCapturedLauncherArgumentSetup(
            launcherArguments,
            continuationExpr: continuationExpr,
            using: rewrite,
            into: &rewritten
        )

        return rewritten
    }

    func rewriteStartCoroutineUninterceptedOrReturnCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        var call = call
        // See the normalization note in rewriteCreateCoroutineUninterceptedCall:
        // kklib-serialized marker calls carry an extra context slot after the
        // function argument. The context half is the suspend function value's
        // closure environment; keep it for the resolved-path launcher setup.
        var contextArgument: KIRExprID? = nil
        if (call.callee == rewrite.startCoroutineUninterceptedOrReturnWithReceiverCallee
                && call.arguments.count == 4)
            || (call.callee == rewrite.startCoroutineUninterceptedOrReturnNoReceiverCallee
                && call.arguments.count == 3)
        {
            contextArgument = call.arguments[1]
            call = CallRewriteInput(
                instruction: call.instruction,
                symbol: call.symbol,
                callee: call.callee,
                arguments: [call.arguments[0]] + call.arguments.dropFirst(2),
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult,
                isSuperCall: call.isSuperCall
            )
        }
        guard call.callee == rewrite.startCoroutineUninterceptedOrReturnCallee
                || call.callee == rewrite.startCoroutineUninterceptedOrReturnNoReceiverCallee
                || call.callee == rewrite.startCoroutineUninterceptedOrReturnWithReceiverCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            // A dynamic suspend callable has no compiler-known entry point, so
            // it must use the boxed-function runtime bridge. Public inline
            // wrappers can leave the source intrinsic name here, while KLIB
            // bodies retain the explicit link-only marker name.
            let dynamicCallee: InternedString
            let dynamicArguments: [KIRExprID]
            let preserveSymbol: SymbolID?
            switch (call.callee, call.arguments.count) {
            case (rewrite.startCoroutineUninterceptedOrReturnCallee, 2):
                dynamicCallee = rewrite.startCoroutineUninterceptedOrReturnNoReceiverCallee
                dynamicArguments = call.arguments
                preserveSymbol = nil
            case (rewrite.startCoroutineUninterceptedOrReturnCallee, 3):
                dynamicCallee = rewrite.startCoroutineUninterceptedOrReturnWithReceiverCallee
                dynamicArguments = call.arguments
                preserveSymbol = nil
            case (rewrite.startCoroutineUninterceptedOrReturnNoReceiverCallee, 2),
                 (rewrite.startCoroutineUninterceptedOrReturnWithReceiverCallee, 3):
                dynamicCallee = call.callee
                dynamicArguments = call.arguments
                preserveSymbol = call.symbol
            default:
                return nil
            }
            let unusedContext = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            return [
                .constValue(result: unusedContext, value: .intLiteral(0)),
                .call(
                    symbol: preserveSymbol, callee: dynamicCallee,
                    arguments: [dynamicArguments[0], unusedContext] + Array(dynamicArguments.dropFirst()),
                    result: call.result, canThrow: call.canThrow,
                    thrownResult: call.thrownResult
                ),
            ]
        }

        let launcherArguments = resolvedLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            contextArgument: contextArgument,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3 || !launcherArguments.isEmpty,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false
            ),
        ]

        appendCapturedLauncherArgumentSetup(
            launcherArguments,
            continuationExpr: continuationExpr,
            using: rewrite,
            into: &rewritten
        )

        rewritten.append(
            .call(
                callee: rewrite.runtimeStartCoroutineUninterceptedOrReturnCallee,
                arguments: [entryPointExpr, continuationExpr],
                result: call.result,
                canThrow: true,
                thrownResult: call.thrownResult
            )
        )
        return rewritten
    }

    func rewriteStartCoroutineCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        if hasRealDeclaration(call.symbol, in: rewrite.ctx) {
            return nil
        }
        guard call.callee == rewrite.startCoroutineCallee,
              call.arguments.count == 2 || call.arguments.count == 3
        else {
            return nil
        }

        guard let referencedSymbol = symbolReference(
            for: call.arguments[0],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        ),
        let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )
        let unitExpr = rewrite.module.arena.appendExpr(
            .unit,
            type: rewrite.unitType
        )

        let launcherArguments = resolvedLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            contextArgument: nil,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3 || !launcherArguments.isEmpty,
            using: rewrite
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false
            ),
        ]

        appendCapturedLauncherArgumentSetup(
            launcherArguments,
            continuationExpr: continuationExpr,
            using: rewrite,
            into: &rewritten
        )

        rewritten.append(
            .call(callee: rewrite.runtimeContinuationResumeCallee, arguments: [continuationExpr, unitExpr], result: nil, canThrow: false)
        )

        if let result = call.result {
            rewritten.append(.constValue(result: result, value: .unit))
        }
        return rewritten
    }

    /// A resolved suspend callable's launcher thunk reads the suspend
    /// function's original parameters straight from the continuation's
    /// launcher slots, so the explicit receiver that the
    /// `createCoroutineUnintercepted` / `startCoroutine` family passes must
    /// land at the slot matching its parameter position — not always slot 0.
    /// The returned list is written positionally into launcher slots.
    ///
    /// A suspend function *value* (`kk_function_create_N(adapter, env)`,
    /// rewritten to `kk_suspend_function_create`) reaches the thunk as a
    /// `kk_function_value_adapter_*` whose leading slot is the callable's
    /// closure environment: the kklib marker's `(fnPtr, context)` pair
    /// carries it as `contextArgument`, while a source-level box records it
    /// as the callable's single capture argument. This mirrors the runtime's
    /// `createCoroutineFromFunctionValue`, which seeds the launcher args
    /// `[closureRaw, receiver]`. A raw suspend callable instead keeps its
    /// captures in the leading slots (capture-first ABI), or follows the
    /// receiver-first layout launcher-marked literals use.
    private func resolvedLauncherArguments(
        for call: CallRewriteInput,
        referencedSymbol: SymbolID,
        contextArgument: KIRExprID?,
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRExprID] {
        guard rewrite.launcherThunkByOriginalSymbol[referencedSymbol] != nil else {
            return []
        }
        let callableInfo = rewrite.module.arena.callableValueInfo(for: call.arguments[0])
            ?? functionValueInfoByExprRaw[call.arguments[0].rawValue]
        let receiverArgument: KIRExprID? = call.arguments.count == 3 ? call.arguments[1] : nil

        if isFunctionValueAdapterSymbol(referencedSymbol, using: rewrite) {
            // The adapter thunk's leading slot is the callable box's
            // `closureRaw` — the environment object its body unpacks. A
            // source-level box records it as the callable's single capture
            // argument; the kklib marker path instead carries a placeholder
            // context slot, so recover the environment from the
            // `kk_function_create_*` producer recorded for the box.
            let environment = callableInfo?.captureArguments.first
                ?? functionValueInfoByExprRaw.values
                    .first(where: { $0.symbol == referencedSymbol })
                    .flatMap(\.captureArguments.first)
                ?? contextArgument
            var arguments = environment.map { [$0] } ?? []
            if let receiverArgument {
                arguments.append(receiverArgument)
            }
            return arguments
        }

        let captures = callableInfo?.captureArguments
            ?? rewrite.module.arena.lambdaCaptureArgsBySymbol[referencedSymbol]
            ?? []

        guard let receiverArgument else {
            return captures
        }
        if rewrite.module.arena.receiverFirstLauncherLambdaSymbols.contains(referencedSymbol) {
            // Launcher-marked literals lower receiver-first:
            // `[receiver, cap0..capN]`.
            return [receiverArgument] + captures
        }
        // Capture-first suspend callables forward each capture in the leading
        // slots; a hasClosureParam value folds them into a single environment
        // slot — the marker pair's context argument.
        let leadingSlotCount = (rewrite.module.arena.function(for: referencedSymbol)?.params.count ?? 0) - 1
        if captures.count == leadingSlotCount {
            return captures + [receiverArgument]
        }
        if leadingSlotCount == 1, let contextArgument {
            return [contextArgument, receiverArgument]
        }
        return [receiverArgument]
    }

    private func appendCapturedLauncherArgumentSetup(
        _ captureArguments: [KIRExprID],
        continuationExpr: KIRExprID,
        using rewrite: SuspendRewriteContext,
        into rewritten: inout [KIRInstruction]
    ) {
        for (index, argExpr) in captureArguments.enumerated() {
            let slotExpr = rewrite.module.arena.appendExpr(
                .intLiteral(Int64(index)),
                type: rewrite.intType
            )
            rewritten.append(.call(
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false
            ))
        }
    }

    func entryPointSymbol(
        for referencedSymbol: SymbolID,
        loweredTarget: LoweredSuspendFunction,
        hasLauncherArg: Bool,
        using rewrite: SuspendRewriteContext
    ) -> SymbolID {
        if hasLauncherArg,
           let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol]
        {
            return thunk.symbol
        }
        return loweredTarget.symbol
    }
}
