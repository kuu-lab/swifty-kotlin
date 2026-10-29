extension CallTypeChecker {
    /// A scoped user extension takes priority over the primitive fallback.
    func hasUserFloorDivExtension(
        _ request: MemberCallInferenceRequest,
        lookupReceiverType: TypeID,
        argTypes: [TypeID],
        locals: LocalBindings
    ) -> Bool {
        let ctx = request.ctx
        let sema = ctx.sema
        let interner = ctx.interner
        let receiver = sema.types.makeNonNullable(lookupReceiverType)
        guard case .primitive = sema.types.kind(of: receiver) else { return false }
        let candidates = collectExtensionCallCandidates(
            named: request.calleeName,
            memberLookupType: lookupReceiverType,
            isSuperCall: false,
            supertypeSymbols: [],
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner,
            callShapeMatches: {
                self.extensionCandidateMatchesCallShape(
                    $0, request: request, argumentTypes: argTypes, receiverType: lookupReceiverType
                )
            },
            requiresInfix: ctx.ast.arena.isInfixCall(request.id)
        )
        return candidates.contains { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  ctx.visibilityChecker.isAccessible(
                      symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                  ),
                  extensionCandidateMatchesCallShape(
                      candidate, request: request, argumentTypes: argTypes, receiverType: lookupReceiverType
                  )
            else { return false }
            if let file = symbol.declSite?.start.file, let origin = driver.sourceManager?.origin(of: file) {
                return origin == .user
            }
            return symbol.fqName.first != interner.intern("kotlin")
        }
    }
}
