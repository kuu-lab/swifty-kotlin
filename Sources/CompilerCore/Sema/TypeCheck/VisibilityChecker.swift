
struct VisibilityChecker {
    let symbols: SymbolTable
    let sourceManager: SourceManager?
    /// Files that opted into calling otherwise-invisible declarations via
    /// `@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")`, the same
    /// escape hatch kotlin-stdlib uses to reach `@PublishedApi internal` API.
    let invisibleAccessFiles: Set<Int32>

    init(symbols: SymbolTable, sourceManager: SourceManager? = nil, invisibleAccessFiles: Set<Int32> = []) {
        self.symbols = symbols
        self.sourceManager = sourceManager
        self.invisibleAccessFiles = invisibleAccessFiles
    }

    func isAccessible(
        _ symbol: SemanticSymbol,
        fromFile accessFileID: FileID,
        enclosingClass: SymbolID?
    ) -> Bool {
        // Anonymous object types are local to their declaring file. Their
        // synthetic private owner chain must not make their public members
        // inaccessible within that file, including through nested literals.
        if symbol.flags.contains(.objectLiteralType) {
            guard !symbol.flags.contains(.importedLibrary),
                  let declarationFileID = symbols.sourceFileID(for: symbol.id) ?? symbol.declSite?.start.file
            else {
                return false
            }
            return declarationFileID == accessFileID
        }
        // A nested declaration cannot expose an owner that is invisible at its
        // use site, for source declarations or imported metadata alike.
        if let parent = symbols.parentSymbol(for: symbol.id),
           let owner = symbols.symbol(parent),
           !isAccessible(owner, fromFile: accessFileID, enclosingClass: enclosingClass) {
            return false
        }
        // An implicit constructor inherits the effective visibility of its
        // owning class. This matters for a protected nested class: checking
        // the constructor as a protected member of that nested class would
        // incorrectly require the caller to subclass the nested class itself.
        if symbol.flags.contains(.constructorVisibilityInherited),
           let parent = symbols.parentSymbol(for: symbol.id),
           let ownerSymbol = symbols.symbol(parent) {
            return isAccessible(ownerSymbol, fromFile: accessFileID, enclosingClass: enclosingClass)
        }
        switch symbol.visibility {
        case .public:
            return true
        case .internal:
            if symbol.flags.contains(.importedLibrary) {
                return invisibleAccessFiles.contains(accessFileID.rawValue)
            }
            guard let sourceManager,
                  let declarationFileID = symbols.sourceFileID(for: symbol.id) ?? symbol.declSite?.start.file,
                  sourceManager.origin(of: declarationFileID)?.isBundledStdlib == true
            else {
                return true
            }
            return sourceManager.origin(of: accessFileID)?.isBundledStdlib == true
                || invisibleAccessFiles.contains(accessFileID.rawValue)
        case .private:
            if isLocalOrParameter(symbol.kind) {
                return true
            }
            if symbol.flags.contains(.importedLibrary) {
                return false
            }
            if let parent = symbols.parentSymbol(for: symbol.id) {
                if let enclosingClass = enclosingClass,
                   let companionOfOwner = symbols.companionObjectSymbol(for: parent),
                   enclosingClass == companionOfOwner {
                    return true
                }
                if let enclosingClass = enclosingClass,
                   let companionOfEnclosing = symbols.companionObjectSymbol(for: enclosingClass),
                   parent == companionOfEnclosing {
                    return true
                }
                if shareEnclosingClass(enclosingClass, parent) {
                    return true
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
            // A protected nested class passes its visibility to an implicit
            // constructor. Check access against that class's owning scope so
            // the enclosing class and its subclasses can construct it. An
            // explicitly protected constructor still uses its own class as
            // the protected owner.
            if symbol.flags.contains(.constructorVisibilityInherited),
               let ownerSymbol = symbols.symbol(ownerClass) {
                return isAccessible(ownerSymbol, fromFile: accessFileID, enclosingClass: enclosingClass)
            }
            guard let enclosingClass else {
                return false
            }
            // A protected member declared in a companion object is scoped to
            // the companion's containing class: the class itself, its
            // subclasses, and every declaration lexically nested inside it —
            // inner and nested classes included — may access it (KUU-3605).
            var protectedScopeOwner = ownerClass
            if let companionOwner = symbols.parentSymbol(for: ownerClass),
               symbols.companionObjectSymbol(for: companionOwner) == ownerClass {
                protectedScopeOwner = companionOwner
            }
            // Protected access is evaluated against every nominal enclosing
            // the use site, not only the innermost one: a nested or inner
            // class also sees protected members that an enclosing class can
            // reach (e.g. a member of an outer class's supertype), and being
            // lexically nested inside the owner counts as access from within
            // the owner.
            var visited: Set<SymbolID> = []
            var useSiteClass: SymbolID? = enclosingClass
            while let candidate = useSiteClass, visited.insert(candidate).inserted {
                if candidate == protectedScopeOwner || isSubclass(candidate, of: protectedScopeOwner) {
                    return true
                }
                useSiteClass = symbols.parentSymbol(for: candidate)
            }
            return false
        }
    }

    func isPublicAPI(_ symbol: SemanticSymbol, allowProtected: Bool = true) -> Bool {
        if symbol.flags.contains(.constructorVisibilityInherited),
           let parent = symbols.parentSymbol(for: symbol.id),
           let owner = symbols.symbol(parent) {
            return isPublicAPI(owner, allowProtected: allowProtected)
        }
        switch symbol.visibility {
        case .public:
            break
        case .protected:
            guard allowProtected else { return false }
        case .internal:
            guard symbols.annotations(for: symbol.id).contains(where: {
                KnownCompilerAnnotation.publishedApi.matches($0.annotationFQName)
            }) else { return false }
        case .private:
            return false
        }
        guard let parent = symbols.parentSymbol(for: symbol.id),
              let owner = symbols.symbol(parent)
        else { return true }
        return isPublicAPI(owner)
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
