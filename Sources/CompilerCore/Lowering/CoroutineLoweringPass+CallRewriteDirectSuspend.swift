
extension CoroutineLoweringPass {
    func rewriteSuspendFunctionValueCreation(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        let name = rewrite.ctx.interner.resolve(call.callee)
        guard name.hasPrefix("kk_function_create_"),
              let arity = Int(name.dropFirst("kk_function_create_".count)),
              call.arguments.count == 2,
              let original = symbolReference(
                  for: call.arguments[0], module: rewrite.module, propagatedSymbols: symbolByExprRaw
              ),
              let thunk = rewrite.launcherThunkByOriginalSymbol[original]
        else { return nil }

        let entry = rewrite.module.arena.appendExpr(.symbolRef(thunk.symbol), type: rewrite.intType)
        let arityExpr = rewrite.module.arena.appendExpr(.intLiteral(Int64(arity)), type: rewrite.intType)
        return [
            .constValue(result: entry, value: .symbolRef(thunk.symbol)),
            .constValue(result: arityExpr, value: .intLiteral(Int64(arity))),
            .call(
                symbol: nil, callee: rewrite.ctx.interner.intern("kk_suspend_function_create"),
                arguments: call.arguments + [arityExpr, entry], result: call.result,
                canThrow: false, thrownResult: nil
            ),
        ]
    }

    func rewriteDirectSuspendCall(
        call: CallRewriteInput,
        callerContinuationSymbol: SymbolID?,
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard let loweredTarget = resolveLoweredTarget(
            symbol: call.symbol,
            callee: call.callee,
            arity: call.arguments.count,
            using: rewrite
        ) else {
            return nil
        }
        let continuationFunctionID = rewrite.module.arena.appendTemporary(type: rewrite.intType
        )
        // Synthetic KIR fixtures and non-suspend callers do not carry a lowered
        // caller continuation. Preserve their historical continuation argument
        // shape; only lowered suspend bodies can use the relay ABI below.
        guard let callerContinuationSymbol else {
            let continuationTemp = rewrite.module.arena.appendTemporary(
                type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
            )
            return [
                .constValue(
                    result: continuationFunctionID,
                    value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
                ),
                .call(
                    symbol: nil,
                    callee: rewrite.continuationFactory,
                    arguments: [continuationFunctionID],
                    result: continuationTemp,
                    canThrow: false,
                    thrownResult: nil
                ),
                .call(
                    symbol: loweredTarget.symbol,
                    callee: loweredTarget.name,
                    arguments: call.arguments + [continuationTemp],
                    result: call.result,
                    canThrow: call.canThrow,
                    thrownResult: call.thrownResult,
                    isSuperCall: call.isSuperCall
                ),
            ]
        }

        // STDLIB-CORO-BUG-01: a direct call from one suspend function's body to
        // another must relay the callee's completion back into this function's
        // own suspend point through kk_coroutine_call_direct_suspend.
        let childContinuationTemp = rewrite.module.arena.appendTemporary(type: rewrite.continuationTypeByLoweredSymbol[loweredTarget.symbol] ?? rewrite.anyType
        )

        var instructions: [KIRInstruction] = [
            .constValue(
                result: continuationFunctionID,
                value: .intLiteral(Int64(loweredTarget.symbol.rawValue))
            ),
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [continuationFunctionID],
                result: childContinuationTemp,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        // A suspend function with parameters is invoked through its launcher
        // thunk (the same adapter launch/async/runBlocking use), which reads
        // the real arguments back out of the child continuation's launcher-arg
        // storage. A 0-arg suspend function's lowered form already matches the
        // (continuation) -> Int entry-point shape directly.
        let entryPointSymbol: SymbolID
        if call.arguments.isEmpty {
            entryPointSymbol = loweredTarget.symbol
        } else {
            let originalSymbol = call.symbol ?? rewrite.originalByLoweredName[loweredTarget.name]?.original
            guard let originalSymbol,
                  let thunk = rewrite.launcherThunkByOriginalSymbol[originalSymbol]
            else {
                return nil
            }
            entryPointSymbol = thunk.symbol
            for (index, argumentExpr) in call.arguments.enumerated() {
                let slotExpr = rewrite.module.arena.appendExpr(
                    .intLiteral(Int64(index)),
                    type: rewrite.intType
                )
                instructions.append(
                    .call(
                        symbol: nil,
                        callee: rewrite.launcherArgSetCallee,
                        arguments: [childContinuationTemp, slotExpr, argumentExpr],
                        result: nil,
                        canThrow: false,
                        thrownResult: nil
                    )
                )
            }
        }

        let entryPointExpr = rewrite.module.arena.appendExpr(
            .symbolRef(entryPointSymbol),
            type: rewrite.intType
        )
        let callerContinuationExpr = rewrite.module.arena.appendExpr(
            .symbolRef(callerContinuationSymbol),
            type: rewrite.anyType
        )
        instructions.append(
            .call(
                symbol: nil,
                callee: rewrite.directSuspendCallCallee,
                arguments: [entryPointExpr, childContinuationTemp, callerContinuationExpr],
                result: call.result,
                canThrow: false,
                thrownResult: nil,
                isSuperCall: call.isSuperCall
            )
        )
        return instructions
    }

    func resolveLoweredTarget(
        symbol: SymbolID?,
        callee: InternedString,
        arity: Int,
        using rewrite: SuspendRewriteContext
    ) -> LoweredSuspendFunction? {
        // Source-backed SequenceScope declarations provide the signature for
        // boxing, but builder bridges already implement their suspension ABI.
        // Rebinding them to the source suspend body would discard each yield.
        guard callee != rewrite.sequenceBuilderYieldCallee,
              callee != rewrite.sequenceBuilderYieldAllCallee,
              callee != rewrite.ctx.interner.intern("__kk_deep_recursive_scope_callRecursive"),
              callee != rewrite.ctx.interner.intern("__kk_deep_recursive_function_callRecursive")
        else { return nil }
        if let symbol {
            if let loweredBySymbol = rewrite.loweredBySymbol[symbol] {
                return loweredBySymbol
            }
            // Name/arity fallback is only valid for unresolved/runtime calls.
            // A resolved non-suspend declaration must not be rebound to the
            // unique suspend function with the same name (for example,
            // kotlin.ranges.toList versus Flow.toList after KSP-499).
            if let signature = rewrite.ctx.sema?.symbols.functionSignature(for: symbol),
               !signature.isSuspend
            {
                return nil
            }
        }
        let byNameArityKey = SuspendCallLookupKey(name: callee, arity: arity)
        if let loweredByNameArity = rewrite.loweredByUniqueNameArity[byNameArityKey] {
            return loweredByNameArity
        }
        return rewrite.loweredByUniqueName[callee]
    }
}
