extension CallTypeChecker {
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
