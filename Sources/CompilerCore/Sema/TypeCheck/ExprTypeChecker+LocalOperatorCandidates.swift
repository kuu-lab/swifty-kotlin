extension ExprTypeChecker {
    /// Local functions live in `LocalBindings` rather than the lexical scope
    /// chain. Keep their operator extensions at the local extension tier and
    /// leave inapplicable candidates to the next scope tier.
    func collectLocalOperatorExtensionCandidates(
        names: [InternedString],
        receiverType: TypeID,
        call: CallExpr? = nil,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        guard receiverType != sema.types.errorType else { return [] }

        var candidates: [SymbolID] = []
        for name in names {
            guard let local = locals[name],
                  let symbol = ctx.cachedSymbol(local.symbol),
                  symbol.kind == .function,
                  symbol.flags.contains(.localFunction),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: local.symbol),
                  let declaredReceiver = signature.receiverType,
                  driver.helpers.declaresExtensionReceiver(local.symbol, sema: sema, interner: ctx.interner),
                  !isHiddenByDeprecationOrVersionAnnotation(local.symbol, symbols: sema.symbols),
                  ctx.visibilityChecker.isAccessible(
                      symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                  ),
                  !(symbol.flags.contains(.expectDeclaration) && sema.symbols.actualSymbol(for: local.symbol) != nil),
                  driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                      callSiteReceiver: sema.types.makeNonNullable(receiverType),
                      declaredReceiver: declaredReceiver,
                      sema: sema
                  )
            else {
                continue
            }

            if let call,
               ctx.resolver.probeCall(
                   candidates: [local.symbol], call: call, expectedType: nil,
                   implicitReceiverType: receiverType, ctx: sema
               ).viableCandidates.isEmpty
            {
                continue
            }
            candidates.append(local.symbol)
        }
        return candidates
    }
}
