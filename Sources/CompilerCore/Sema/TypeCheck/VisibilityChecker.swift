
struct VisibilityChecker {
    let symbols: SymbolTable

    func isAccessible(
        _ symbol: SemanticSymbol,
        fromFile accessFileID: FileID,
        enclosingClass: SymbolID?
    ) -> Bool {
        switch symbol.visibility {
        case .public, .internal:
            return true
        case .private:
            if isLocalOrParameter(symbol.kind) {
                return true
            }
            if let parent = symbols.parentSymbol(for: symbol.id) {
                // Allow access from companion object to the containing class's private members
                if let enclosingClass = enclosingClass,
                   let companionOfOwner = symbols.companionObjectSymbol(for: parent),
                   enclosingClass == companionOfOwner {
                    return true
                }
                // Allow access from class to its companion's private members
                if let enclosingClass = enclosingClass,
                   let companionOfEnclosing = symbols.companionObjectSymbol(for: enclosingClass),
                   parent == companionOfEnclosing {
                    return true
                }
                if shareEnclosingClass(enclosingClass, parent) {
                    return true
                }
                // This constructor's `.private` was inherited from its owner
                // (no explicit modifier on the constructor itself), so its real
                // accessibility ceiling is the owner's own visibility rather than
                // a class-hierarchy relationship — an unrelated top-level
                // declaration in the same file as a `private class` shares no
                // class hierarchy with it, but should still be able to construct
                // it. Recurse into the owner's own check, which correctly falls
                // back to file scope once its parent chain is exhausted.
                if symbol.flags.contains(.constructorVisibilityInherited),
                   let ownerSymbol = symbols.symbol(parent) {
                    return isAccessible(ownerSymbol, fromFile: accessFileID, enclosingClass: enclosingClass)
                }
                return false
            }
            guard let declSite = symbol.declSite else {
                return true
            }
            return declSite.start.file == accessFileID
        case .protected:
            guard let ownerClass = symbols.parentSymbol(for: symbol.id) else {
                return false
            }
            guard let enclosingClass else {
                return false
            }
            if enclosingClass == ownerClass {
                return true
            }
            return isSubclass(enclosingClass, of: ownerClass)
        }
    }

    private func isLocalOrParameter(_ kind: SymbolKind) -> Bool {
        kind == .local || kind == .valueParameter || kind == .label || kind == .typeParameter
    }

    private func isSubclass(_ candidate: SymbolID, of ancestor: SymbolID) -> Bool {
        var visited: Set<Int32> = []
        var queue = symbols.directSupertypes(for: candidate)
        var index = 0
        while index < queue.count {
            let current = queue[index]
            index += 1
            if current == ancestor { return true }
            if visited.contains(current.rawValue) { continue }
            visited.insert(current.rawValue)
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }
        return false
    }

    private func shareEnclosingClass(_ a: SymbolID?, _ b: SymbolID) -> Bool {
        guard let a else { return false }
        var ancestorsA: Set<SymbolID> = []
        var currentA: SymbolID? = a
        while let ca = currentA, !ancestorsA.contains(ca) {
            ancestorsA.insert(ca)
            currentA = symbols.parentSymbol(for: ca)
        }
        var currentB: SymbolID? = b
        var visitedB: Set<SymbolID> = []
        while let cb = currentB, !visitedB.contains(cb) {
            if ancestorsA.contains(cb) { return true }
            visitedB.insert(cb)
            currentB = symbols.parentSymbol(for: cb)
        }
        return false
    }
}
