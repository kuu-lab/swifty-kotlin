/// Method binders are alpha-equivalent, but their upper bounds are part of
/// overload/override identity. Class binders must be specialized first.
func methodTypeParameterBounds(_ signature: FunctionSignature, types: TypeSystem) -> [[TypeID]] {
    signature.typeParameterSymbols.indices.dropFirst(signature.classTypeParameterCount).map { index in
        let declared = index < signature.typeParameterUpperBoundsList.count
            ? signature.typeParameterUpperBoundsList[index] : []
        let stored = types.symbolTable?.typeParameterUpperBounds(for: signature.typeParameterSymbols[index]) ?? []
        let bounds = declared + stored.filter { !declared.contains($0) }
        return bounds.isEmpty ? [types.nullableAnyType] : bounds
    }
}

func alphaAlignedMethodType(
    _ type: TypeID,
    sourceParameters: [SymbolID],
    targetParameters: [SymbolID],
    types: TypeSystem
) -> TypeID {
    guard !sourceParameters.isEmpty else { return type }
    let variables = types.makeTypeVarBySymbol(sourceParameters)
    var substitution: [TypeVarID: TypeID] = [:]
    for (source, target) in zip(sourceParameters, targetParameters) {
        guard let variable = variables[source] else { continue }
        substitution[variable] = types.make(.typeParam(TypeParamType(symbol: target, nullability: .nonNull)))
    }
    return types.substituteTypeParameters(in: type, substitution: substitution, typeVarBySymbol: variables)
}

