extension CallTypeChecker {
    func isInheritedNestedClassifier(_ candidate: SymbolID, in ctx: TypeInferenceContext) -> Bool {
        guard let enclosingClass = ctx.enclosingClassSymbol,
              let declaringOwner = ctx.sema.symbols.parentSymbol(for: candidate)
        else {
            return false
        }

        var pendingOwners = ctx.sema.symbols.directSupertypes(for: enclosingClass)
        var visited: Set<SymbolID> = []
        while let owner = pendingOwners.popLast() {
            guard visited.insert(owner).inserted else { continue }
            if owner == declaringOwner {
                return true
            }
            pendingOwners.append(contentsOf: ctx.sema.symbols.directSupertypes(for: owner))
        }
        return false
    }

    func outerScopeClassifiers(
        named name: InternedString,
        in ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let typeKinds: Set<SymbolKind> = [.class, .interface, .enumClass, .annotationClass, .object]
        return ctx.scope.lookupClassifier(name, matching: { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  typeKinds.contains(symbol.kind),
                  !isInheritedNestedClassifier(candidate, in: ctx)
            else {
                return false
            }
            return !symbol.flags.contains(.expectDeclaration)
                || ctx.sema.symbols.actualSymbol(for: candidate) == nil
        })
    }

    func appendClassConstructorCandidates(
        for classID: SymbolID,
        to candidates: inout [SymbolID],
        typeNameCompanionInvokeCandidates: Set<SymbolID>,
        ctx: TypeInferenceContext
    ) -> (visible: [SymbolID], invisible: [SemanticSymbol]) {
        let sema = ctx.sema
        let initName = ctx.interner.intern("<init>")
        guard let classSymbol = ctx.cachedSymbol(classID) else {
            return ([], [])
        }
        let ctorFQName = classSymbol.fqName + [initName]
        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName).filter {
            sema.symbols.parentSymbol(for: $0) == classID
        }
        guard !ctorSymbols.isEmpty else {
            return ([], [])
        }

        let (ctorVis, ctorInvis) = ctx.filterByVisibility(ctorSymbols)
        // Constructors with the same parameter types on different classifiers
        // remain separate candidates. The inherited classifier is preferred
        // when applicable, while its outer-scope fallback is still available
        // when the inherited constructor cannot accept the call.
        let constructorParameterTypes = ctorVis.compactMap {
            sema.symbols.functionSignature(for: $0)?.parameterTypes
        }
        // Synthetic stdlib types can register a constructor with the same
        // signature as a top-level factory function. Hidden compatibility
        // factories remain visible long enough to produce their deprecation
        // diagnostic when called directly, so discard a hidden duplicate only
        // after merging the constructor into this call's candidate set.
        candidates.removeAll { existingID in
            if sema.symbols.symbol(existingID)?.kind == .constructor,
               sema.symbols.parentSymbol(for: existingID) != classID {
                return false
            }
            guard isHiddenByDeprecationOrVersionAnnotation(existingID, symbols: sema.symbols),
                  let signature = sema.symbols.functionSignature(for: existingID)
            else {
                return false
            }
            return constructorParameterTypes.contains(signature.parameterTypes)
        }
        let newCtorVis = ctorVis.filter { ctorID in
            guard let ctorSignature = sema.symbols.functionSignature(for: ctorID) else {
                return true
            }
            // Avoid an indistinguishable top-level factory/constructor pair.
            // Constructors belonging to a different classifier are kept so
            // the inherited tier can suppress them only when it is applicable.
            return !candidates.contains { existingID in
                if sema.symbols.symbol(existingID)?.kind == .constructor,
                   sema.symbols.parentSymbol(for: existingID) != classID {
                    return false
                }
                // A same-signature companion `invoke` is a distinct call
                // target: Kotlin prefers the constructor when applicable,
                // then falls back to `invoke` when it is not.
                return !typeNameCompanionInvokeCandidates.contains(existingID)
                    && sema.symbols.functionSignature(for: existingID)?.parameterTypes
                    == ctorSignature.parameterTypes
            }
        }
        candidates.append(contentsOf: newCtorVis)
        return (newCtorVis, ctorInvis)
    }

    func isLexicallyDeclaredClassifier(_ candidate: SymbolID, in ctx: TypeInferenceContext) -> Bool {
        var lexicalOwners: Set<SymbolID> = []
        var pendingOwners = [ctx.currentDeclSymbol, ctx.enclosingClassSymbol].compactMap { $0 }
        while let owner = pendingOwners.popLast() {
            guard lexicalOwners.insert(owner).inserted else { continue }
            if let parent = ctx.sema.symbols.parentSymbol(for: owner) {
                pendingOwners.append(parent)
            }
        }
        guard let declaringOwner = ctx.sema.symbols.parentSymbol(for: candidate) else {
            return false
        }
        return lexicalOwners.contains(declaringOwner)
    }

    func inheritedNestedClassifiers(
        named name: InternedString,
        in ctx: TypeInferenceContext
    ) -> [SymbolID] {
        guard let enclosingClass = ctx.enclosingClassSymbol else { return [] }

        let sema = ctx.sema
        let typeKinds: Set<SymbolKind> = [.class, .enumClass, .annotationClass, .object]
        var pendingOwners = sema.symbols.directSupertypes(for: enclosingClass)
        var visited: Set<SymbolID> = [enclosingClass]

        while !pendingOwners.isEmpty {
            var nextOwners: [SymbolID] = []
            var matches: [SymbolID] = []
            for ownerID in pendingOwners where visited.insert(ownerID).inserted {
                guard let owner = ctx.cachedSymbol(ownerID) else { continue }
                let nestedFQName = owner.fqName + [name]
                let nestedSymbols = sema.symbols.lookupAll(fqName: nestedFQName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate),
                          typeKinds.contains(symbol.kind),
                          sema.symbols.parentSymbol(for: candidate) == ownerID
                    else { return false }
                    return !symbol.flags.contains(.expectDeclaration)
                        || sema.symbols.actualSymbol(for: candidate) == nil
                }
                let accessibleMatches = nestedSymbols.filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    // This lookup walks only enclosing-class supertypes, so a
                    // protected classifier found here is accessible through
                    // inheritance. The constructor's own visibility is still
                    // checked by the regular candidate path below.
                    if symbol.visibility == .protected { return true }
                    return ctx.visibilityChecker.isAccessible(
                        symbol,
                        fromFile: ctx.currentFileID,
                        enclosingClass: ctx.enclosingClassSymbol
                    )
                }
                matches.append(contentsOf: accessibleMatches)
                if accessibleMatches.isEmpty {
                    nextOwners.append(contentsOf: sema.symbols.directSupertypes(for: ownerID))
                }
            }
            if !matches.isEmpty {
                return matches
            }
            pendingOwners = nextOwners
        }
        return []
    }

    func isInheritedNestedInterface(_ candidate: SymbolID, in ctx: TypeInferenceContext) -> Bool {
        let symbols = ctx.sema.symbols
        guard ctx.cachedSymbol(candidate)?.kind == .interface,
              let owner = symbols.parentSymbol(for: candidate),
              let enclosingClass = ctx.enclosingClassSymbol
        else { return false }

        // This only classifies where the interface is declared; visibility is
        // checked separately for the callable selected from an outer scope.
        var pendingOwners = symbols.directSupertypes(for: enclosingClass)
        var visited: Set<SymbolID> = [enclosingClass]
        while let current = pendingOwners.popLast() {
            guard visited.insert(current).inserted else { continue }
            if current == owner { return true }
            pendingOwners.append(contentsOf: symbols.directSupertypes(for: current))
        }
        return false
    }
}
