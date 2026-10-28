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

/// A member signature a `by` delegation makes concrete on the delegating
/// class: the delegate object supplies an implementation for every member
/// declared on the delegated interface closure, with the delegate field's
/// declared type arguments substituted through (KUU-3248).
private struct DelegatedProvidedMember {
    let name: InternedString
    let kind: SymbolKind
    let parameterTypes: [TypeID]
    let resultType: TypeID
    let extensionReceiverType: TypeID?
    let isSuspend: Bool
    let isMutable: Bool
}

/// The members a `by` delegation supplies on `classSymbol` — every member of
/// each directly delegated interface plus its inherited interfaces, with type
/// arguments substituted through the delegate field's declared type. Pairs
/// carry the class that declared the delegation so the delegate field is
/// looked up on the right nominal (an ancestor class's `by` delegation still
/// provides concrete members the subclass inherits).
private func delegatedProvidedMembers(
    delegations: [(declaringClass: SymbolID, interface: SymbolID)],
    symbols: SymbolTable,
    types: TypeSystem
) -> [DelegatedProvidedMember] {
    var provided: [DelegatedProvidedMember] = []
    for (declaringClass, interface) in delegations {
        guard let fieldSymbol = symbols.classDelegationField(
            forClass: declaringClass, interface: interface
        ), let fieldType = symbols.propertyType(for: fieldSymbol),
            case let .classType(fieldClassType) = types.kind(of: types.makeNonNullable(fieldType))
        else {
            continue
        }
        let delegatedTypeArgs = fieldClassType.args

        var ownerQueue: [SymbolID] = [interface]
        var visitedOwners: Set<SymbolID> = []
        while let ownerInterface = ownerQueue.popLast() {
            guard visitedOwners.insert(ownerInterface).inserted,
                  let ownerSym = symbols.symbol(ownerInterface)
            else { continue }
            for supertype in symbols.directSupertypes(for: ownerInterface)
            where symbols.symbol(supertype)?.kind == .interface {
                ownerQueue.append(supertype)
            }

            // Map the owner interface's type parameters to the concrete
            // arguments the delegation declaration supplies.
            let ownerTypeParams = types.nominalTypeParameterSymbols(for: ownerInterface)
            let ownerArgs: [TypeArg] = if ownerInterface == interface {
                delegatedTypeArgs
            } else {
                types.liftedNominalSupertypeArgs(
                    from: interface, childArgs: delegatedTypeArgs, to: ownerInterface
                ) ?? []
            }
            let typeVarBySymbol = types.makeTypeVarBySymbol(ownerTypeParams)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, typeParamSymbol) in ownerTypeParams.enumerated() {
                guard index < ownerArgs.count,
                      let typeVar = typeVarBySymbol[typeParamSymbol]
                else { continue }
                switch ownerArgs[index] {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    substitution[typeVar] = inner
                case .star:
                    substitution[typeVar] = types.nullableAnyType
                }
            }
            func substitute(_ type: TypeID) -> TypeID {
                guard !substitution.isEmpty else { return type }
                return types.substituteTypeParameters(
                    in: type, substitution: substitution, typeVarBySymbol: typeVarBySymbol
                )
            }

            for memberID in symbols.children(ofFQName: ownerSym.fqName) {
                guard let member = symbols.symbol(memberID),
                      symbols.parentSymbol(for: memberID) == ownerInterface,
                      !member.flags.contains(.extensionMemberAlias)
                else { continue }
                let isMemberExtension = symbols.memberExtensionOwnerSymbol(for: memberID) != nil
                switch member.kind {
                case .function:
                    guard let signature = symbols.functionSignature(for: memberID) else { continue }
                    provided.append(DelegatedProvidedMember(
                        name: member.name,
                        kind: .function,
                        parameterTypes: signature.parameterTypes.map(substitute),
                        resultType: substitute(signature.returnType),
                        extensionReceiverType: isMemberExtension
                            ? signature.receiverType.map(substitute) : nil,
                        isSuspend: signature.isSuspend,
                        isMutable: false
                    ))
                case .property:
                    guard let propertyType = symbols.propertyType(for: memberID) else { continue }
                    provided.append(DelegatedProvidedMember(
                        name: member.name,
                        kind: .property,
                        parameterTypes: [],
                        resultType: substitute(propertyType),
                        extensionReceiverType: isMemberExtension
                            ? symbols.extensionPropertyReceiverType(for: memberID).map(substitute) : nil,
                        isSuspend: false,
                        isMutable: member.flags.contains(.mutable)
                    ))
                default:
                    continue
                }
            }
        }
    }
    return provided
}

