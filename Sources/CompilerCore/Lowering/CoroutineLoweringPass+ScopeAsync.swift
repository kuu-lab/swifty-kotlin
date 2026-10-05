extension CoroutineLoweringPass {
    /// Rewrites `kk_coroutine_scope_async(scope, context, start, block, captures...)`.
    ///
    /// The bundled `CoroutineScope.async` contract is
    /// `block: suspend CoroutineScope.() -> T` — the block's `this` binds to
    /// the receiver scope — so the block uses the same dual-shape receiver
    /// ABI `rewriteTestScopeRunBlockingCall` emits for `runTest`:
    ///  - A suspend block that resolves to a suspend symbol rewrites into the
    ///    launcher continuation convention. Captures occupy launcherArgs —
    ///    slots 1... for launcher-marked literals lowered receiver-first
    ///    (`[receiver, cap0..capN]`), slots 0... for unmarked suspend values
    ///    lowered captures-first (`[cap0..capN, receiver]`) — and the runtime
    ///    writes the receiver scope handle into the suspend-entry receiver
    ///    slot named by `scopeSlot`.
    ///  - A block that does not resolve (a suspend function *value* stored in
    ///    a variable or forwarded from another call) stays on the boxed
    ///    function-value path: `kk_coroutine_scope_async` expands env into
    ///    positional captures and invokes `(cap0..capN, receiver, outThrown)`,
    ///    mirroring `rewriteProduceLaunchFunctionValueCall`. The value's env
    ///    slot is materialized from the argument's callable info when present.
    func rewriteCoroutineScopeAsyncCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.arguments.count >= 4 else { return nil }
        let arena = rewrite.module.arena
        var arguments = call.arguments
        if let mode = coroutineStartEntryName(arguments[2], symbolByExprRaw: symbolByExprRaw, using: rewrite) {
            let ordinal: Int64 = switch mode {
            case "LAZY": 1
            case "ATOMIC": 2
            case "UNDISPATCHED": 3
            default: 0
            }
            arguments[2] = arena.appendExpr(.intLiteral(ordinal), type: rewrite.intType)
        }
        let suspendArgExpr = call.arguments[3]
        guard let symbol = symbolReference(
                  for: suspendArgExpr, module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let lowered = rewrite.loweredBySymbol[symbol],
              let thunk = rewrite.launcherThunkByOriginalSymbol[symbol]
        else {
            let entryExpr: KIRExprID
            let envExpr: KIRExprID
            var instructions: [KIRInstruction] = []
            if let callableInfo = arena.callableValueInfo(for: suspendArgExpr) {
                entryExpr = arena.appendTemporary(type: rewrite.intType)
                instructions.append(.constValue(
                    result: entryExpr,
                    value: .symbolRef(callableInfo.symbol)
                ))
                switch callableInfo.captureArguments.count {
                case 0:
                    envExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
                    instructions.append(.constValue(result: envExpr, value: .intLiteral(0)))
                default:
                    envExpr = emitPackedCaptureEnvironment(
                        callableInfo.captureArguments,
                        using: rewrite,
                        into: &instructions
                    )
                }
            } else {
                entryExpr = suspendArgExpr
                envExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
                instructions.append(.constValue(result: envExpr, value: .intLiteral(0)))
            }
            instructions.append(.call(
                symbol: call.symbol,
                callee: call.callee,
                arguments: Array(arguments.prefix(3)) + [entryExpr, envExpr],
                result: call.result,
                canThrow: call.canThrow,
                thrownResult: call.thrownResult
            ))
            return instructions
        }

        // Captures either arrive flattened as trailing call args or ride
        // inside the suspend value's callable info — use whichever form the
        // emitter produced.
        let trailingCaptures = Array(call.arguments.dropFirst(4))
        let captures: [KIRExprID] = trailingCaptures.isEmpty
            ? (arena.callableValueInfo(for: suspendArgExpr)?.captureArguments ?? [])
            : trailingCaptures

        let receiverFirst = arena.receiverFirstLauncherLambdaSymbols.contains(symbol)
        let suspendParamCount = arena.function(for: symbol)?.params.count
            ?? (captures.count + 1)
        let scopeSlot = receiverFirst ? 0 : suspendParamCount - 1
        guard scopeSlot >= 0 else {
            return nil
        }

        let functionIDExpr = arena.appendExpr(
            .intLiteral(Int64(lowered.symbol.rawValue)), type: rewrite.intType
        )
        let continuationExpr = arena.appendTemporary(type: rewrite.intType)
        let zeroExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
        var instructions: [KIRInstruction] = [
            .call(
                symbol: nil,
                callee: rewrite.continuationFactory,
                arguments: [functionIDExpr],
                result: continuationExpr,
                canThrow: false,
                thrownResult: nil
            ),
        ]

        func appendLauncherArgSet(_ slot: Int, _ value: KIRExprID) {
            let slotExpr = arena.appendExpr(.intLiteral(Int64(slot)), type: rewrite.intType)
            instructions.append(.call(
                symbol: nil,
                callee: rewrite.launcherArgSetCallee,
                arguments: [continuationExpr, slotExpr, value],
                result: nil,
                canThrow: false,
                thrownResult: nil
            ))
        }

        if receiverFirst {
            for (index, capture) in captures.enumerated() {
                appendLauncherArgSet(index + 1, capture)
            }
        } else {
            for index in 0..<scopeSlot {
                appendLauncherArgSet(index, index < captures.count ? captures[index] : zeroExpr)
            }
        }
        // Reserve the receiver slot so launcherArgs is sized for it; the
        // runtime overwrites it with the receiver scope handle.
        appendLauncherArgSet(scopeSlot, zeroExpr)

        let entryExpr = arena.appendTemporary(type: rewrite.intType)
        let scopeSlotExpr = arena.appendExpr(.intLiteral(Int64(scopeSlot)), type: rewrite.intType)
        instructions.append(.constValue(result: entryExpr, value: .symbolRef(thunk.symbol)))
        instructions.append(.call(
            symbol: nil,
            callee: rewrite.ctx.interner.intern("kk_coroutine_scope_async_with_cont"),
            arguments: Array(arguments.prefix(3)) + [entryExpr, continuationExpr, scopeSlotExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return instructions
    }
}