func specializeMethodOwnerType(
    _ type: TypeID,
    owner: SymbolID?,
    instanceOwner: SymbolID,
    types: TypeSystem
) -> TypeID {
    guard let owner, !types.nominalTypeParameterSymbols(for: owner).isEmpty else { return type }
    let instanceArgs = types.nominalTypeParameterSymbols(for: instanceOwner).map {
        TypeArg.invariant(types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
    }
    guard let ownerArgs = types.liftedNominalSupertypeArgs(from: instanceOwner, childArgs: instanceArgs, to: owner)
    else { return type }
    return types.substituteNominalTypeParameters(in: type, owner: owner, ownerArgs: ownerArgs)
}

func methodUpperBoundsMatch(
    source: FunctionSignature,
    target: FunctionSignature,
    sourceOwner: SymbolID?,
    targetOwner: SymbolID,
    instanceOwner: SymbolID? = nil,
    types: TypeSystem
) -> Bool {
    let sourceParameters = Array(source.typeParameterSymbols.dropFirst(source.classTypeParameterCount))
    let targetParameters = Array(target.typeParameterSymbols.dropFirst(target.classTypeParameterCount))
    guard sourceParameters.count == targetParameters.count else { return false }
    guard !sourceParameters.isEmpty else { return true }
    let instanceOwner = instanceOwner ?? targetOwner
    let sourceBounds = methodTypeParameterBounds(source, types: types).map { bounds in
        bounds.map { bound in
            let specialized = specializeMethodOwnerType(bound, owner: sourceOwner, instanceOwner: instanceOwner, types: types)
            return alphaAlignedMethodType(specialized, sourceParameters: sourceParameters,
                                          targetParameters: targetParameters, types: types)
        }
    }
    let targetBounds = methodTypeParameterBounds(target, types: types).map { bounds in
        bounds.map { specializeMethodOwnerType($0, owner: targetOwner, instanceOwner: instanceOwner, types: types) }
    }
    return methodUpperBoundSetsMatch(sourceBounds, targetBounds, types: types)
}

/// Compare each binder's bound set without depending on declaration order,
/// duplicate spellings, or redundant use-site variance.
func methodUpperBoundSetsMatch(_ source: [[TypeID]], _ target: [[TypeID]], types: TypeSystem) -> Bool {
    guard source.count == target.count else { return false }
    return zip(source, target).allSatisfy { left, right in
        func equivalent(_ lhs: TypeID, _ rhs: TypeID) -> Bool {
            methodIdentityTypesMatch(lhs, rhs, types: types, allowTypeParameterWildcards: false)
        }
        return left.allSatisfy { bound in right.contains { equivalent(bound, $0) } }
            && right.allSatisfy { bound in left.contains { equivalent(bound, $0) } }
    }
}

func alignedMethodParameterTypes(
    source: FunctionSignature,
    target: FunctionSignature,
    sourceOwner: SymbolID?,
    instanceOwner: SymbolID,
    types: TypeSystem
) -> [TypeID] {
    let sourceParameters = Array(source.typeParameterSymbols.dropFirst(source.classTypeParameterCount))
    let targetParameters = Array(target.typeParameterSymbols.dropFirst(target.classTypeParameterCount))
    return source.parameterTypes.map {
        let specialized = specializeMethodOwnerType($0, owner: sourceOwner, instanceOwner: instanceOwner, types: types)
        return alphaAlignedMethodType(specialized, sourceParameters: sourceParameters,
                                      targetParameters: targetParameters, types: types)
    }
}

private func nominalSymbolForMethodIdentity(_ symbol: SymbolID, types: TypeSystem) -> SymbolID {
    guard let symbolTable = types.symbolTable else { return symbol }
    return types.actualTypeAliasTargetNominalSymbol(for: symbol, symbols: symbolTable) ?? symbol
}

func methodIdentityParameterTypesMatch(
    candidateParameterTypes: [TypeID],
    interfaceParameterTypes: [TypeID],
    types: TypeSystem,
    allowTypeParameterWildcards: Bool = false
) -> Bool {
    guard candidateParameterTypes.count == interfaceParameterTypes.count else { return false }
    return zip(candidateParameterTypes, interfaceParameterTypes).allSatisfy {
        methodIdentityTypesMatch($0, $1, types: types, allowTypeParameterWildcards: allowTypeParameterWildcards)
    }
}

private func methodIdentityNullabilityMatches(_ lhs: Nullability, _ rhs: Nullability) -> Bool {
    lhs == rhs || lhs == .platformType || rhs == .platformType
}

private func methodIdentityTypesMatch(
    _ candidate: TypeID, _ interface: TypeID, types: TypeSystem, allowTypeParameterWildcards: Bool
) -> Bool {
    if candidate == interface { return true }
    if allowTypeParameterWildcards {
        // Only the interface side is a wildcard. A rigid candidate type
        // parameter (a class binder, or an enclosing function's type
        // parameter captured by an object literal) can only override a
        // signature that specializes to that same variable — never a
        // concrete type. JVM agrees: `foo(t: T)` erases to `foo(Object)`,
        // which does not override e.g. `foo(Int)` from another interface
        // (KUU-3793: `object : A<T>, B` must not steal `B.foo(Int)`'s slot).
        if case .typeParam = types.kind(of: interface) { return true }
    }
    switch (types.kind(of: candidate), types.kind(of: interface)) {
    case let (.primitive(lhsPrim, lhsNull), .primitive(rhsPrim, rhsNull)):
        return lhsPrim == rhsPrim && methodIdentityNullabilityMatches(lhsNull, rhsNull)
    case let (.any(lhsNull), .any(rhsNull)),
         let (.nothing(lhsNull), .nothing(rhsNull)),
         let (.stringStruct(lhsNull), .stringStruct(rhsNull)):
        return methodIdentityNullabilityMatches(lhsNull, rhsNull)
    case (.unit, .platformUnit), (.platformUnit, .unit),
         (.nullableUnit, .platformUnit), (.platformUnit, .nullableUnit):
        return true
    case let (.typeParam(lhs), .typeParam(rhs)):
        return lhs.symbol == rhs.symbol
            && lhs.capture == rhs.capture
            && methodIdentityNullabilityMatches(lhs.nullability, rhs.nullability)
    case let (.functionType(lhs), .functionType(rhs)):
        guard lhs.isSuspend == rhs.isSuspend,
              methodIdentityNullabilityMatches(lhs.nullability, rhs.nullability),
              (lhs.receiver == nil) == (rhs.receiver == nil)
        else { return false }
        return methodIdentityParameterTypesMatch(
            candidateParameterTypes: lhs.contextReceivers,
            interfaceParameterTypes: rhs.contextReceivers, types: types, allowTypeParameterWildcards: allowTypeParameterWildcards
        ) && methodIdentityParameterTypesMatch(
            candidateParameterTypes: lhs.receiver.map { [$0] } ?? [],
            interfaceParameterTypes: rhs.receiver.map { [$0] } ?? [], types: types, allowTypeParameterWildcards: allowTypeParameterWildcards
        ) && methodIdentityParameterTypesMatch(
            candidateParameterTypes: lhs.params, interfaceParameterTypes: rhs.params, types: types, allowTypeParameterWildcards: allowTypeParameterWildcards
        ) && methodIdentityTypesMatch(lhs.returnType, rhs.returnType, types: types, allowTypeParameterWildcards: allowTypeParameterWildcards)
            && methodIdentityParameterTypesMatch(
                candidateParameterTypes: lhs.throws, interfaceParameterTypes: rhs.throws, types: types, allowTypeParameterWildcards: allowTypeParameterWildcards
            )
    case let (.classType(lhs), .classType(rhs)):
        // A supertype written through a typealias (`Sub : Base<Node>`) keeps
        // the alias symbol in lifted supertype args while the member
        // signature resolves the same alias to its target — normalize both
        // sides so the override check compares the real nominals.
        guard nominalSymbolForMethodIdentity(lhs.classSymbol, types: types)
                == nominalSymbolForMethodIdentity(rhs.classSymbol, types: types),
              methodIdentityNullabilityMatches(lhs.nullability, rhs.nullability),
              lhs.args.count == rhs.args.count
        else { return false }
        let variances = types.normalizedNominalVariances(
            for: lhs.classSymbol,
            arity: lhs.args.count
        )
        return lhs.args.indices.allSatisfy { index in
            let candidateArg = types.composedProjection(
                declarationVariance: variances[index], useSite: lhs.args[index]
            )
            let interfaceArg = types.composedProjection(
                declarationVariance: variances[index], useSite: rhs.args[index]
            )
            switch (candidateArg, interfaceArg) {
            case let (.invariant(candidate), .invariant(interface)),
                 let (.out(candidate), .out(interface)),
                 let (.in(candidate), .in(interface)):
                return methodIdentityTypesMatch(candidate, interface, types: types, allowTypeParameterWildcards: allowTypeParameterWildcards)
            case (.star, .star):
                return true
            default:
                return false
            }
        }
    case let (.kClassType(lhs), .kClassType(rhs)):
        return methodIdentityNullabilityMatches(lhs.nullability, rhs.nullability)
            && methodIdentityTypesMatch(lhs.argument, rhs.argument, types: types, allowTypeParameterWildcards: allowTypeParameterWildcards)
    default:
        return false
    }
}