/// Substitutes the abstract member's signature through the type arguments the
/// class applies to the member's owner, so both sides of a coverage check are
/// expressed in the class's view.
func abstractMemberViewFromClass(
    _ abstractMember: SymbolID,
    for classSymbol: SymbolID,
    symbols: SymbolTable,
    types: TypeSystem
) -> (parameterTypes: [TypeID], resultType: TypeID, extensionReceiverType: TypeID?, isSuspend: Bool, isMutable: Bool)? {
    guard let member = symbols.symbol(abstractMember),
          let owner = symbols.parentSymbol(for: abstractMember)
    else { return nil }

    let classTypeParams = types.nominalTypeParameterSymbols(for: classSymbol)
    let classArgs = classTypeParams.map {
        TypeArg.invariant(types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
    }
    let ownerTypeParams = types.nominalTypeParameterSymbols(for: owner)
    let ownerArgs = types.liftedNominalSupertypeArgs(from: classSymbol, childArgs: classArgs, to: owner) ?? []
    let typeVarBySymbol = types.makeTypeVarBySymbol(ownerTypeParams)
    var substitution: [TypeVarID: TypeID] = [:]
    for (index, typeParamSymbol) in ownerTypeParams.enumerated() {
        guard index < ownerArgs.count,
              let typeVar = typeVarBySymbol[typeParamSymbol]
        else { continue }
        switch ownerArgs[index] {
        case let .invariant(inner), let .out(inner), let .in(inner):
            substitution[typeVar] = inner
        case .star:
            substitution[typeVar] = types.nullableAnyType
        }
    }
    func substitute(_ type: TypeID) -> TypeID {
        guard !substitution.isEmpty else { return type }
        return types.substituteTypeParameters(
            in: type, substitution: substitution, typeVarBySymbol: typeVarBySymbol
        )
    }

    let isMemberExtension = symbols.memberExtensionOwnerSymbol(for: abstractMember) != nil
    switch member.kind {
    case .function:
        guard let signature = symbols.functionSignature(for: abstractMember) else { return nil }
        return (signature.parameterTypes.map(substitute), substitute(signature.returnType),
                isMemberExtension ? signature.receiverType.map(substitute) : nil,
                signature.isSuspend, false)
    case .property:
        guard let propertyType = symbols.propertyType(for: abstractMember) else { return nil }
        return ([], substitute(propertyType),
                isMemberExtension
                    ? symbols.extensionPropertyReceiverType(for: abstractMember).map(substitute) : nil,
                false, member.flags.contains(.mutable))
    default:
        return nil
    }
}

/// Whether a delegated-provided implementation satisfies the abstract member:
/// same name, kind and arity, identical substituted parameter types, and a
/// result type the implementation can covariantly return (`var` properties
/// require invariance). Signatures still carrying type parameters after
/// substitution are treated as covered — rejecting them needs resolution the
/// completeness check cannot reliably perform.
private func delegationProvides(
    _ provided: DelegatedProvidedMember,
    forAbstractMember view: (parameterTypes: [TypeID], resultType: TypeID, extensionReceiverType: TypeID?, isSuspend: Bool, isMutable: Bool),
    named name: InternedString,
    kind: SymbolKind,
    types: TypeSystem
) -> Bool {
    guard provided.name == name, provided.kind == kind,
          (provided.extensionReceiverType != nil) == (view.extensionReceiverType != nil),
          provided.isSuspend == view.isSuspend,
          // A `var` abstract needs a `var` implementation; a `val` abstract
          // accepts either.
          provided.isMutable || !view.isMutable
    else { return false }
    if let providedReceiver = provided.extensionReceiverType,
       let abstractReceiver = view.extensionReceiverType,
       !methodIdentityParameterTypesMatch(
           candidateParameterTypes: [providedReceiver],
           interfaceParameterTypes: [abstractReceiver],
           types: types
       )
    {
        return false
    }
    guard methodIdentityParameterTypesMatch(
        candidateParameterTypes: provided.parameterTypes,
        interfaceParameterTypes: view.parameterTypes,
        types: types
    ) else { return false }
    if view.isMutable {
        return provided.resultType == view.resultType
    }
    if types.typeContainsAnyTypeParam(provided.resultType)
        || types.typeContainsAnyTypeParam(view.resultType)
    {
        // Subtype checks cannot rank unresolved type parameters; the
        // signatures only agree when they instantiate identically.
        return provided.resultType == view.resultType
    }
    return types.isSubtype(provided.resultType, view.resultType)
}

/// The inherited abstract members `classSymbol` still owes an implementation
/// for: everything `collectInheritedAbstractMembers` finds, minus the names
/// this type provides an `override` for, minus anything owned by an interface
/// satisfied through `by` delegation (CLASS-008), including delegates declared
/// by class ancestors. A `by` delegation also supplies concrete
/// implementations for its interface's members, so a matching abstract member
/// declared on a sibling supertype is satisfied too (KUU-3248).
func unimplementedAbstractMembers(
    for classSymbol: SymbolID,
    overriddenNames: Set<InternedString>,
    delegatedInterfaces: [SymbolID],
    symbols: SymbolTable,
    types: TypeSystem,
    interner _: StringInterner
) -> [SymbolID] {
    // A `by`-delegated interface covers members inherited through its
    // super-interfaces too: `class C : MutableMap<K,V> by m` must not owe an
    // implementation for `Map.values`, which is declared on MutableMap's
    // parent interface rather than on MutableMap itself (BUG-240).
    var delegatedPairs: [(declaringClass: SymbolID, interface: SymbolID)] =
        delegatedInterfaces.map { (classSymbol, $0) }
    var delegatedQueue = delegatedInterfaces
    var classAncestorQueue = symbols.directSupertypes(for: classSymbol)
    var visitedClassAncestors: Set<SymbolID> = [classSymbol]
    while let ancestor = classAncestorQueue.popLast() {
        guard let ancestorSym = symbols.symbol(ancestor),
              ancestorSym.kind == .class || ancestorSym.kind == .object
                || ancestorSym.kind == .enumClass || ancestorSym.kind == .annotationClass,
              visitedClassAncestors.insert(ancestor).inserted
        else {
            continue
        }
        for ancestorInterface in symbols.delegatedInterfaces(forClass: ancestor) {
            delegatedQueue.append(ancestorInterface)
            delegatedPairs.append((ancestor, ancestorInterface))
        }
        classAncestorQueue.append(contentsOf: symbols.directSupertypes(for: ancestor))
    }

    var delegatedNominals: Set<SymbolID> = []
    while let interface = delegatedQueue.popLast() {
        guard delegatedNominals.insert(interface).inserted else { continue }
        for supertype in symbols.directSupertypes(for: interface)
        where symbols.symbol(supertype)?.kind == .interface {
            delegatedQueue.append(supertype)
        }
    }

    let providedMembers = delegatedProvidedMembers(
        delegations: delegatedPairs, symbols: symbols, types: types
    )

    return collectInheritedAbstractMembers(for: classSymbol, symbols: symbols).filter { abstractMember in
        guard let abstractSym = symbols.symbol(abstractMember) else {
            return false
        }
        if let owner = symbols.parentSymbol(for: abstractMember),
           delegatedNominals.contains(owner)
        {
            return false
        }
        if overriddenNames.contains(abstractSym.name) {
            return false
        }
        guard !providedMembers.isEmpty,
              let view = abstractMemberViewFromClass(
                  abstractMember, for: classSymbol, symbols: symbols, types: types
              )
        else {
            return true
        }
        return !providedMembers.contains {
            delegationProvides(
                $0, forAbstractMember: view,
                named: abstractSym.name, kind: abstractSym.kind, types: types
            )
        }
    }
}
