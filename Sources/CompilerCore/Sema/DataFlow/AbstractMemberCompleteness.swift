/// Member requirements key off the member's *override family*: a member
/// extension and a regular member that share a name are unrelated for
/// override purposes — `fun Any?.toString()` can neither implement nor be
/// implemented by `fun toString()` (KUU-3656). Grouping both under one name
/// bucket let `Any.toString()` "cover" an interface's abstract
/// `Any?.toString()`, so a class that never implemented the member extension
/// was wrongly accepted. Properties and functions are likewise separate
/// override namespaces — `override fun p()` cannot implement `abstract val p`
/// (KUU-4106).
struct MemberRequirementKey: Hashable {
    let name: InternedString
    let isMemberExtension: Bool
    let kind: SymbolKind
}

func collectInheritedAbstractMembers(
    for classSymbol: SymbolID,
    symbols: SymbolTable
) -> [SymbolID] {
    var abstractMembersByKey: [MemberRequirementKey: [SymbolID]] = [:]
    var concreteOwnersByKey: [MemberRequirementKey: [SymbolID]] = [:]
    var visited: Set<SymbolID> = [classSymbol]
    var queue = symbols.directSupertypes(for: classSymbol)

    while !queue.isEmpty {
        let current = queue.removeFirst()
        guard visited.insert(current).inserted else { continue }
        guard symbols.symbol(current) != nil else { continue }

        // `declaredChildren(of:)` is owner-exact: a same-fqName shadowed
        // nominal (a source declaration over an imported library type) does
        // not leak its member table into `current`'s requirements (KUU-3911).
        let children = symbols.declaredChildren(of: current)
        for childID in children {
            guard let childSym = symbols.symbol(childID) else { continue }
            guard childSym.kind == .function || childSym.kind == .property else { continue }
            let requirementKey = MemberRequirementKey(
                name: childSym.name,
                isMemberExtension: childSym.flags.contains(.memberExtension),
                kind: childSym.kind
            )
            if childSym.flags.contains(.abstractType) {
                abstractMembersByKey[requirementKey, default: []].append(childID)
            } else if let owner = symbols.parentSymbol(for: childID) {
                concreteOwnersByKey[requirementKey, default: []].append(owner)
            }
        }

        queue.append(contentsOf: symbols.directSupertypes(for: current))
    }

    var result: [SymbolID] = []
    for (requirementKey, abstractMembers) in abstractMembersByKey {
        let concreteOwners = concreteOwnersByKey[requirementKey] ?? []
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

private struct DelegatedProvidedMember {
    let name: InternedString
    let kind: SymbolKind
    let parameterTypes: [TypeID]
    let resultType: TypeID
    let extensionReceiverType: TypeID?
    let isSuspend: Bool
    let isMutable: Bool
}

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
                  symbols.symbol(ownerInterface) != nil
            else { continue }
            for supertype in symbols.directSupertypes(for: ownerInterface)
            where symbols.symbol(supertype)?.kind == .interface {
                ownerQueue.append(supertype)
            }

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

            for memberID in symbols.declaredChildren(of: ownerInterface) {
                guard let member = symbols.symbol(memberID),
                      symbols.parentSymbolIfKnown(for: memberID) == ownerInterface,
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
        return provided.resultType == view.resultType
    }
    return types.isSubtype(provided.resultType, view.resultType)
}

func unimplementedAbstractMembers(
    for classSymbol: SymbolID,
    overriddenMembers: Set<MemberRequirementKey>,
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
        if overriddenMembers.contains(MemberRequirementKey(
            name: abstractSym.name,
            isMemberExtension: abstractSym.flags.contains(.memberExtension),
            kind: abstractSym.kind
        )) {
            return false
        }
        // A concrete member declared on the type itself implements the
        // requirement even without `override`: kotlinc counts
        // `class C : I { fun g() }` over `fun g(): Int` as implemented and
        // reports only 'hides member of supertype' for the missing modifier
        // (KUU-4170). The hides-member diagnostic is emitted by the OFO
        // phase; here we only decide abstract completeness.
        if declaredMemberSatisfiesAbstractRequirement(
            abstractMember,
            on: classSymbol,
            symbols: symbols,
            types: types
        ) {
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

private func declaredMemberSatisfiesAbstractRequirement(
    _ abstractMember: SymbolID,
    on classSymbol: SymbolID,
    symbols: SymbolTable,
    types: TypeSystem
) -> Bool {
    guard let abstract = symbols.symbol(abstractMember),
          abstract.kind == .function || abstract.kind == .property
    else { return false }
    let abstractIsMemberExtension = symbols.memberExtensionOwnerSymbol(for: abstractMember) != nil
    for childID in symbols.declaredChildren(of: classSymbol) {
        guard let child = symbols.symbol(childID),
              child.name == abstract.name,
              child.kind == abstract.kind,
              !child.flags.contains(.abstractType),
              !child.flags.contains(.extensionMemberAlias),
              (symbols.memberExtensionOwnerSymbol(for: childID) != nil) == abstractIsMemberExtension
        else { continue }
        if child.kind == .function {
            if DataFlowSemaPhase().overrideFunctionSignatureMatches(
                childMember: childID,
                parentMember: abstractMember,
                childOwner: classSymbol,
                requireCovariantReturn: false,
                symbols: symbols,
                types: types
            ) {
                return true
            }
            continue
        }
        guard let abstractView = abstractMemberViewFromClass(
            abstractMember,
            for: classSymbol,
            symbols: symbols,
            types: types
        ) else { continue }
        let childReceiverTypes = abstractIsMemberExtension
            ? (symbols.extensionPropertyReceiverType(for: childID).map { [$0] } ?? [])
            : []
        let abstractReceiverTypes = abstractView.extensionReceiverType.map { [$0] } ?? []
        guard methodIdentityParameterTypesMatch(
            candidateParameterTypes: childReceiverTypes,
            interfaceParameterTypes: abstractReceiverTypes,
            types: types
        ) else { continue }
        return true
    }
    return false
}
