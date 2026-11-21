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
        let constructorParameterTypes = ctorVis.compactMap {
            sema.symbols.functionSignature(for: $0)?.parameterTypes
        }
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
            return !candidates.contains { existingID in
                if sema.symbols.symbol(existingID)?.kind == .constructor,
                   sema.symbols.parentSymbol(for: existingID) != classID {
                    return false
                }
                // A @LowPriorityInOverloadResolution function legitimately
                // shares the constructor's signature — resolution ranks it
                // below the ctor, so it must not suppress the ctor candidate
                // (KUU-3922, kotlinx-datetime's deprecated ctor-compat funs).
                if isLowPriorityInOverloadResolution(existingID, symbols: sema.symbols) {
                    return false
                }
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
        let classSupertypes: (SymbolID) -> [SymbolID] = { owner in
            sema.symbols.directSupertypes(for: owner).filter { supertype in
                ctx.cachedSymbol(supertype)?.kind == .class
            }
        }
        let typeKinds: Set<SymbolKind> = [.class, .enumClass, .annotationClass, .object]
        var pendingOwners = classSupertypes(enclosingClass)
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
                    if symbol.visibility == .protected { return true }
                    return ctx.visibilityChecker.isAccessible(
                        symbol,
                        fromFile: ctx.currentFileID,
                        enclosingClass: ctx.enclosingClassSymbol
                    )
                }
                matches.append(contentsOf: accessibleMatches)
                if accessibleMatches.isEmpty {
                    nextOwners.append(contentsOf: classSupertypes(ownerID))
                }
            }
            if !matches.isEmpty {
                return matches
            }
            pendingOwners = nextOwners
        }
        return []
    }

    func implicitReceiverInnerClassifier(
        named name: InternedString,
        in ctx: TypeInferenceContext
    ) -> (classSymbol: SymbolID, receiverType: TypeID)? {
        let sema = ctx.sema
        for receiverType in ctx.implicitReceiverMemberLookupTypes() {
            guard let receiverNominal = driver.helpers.nominalSymbol(
                of: receiverType, types: sema.types
            ) else {
                continue
            }
            var ownerQueue: [SymbolID] = [receiverNominal]
            var visited: Set<SymbolID> = []
            while !ownerQueue.isEmpty {
                let owner = ownerQueue.removeFirst()
                guard visited.insert(owner).inserted,
                      let ownerSymbol = ctx.cachedSymbol(owner)
                else {
                    continue
                }
                let nestedFQName = ownerSymbol.fqName + [name]
                if let match = sema.symbols.lookupAll(fqName: nestedFQName).first(where: { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate),
                          symbol.kind == .class,
                          symbol.flags.contains(.innerClass),
                          sema.symbols.parentSymbol(for: candidate) == owner
                    else {
                        return false
                    }
                    return !symbol.flags.contains(.expectDeclaration)
                        || sema.symbols.actualSymbol(for: candidate) == nil
                }) {
                    return (match, receiverType)
                }
                ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
            }
        }
        return nil
    }

    func isInheritedNestedInterface(_ candidate: SymbolID, in ctx: TypeInferenceContext) -> Bool {
        let symbols = ctx.sema.symbols
        guard ctx.cachedSymbol(candidate)?.kind == .interface,
              let owner = symbols.parentSymbol(for: candidate),
              let enclosingClass = ctx.enclosingClassSymbol
        else { return false }

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
