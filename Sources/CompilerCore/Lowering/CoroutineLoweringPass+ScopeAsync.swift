extension CoroutineLoweringPass {
    /// Rewrites receiver-bearing async/launch builders with the shared
    /// `(scope, context, start, block, captures...)` source argument layout.
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
        let callableInfo = arena.callableValueInfo(for: suspendArgExpr)
        var suspendSymbol = symbolReference(
            for: suspendArgExpr, module: rewrite.module,
            propagatedSymbols: symbolByExprRaw
        )
        // A block that resolves to a `kk_function_value_adapter_*` symbol (the
        // materialization of a stored `suspend CoroutineScope.() -> T` value)
        // keeps its captures inside the boxed value: its invoke ABI is
        // `(closureEnv, receiver, outThrown)`, not per-capture launcherArgs —
        // so it must stay on the boxed path.
        if let symbol = suspendSymbol,
           isFunctionValueAdapterSymbol(symbol, using: rewrite) {
            suspendSymbol = nil
        }
        // A literal block that reached the member overload through expected-type
        // inference (e.g. `val d: Deferred<Int> = async { ... }`, resolved via
        // the implicit receiver) carries no propagated symbol on its arg expr;
        // recover the suspend symbol from the callable info so it still takes
        // the launcher continuation path — the boxed path would invoke its
        // `(params, continuation)` ABI as a value thunk and corrupt the scope.
        if suspendSymbol == nil,
           let info = callableInfo,
           !isFunctionValueAdapterSymbol(info.symbol, using: rewrite),
           rewrite.loweredBySymbol[info.symbol] != nil {
            suspendSymbol = info.symbol
        }
        guard let symbol = suspendSymbol,
              let lowered = rewrite.loweredBySymbol[symbol]
        else {
            let entryExpr: KIRExprID
            let envExpr: KIRExprID
            var instructions: [KIRInstruction] = []
            if let info = callableInfo,
               !isFunctionValueAdapterSymbol(info.symbol, using: rewrite) {
                // A non-adapter suspend value whose symbol is not lowered in
                // this module: pass its fnPtr with the packed capture env.
                entryExpr = arena.appendTemporary(type: rewrite.intType)
                instructions.append(.constValue(
                    result: entryExpr,
                    value: .symbolRef(info.symbol)
                ))
                switch info.captureArguments.count {
                case 0:
                    envExpr = arena.appendExpr(.intLiteral(0), type: rewrite.intType)
                    instructions.append(.constValue(result: envExpr, value: .intLiteral(0)))
                default:
                    envExpr = emitPackedCaptureEnvironment(
                        info.captureArguments,
                        using: rewrite,
                        into: &instructions
                    )
                }
            } else {
                // Adapter-valued or opaque values: `suspendArgExpr` evaluates
                // to the FunctionValueBox; the runtime resolves its
                // `(closureEnv, receiver, outThrown)` entry itself.
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
            ? (callableInfo?.captureArguments ?? [])
            : trailingCaptures

        let receiverFirst = arena.receiverFirstLauncherLambdaSymbols.contains(symbol)
        let suspendParamCount = arena.function(for: symbol)?.params.count
            ?? (captures.count + 1)
        // A zero-parameter suspend fn gets no launcher thunk — its
        // `(continuation)` ABI is already the thunk shape — so the lowered
        // symbol itself is the launcher entry.
        let entrySymbol = rewrite.launcherThunkByOriginalSymbol[symbol]?.symbol
            ?? (suspendParamCount == 0 ? lowered.symbol : nil)
        guard let entrySymbol else {
            assertionFailure("Internal compiler error: CoroutineScope.async launcher entry missing")
            return [call.instruction]
        }
        let scopeSlot = receiverFirst ? 0 : max(0, suspendParamCount - 1)

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
        instructions.append(.constValue(result: entryExpr, value: .symbolRef(entrySymbol)))
        instructions.append(.call(
            symbol: nil,
            callee: rewrite.ctx.interner.intern(
                rewrite.ctx.interner.resolve(call.callee) == "__kk_coroutine_scope_launch_context"
                    ? "__kk_coroutine_scope_launch_context_with_cont"
                    : "kk_coroutine_scope_async_with_cont"
            ),
            arguments: Array(arguments.prefix(3)) + [entryExpr, continuationExpr, scopeSlotExpr],
            result: call.result,
            canThrow: call.canThrow,
            thrownResult: call.thrownResult
        ))
        return instructions
    }
}
