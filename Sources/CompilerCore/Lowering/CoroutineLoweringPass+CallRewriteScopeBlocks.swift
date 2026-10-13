
extension CoroutineLoweringPass {
    func rewriteWithContextCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.callee == rewrite.withContextCallee,
              call.arguments.count >= 2,
              let referencedSymbol = symbolReference(
                  for: call.arguments[1],
                  module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ) ?? functionValueInfoByExprRaw[call.arguments[1].rawValue]?.symbol,
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }

        let dispatcherExpr = call.arguments[0]
        let extraArgs = blockLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0004",
                "withContext block capture arity mismatch.",
                range: nil
            )
            return [call.instruction]
        }

        let entryTarget: LoweredSuspendFunction
        var rewritten: [KIRInstruction] = []
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        if extraArgs.isEmpty {
            entryTarget = loweredTarget
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol] else {
                return [call.instruction]
            }
            entryTarget = thunk
        }

        rewritten.append(.constValue(
            result: continuationFunctionID,
            value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
        ))
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.continuationFactory,
            arguments: [continuationFunctionID],
            result: continuationExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, argExpr) in extraArgs.enumerated() {
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

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryTarget.symbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.runtimeWithContextCallee,
            arguments: [dispatcherExpr, entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return rewritten
    }

    func rewriteWithTimeoutCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        // KSP-1566: bundled kotlinx declarations surface here under several
        // spellings — the Kotlin name for source-injected calls, the
        // `kk_fn_*` linkname for kklib-imported overloads, and the runtime
        // `kk_with_timeout*` linkname for the `external` declarations.
        let calleeName = rewrite.ctx.interner.resolve(call.callee)
        let runtimeCallee: InternedString
        if calleeName == "withTimeoutOrNull"
            || calleeName.hasPrefix("withTimeoutOrNull_")
            || calleeName.hasPrefix("kk_fn_withTimeoutOrNull_")
            || calleeName.hasPrefix("kk_suspend_withTimeoutOrNull")
            || call.callee == rewrite.runtimeWithTimeoutOrNullCallee
        {
            runtimeCallee = rewrite.runtimeWithTimeoutOrNullCallee
        } else if calleeName == "withTimeout"
            || calleeName.hasPrefix("withTimeout_")
            || calleeName.hasPrefix("kk_fn_withTimeout_")
            || calleeName.hasPrefix("kk_suspend_withTimeout")
            || call.callee == rewrite.runtimeWithTimeoutCallee
        {
            runtimeCallee = rewrite.runtimeWithTimeoutCallee
        } else {
            return nil
        }

        guard call.arguments.count >= 2 else {
            return nil
        }

        // KSP-1566: adapt Duration's tagged payload to the coroutine runtime's
        // millisecond ABI. Long/Int arguments already contain milliseconds.
        var timeMillisExpr = call.arguments[0]
        var rewritten: [KIRInstruction] = []
        if let argType = rewrite.module.arena.exprType(timeMillisExpr) {
            let longType = rewrite.ctx.sema?.types.make(.primitive(.long, .nonNull))
            if argType != longType, argType != rewrite.intType {
                let millisExpr = rewrite.module.arena.appendTemporary(type: longType)
                rewritten.append(.call(
                    symbol: nil,
                    callee: rewrite.ctx.interner.intern("kk_duration_inWholeMilliseconds"),
                    arguments: [timeMillisExpr],
                    result: millisExpr,
                    canThrow: false,
                    thrownResult: nil,
                    isSuperCall: false
                ))
                timeMillisExpr = millisExpr
            }
        }

        let referencedSymbol = symbolReference(
            for: call.arguments[1],
            module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        )
        guard let referencedSymbol,
              let loweredTarget = rewrite.loweredBySymbol[referencedSymbol]
        else {
            return nil
        }
        let extraArgs = blockLauncherArguments(
            for: call,
            referencedSymbol: referencedSymbol,
            functionValueInfoByExprRaw: functionValueInfoByExprRaw,
            using: rewrite
        )
        let targetArity = rewrite.suspendFunctionArityBySymbol[referencedSymbol] ?? 0
        guard extraArgs.count == targetArity else {
            rewrite.ctx.diagnostics.error(
                "KSWIFTK-CORO-0005",
                "withTimeout block capture arity mismatch.",
                range: nil
            )
            return [call.instruction]
        }

        let entryTarget: LoweredSuspendFunction
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        let continuationExpr = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        if extraArgs.isEmpty {
            entryTarget = loweredTarget
        } else {
            guard let thunk = rewrite.launcherThunkByOriginalSymbol[referencedSymbol] else {
                return [call.instruction]
            }
            entryTarget = thunk
        }

        rewritten.append(.constValue(
            result: continuationFunctionID,
            value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
        ))
        rewritten.append(.call(
            symbol: nil,
            callee: rewrite.continuationFactory,
            arguments: [continuationFunctionID],
            result: continuationExpr,
            canThrow: false,
            thrownResult: nil
        ))

        for (index, argExpr) in extraArgs.enumerated() {
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

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryTarget.symbol),
            type: rewrite.intType
        )
        rewritten.append(.call(
            symbol: nil,
            callee: runtimeCallee,
            arguments: [timeMillisExpr, entryPointExpr, continuationExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return rewritten
    }

    private func blockLauncherArguments(
        for call: CallRewriteInput,
        referencedSymbol: SymbolID,
        functionValueInfoByExprRaw: [Int32: KIRCallableValueInfo],
        using rewrite: SuspendRewriteContext
    ) -> [KIRExprID] {
        if call.arguments.count > 2 {
            return Array(call.arguments.dropFirst(2))
        }
        guard let callableInfo = rewrite.module.arena.callableValueInfo(for: call.arguments[1])
            ?? functionValueInfoByExprRaw[call.arguments[1].rawValue],
            callableInfo.symbol == referencedSymbol
        else { return [] }
        return callableInfo.captureArguments
    }
}
