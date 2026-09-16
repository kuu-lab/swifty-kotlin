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
///
/// A concrete member satisfies an abstract requirement unless the abstract
/// declaration's owner is a nominal subtype of the concrete member's owner.
/// The latter is a re-abstraction: the more-specific interface intentionally
/// requires an implementation again. This keeps the result independent of
/// direct-supertype declaration order.
func collectInheritedAbstractMembers(
    for classSymbol: SymbolID,
    symbols: SymbolTable
) -> [SymbolID] {
    var abstractMembersByName: [InternedString: [SymbolID]] = [:]
    var concreteOwnersByName: [InternedString: [SymbolID]] = [:]
    var visited: Set<SymbolID> = [classSymbol]
    var queue = symbols.directSupertypes(for: classSymbol)

    while !queue.isEmpty {
        let current = queue.removeFirst()
        guard visited.insert(current).inserted else { continue }
        guard let currentSym = symbols.symbol(current) else { continue }

        let children = symbols.children(ofFQName: currentSym.fqName)
        for childID in children {
            guard let childSym = symbols.symbol(childID) else { continue }
            guard childSym.kind == .function || childSym.kind == .property else { continue }
            if childSym.flags.contains(.abstractType) {
                abstractMembersByName[childSym.name, default: []].append(childID)
            } else if let owner = symbols.parentSymbol(for: childID) {
                concreteOwnersByName[childSym.name, default: []].append(owner)
            }
        }

        // Continue walking supertypes
        queue.append(contentsOf: symbols.directSupertypes(for: current))
    }

    var result: [SymbolID] = []
    for (name, abstractMembers) in abstractMembersByName {
        let concreteOwners = concreteOwnersByName[name] ?? []
        for abstractMember in abstractMembers {
            let covered = concreteOwners.contains { concreteOwner in
                guard let abstractOwner = symbols.parentSymbol(for: abstractMember) else {
                    return true
                }
                return !isNominalSubtypeViaDirectSupertypes(
                    abstractOwner,
                    of: concreteOwner,
                    symbols: symbols
                )
            }
            if !covered {
                result.append(abstractMember)
            }
        }
    }
    return result.sorted(by: { $0.rawValue < $1.rawValue })
}

/// Nominal (type-argument-insensitive) subtype check over direct supertypes.
private func isNominalSubtypeViaDirectSupertypes(
    _ candidate: SymbolID,
    of base: SymbolID,
    symbols: SymbolTable
) -> Bool {
    if candidate == base {
        return true
    }
    var visited: Set<SymbolID> = [candidate]
    var queue = symbols.directSupertypes(for: candidate)
    while !queue.isEmpty {
        let current = queue.removeFirst()
        if current == base {
            return true
        }
        if visited.insert(current).inserted {
            queue.append(contentsOf: symbols.directSupertypes(for: current))
        }
    }
    return false
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
