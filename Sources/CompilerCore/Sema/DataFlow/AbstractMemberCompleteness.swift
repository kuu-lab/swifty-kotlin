/// Shared by `Inheritance.validateAbstractOverrides` (named class/object
/// declarations, checked during header validation) and
/// `ExprTypeChecker+ObjectLiteralInference` (object literal expressions, whose
/// own members are only known once the enclosing function body is
/// type-checked — after `validateAbstractOverrides` has already run for every
/// named nominal). Both need the same "which inherited abstract members does
/// this concrete type still owe an implementation for" logic; the object
/// literal path previously had none at all, so `object : Animal() {}` over an
/// abstract member compiled where kotlinc rejects it. Same structural cause as
/// the vtable-slot gap solved by `VtableOverrideMatching.swift`.

/// Collects all abstract member symbol IDs from the entire supertype chain of a
/// class, filtering out those that have been concretely overridden by
/// intermediate classes. Ordered by symbol ID so callers emit diagnostics
/// deterministically.
func collectInheritedAbstractMembers(
    for classSymbol: SymbolID,
    symbols: SymbolTable
) -> [SymbolID] {
    var abstractMembersByName: [InternedString: SymbolID] = [:]
    var concreteOverrideNames: Set<InternedString> = []
    var visited: Set<SymbolID> = [classSymbol]
    var queue = symbols.directSupertypes(for: classSymbol)

    while !queue.isEmpty {
        let current = queue.removeFirst()
        guard visited.insert(current).inserted else { continue }
        guard let currentSym = symbols.symbol(current) else { continue }

        let children = symbols.children(ofFQName: currentSym.fqName)
        for childID in children {
            guard let childSym = symbols.symbol(childID) else { continue }
            if childSym.kind == .function || childSym.kind == .property {
                if childSym.flags.contains(.abstractType) {
                    // Only record the abstract member if we haven't seen
                    // a concrete override for this name yet.
                    if !concreteOverrideNames.contains(childSym.name) {
                        abstractMembersByName[childSym.name] = childID
                    }
                } else {
                    // This is a concrete member. Only treat it as satisfying
                    // abstract requirements from higher supertypes if no closer
                    // supertype has already (re-)abstracted this name.
                    if abstractMembersByName[childSym.name] == nil {
                        concreteOverrideNames.insert(childSym.name)
                    }
                }
            }
        }

        // Continue walking supertypes
        queue.append(contentsOf: symbols.directSupertypes(for: current))
    }

    return abstractMembersByName.values.sorted(by: { $0.rawValue < $1.rawValue })
}

/// The inherited abstract members `classSymbol` still owes an implementation
/// for: everything `collectInheritedAbstractMembers` finds, minus the names
/// this type provides an `override` for, minus anything owned by an interface
/// satisfied through `by` delegation (CLASS-008).
func unimplementedAbstractMembers(
    for classSymbol: SymbolID,
    overriddenNames: Set<InternedString>,
    delegatedInterfaces: [SymbolID],
    symbols: SymbolTable
) -> [SymbolID] {
    collectInheritedAbstractMembers(for: classSymbol, symbols: symbols).filter { abstractMember in
        guard let abstractSym = symbols.symbol(abstractMember) else {
            return false
        }
        if let owner = symbols.parentSymbol(for: abstractMember),
           delegatedInterfaces.contains(owner)
        {
            return false
        }
        return !overriddenNames.contains(abstractSym.name)
    }
}
