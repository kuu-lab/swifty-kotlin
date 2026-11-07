extension CallTypeChecker {
    /// A scoped user extension takes priority over the primitive fallback.
    func hasUserFloorDivExtension(
        _ request: MemberCallInferenceRequest,
        lookupReceiverType: TypeID,
        argTypes: [TypeID],
        locals: LocalBindings
    ) -> Bool {
        let receiver = request.sema.types.makeNonNullable(lookupReceiverType)
        guard case .primitive = request.sema.types.kind(of: receiver) else { return false }
        let candidates = collectExtensionCallCandidates(
            named: request.calleeName,
            memberLookupType: lookupReceiverType,
            isSuperCall: false,
            supertypeSymbols: [],
            ctx: request.ctx,
            locals: locals,
            sema: request.sema,
            interner: request.interner,
            callShapeMatches: {
                self.extensionCandidateMatchesCallShape(
                    $0, request: request, argumentTypes: argTypes, receiverType: lookupReceiverType
                )
            },
            requiresInfix: request.ctx.ast.arena.isInfixCall(request.id)
        )
        return candidates.contains { candidate in
            guard let symbol = request.sema.symbols.symbol(candidate),
                  request.ctx.visibilityChecker.isAccessible(
                      symbol, fromFile: request.ctx.currentFileID, enclosingClass: request.ctx.enclosingClassSymbol
                  ),
                  extensionCandidateMatchesCallShape(
                      candidate, request: request, argumentTypes: argTypes, receiverType: lookupReceiverType
                  )
            else { return false }
            if let file = symbol.declSite?.start.file, let origin = driver.sourceManager?.origin(of: file) {
                return origin == .user
            }
            return symbol.fqName.first != request.interner.intern("kotlin")
        }
    }
}
