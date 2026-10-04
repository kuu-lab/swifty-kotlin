extension CoroutineLoweringPass {
    func rewriteCoroutineScopeAsyncCall(
        call: CallRewriteInput,
        symbolByExprRaw: [Int32: SymbolID],
        using rewrite: SuspendRewriteContext
    ) -> [KIRInstruction]? {
        guard call.arguments.count >= 4 else { return nil }
        var arguments = call.arguments
        if let mode = coroutineStartEntryName(arguments[2], symbolByExprRaw: symbolByExprRaw, using: rewrite) {
            let ordinal: Int64 = switch mode {
            case "LAZY": 1
            case "ATOMIC": 2
            case "UNDISPATCHED": 3
            default: 0
            }
            arguments[2] = rewrite.module.arena.appendExpr(.intLiteral(ordinal), type: rewrite.intType)
        }
        guard let symbol = symbolReference(
                  for: call.arguments[3], module: rewrite.module,
                  propagatedSymbols: symbolByExprRaw
              ),
              let lowered = rewrite.loweredBySymbol[symbol]
        else {
            let environment = rewrite.module.arena.appendExpr(.intLiteral(0), type: rewrite.intType)
            return [.call(
                symbol: nil, callee: call.callee,
                arguments: Array(arguments.prefix(4)) + [environment],
                result: call.result, canThrow: call.canThrow, thrownResult: call.thrownResult
            )]
        }

        let functionID = rewrite.module.arena.appendExpr(
            .intLiteral(Int64(lowered.symbol.rawValue)), type: rewrite.intType
        )
        let continuation = rewrite.module.arena.appendTemporary(type: rewrite.intType)
        var instructions: [KIRInstruction] = [
            .call(symbol: nil, callee: rewrite.continuationFactory,
                  arguments: [functionID], result: continuation,
                  canThrow: false, thrownResult: nil),
        ]
        let trailingCaptures = Array(call.arguments.dropFirst(4))
        let captures = trailingCaptures.isEmpty
            ? (rewrite.module.arena.callableValueInfo(for: call.arguments[3])?.captureArguments ?? [])
            : trailingCaptures
        for (index, capture) in captures.enumerated() {
            let slot = rewrite.module.arena.appendExpr(.intLiteral(Int64(index)), type: rewrite.intType)
            instructions.append(.call(
                symbol: nil, callee: rewrite.launcherArgSetCallee,
                arguments: [continuation, slot, capture], result: nil,
                canThrow: false, thrownResult: nil
            ))
        }
        let entry = rewrite.module.arena.appendTemporary(type: rewrite.intType)
        let entrySymbol = rewrite.launcherThunkByOriginalSymbol[symbol]?.symbol ?? lowered.symbol
        instructions.append(.constValue(result: entry, value: .symbolRef(entrySymbol)))
        instructions.append(.call(
            symbol: nil, callee: rewrite.ctx.interner.intern("kk_coroutine_scope_async_with_cont"),
            arguments: Array(arguments.prefix(3)) + [entry, continuation],
            result: call.result, canThrow: call.canThrow, thrownResult: call.thrownResult
        ))
        return instructions
    }
}
