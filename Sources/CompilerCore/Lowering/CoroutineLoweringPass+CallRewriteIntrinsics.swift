
extension CoroutineLoweringPass {
    func rewriteYieldCall(
        call: CallRewriteInput,
        using rewrite: SuspendRewriteContext
    ) -> KIRInstruction? {
        guard call.callee == rewrite.yieldCallee else {
            return nil
        }
        return .call(
            symbol: nil,
            callee: rewrite.runtimeYieldCallee,
            arguments: call.arguments,
            result: call.result,
            canThrow: false,
            thrownResult: nil
        )
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
        // below re-adds it when the function cannot be resolved.
        if (call.callee == rewrite.createCoroutineUninterceptedWithReceiverCallee
                && call.arguments.count == 4)
            || (call.callee == rewrite.createCoroutineUninterceptedNoReceiverCallee
                && call.arguments.count == 3)
        {
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

        let capturedLauncherArguments = capturedLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3 || !capturedLauncherArguments.isEmpty,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = call.result ?? rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            )
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        appendCapturedLauncherArgumentSetup(
            capturedLauncherArguments,
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
        // function argument.
        if (call.callee == rewrite.startCoroutineUninterceptedOrReturnWithReceiverCallee
                && call.arguments.count == 4)
            || (call.callee == rewrite.startCoroutineUninterceptedOrReturnNoReceiverCallee
                && call.arguments.count == 3)
        {
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
            // Standalone inline bodies retain these link-only markers when the
            // suspend callable is a parameter rather than a known entry point.
            // Preserve the boxed value and supply the unused context slot, just
            // as the create markers do, so their calls match the runtime ABI.
            guard call.callee == rewrite.startCoroutineUninterceptedOrReturnNoReceiverCallee
                    || call.callee == rewrite.startCoroutineUninterceptedOrReturnWithReceiverCallee else {
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

        let capturedLauncherArguments = capturedLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3 || !capturedLauncherArguments.isEmpty,
            using: rewrite
        )
        let entryPointExpr = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.anyType
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        appendCapturedLauncherArgumentSetup(
            capturedLauncherArguments,
            continuationExpr: continuationExpr,
            using: rewrite,
            into: &rewritten
        )

        rewritten.append(
            .call(
                symbol: nil,
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

        let capturedLauncherArguments = capturedLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let entryPointSymbol = entryPointSymbol(
            for: referencedSymbol,
            loweredTarget: loweredTarget,
            hasLauncherArg: call.arguments.count == 3 || !capturedLauncherArguments.isEmpty,
            using: rewrite
        )

        var rewritten: [KIRInstruction] = [
            .constValue(result: entryPointExpr, value: .symbolRef(entryPointSymbol)),
            .call(
                symbol: nil,
                callee: rewrite.runtimeCreateCoroutineUninterceptedCallee,
                arguments: [entryPointExpr, call.arguments[call.arguments.count - 1]],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        if call.arguments.count == 3 {
            let slotExpr = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            rewritten.append(
                .call(
                    symbol: nil,
                    callee: rewrite.launcherArgSetCallee,
                    arguments: [continuationExpr, slotExpr, call.arguments[1]],
                    result: nil,
                    canThrow: false,
                    thrownResult: nil
                )
            )
        }

        appendCapturedLauncherArgumentSetup(
            capturedLauncherArguments,
            continuationExpr: continuationExpr,
            using: rewrite,
            into: &rewritten
        )

        rewritten.append(
            .call(
                symbol: nil,
                callee: rewrite.runtimeContinuationResumeCallee,
                arguments: [continuationExpr, unitExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
            )
        )

        if let result = call.result {
            rewritten.append(.constValue(result: result, value: .unit))
        }
        return rewritten
    }

    /// A capturing suspend lambda reaches these entry-point intrinsics as a function
    /// value (`kk_function_create_N(adapter, closureState)`). The adapter's suspend
    /// body reads that closure state from its first parameter, so starting it
    /// through the bare entry point (which only supplies the continuation) would
    /// hand it garbage. Returns the closure arguments that must be threaded through
    /// the launcher thunk; empty when the lambda captures nothing, has no thunk, or
    /// already uses slot 0 for an explicit receiver.
    private func capturedLauncherArguments(
        for call: CallRewriteInput,
        referencedSymbol: SymbolID,
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRExprID] {
        guard call.arguments.count == 2,
              rewrite.launcherThunkByOriginalSymbol[referencedSymbol] != nil,
              let callableInfo = rewrite.module.arena.callableValueInfo(for: call.arguments[0])
              ?? functionValueInfoByExprRaw[call.arguments[0].rawValue]
        else {
            return []
        }
        return callableInfo.captureArguments
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
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, argExpr],
                result: nil,
                canThrow: false,
                thrownResult: nil
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
