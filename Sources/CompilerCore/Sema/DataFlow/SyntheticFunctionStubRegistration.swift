@discardableResult
func registerSyntheticFunctionStub(
    named name: String,
    ownerFQName: [InternedString],
    parentSymbol: SymbolID?,
    receiverType: TypeID? = nil,
    parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
    returnType: TypeID,
    externalLinkName: String,
    annotations: [MetadataAnnotationRecord] = [],
    flags: SymbolFlags = [.synthetic],
    canThrow: Bool = false,
    typeParameterSymbols: [SymbolID] = [],
    typeParameterUpperBoundsList: [[TypeID]] = [],
    classTypeParameterCount: Int = 0,
    matchReturnType: Bool = false,
    updateExistingSignature: Bool = false,
    requireSyntheticOrNoDeclSiteForExisting: Bool = false,
    existingFlagsToInsert: SymbolFlags = [],
    bundledIndex: BundledDeclarationIndex = .empty,
    skipStats: SyntheticStubSkipStatsCollector? = nil,
    types: TypeSystem? = nil,
    symbols: SymbolTable,
    interner: StringInterner
) -> SymbolID {
    let functionName = interner.intern(name)
    let functionFQName = ownerFQName + [functionName]
    let parameterTypes = parameters.map(\.type)
    if let contextTypes = BundledSyntheticStubRegistration.types,
       BundledSyntheticStubRegistration.shouldSkipRegistration(
           declaredOwnerFQName: ownerFQName,
           receiverType: receiverType,
           name: functionName,
           arity: parameterTypes.count,
           symbols: symbols,
           types: contextTypes,
           interner: interner
       )
    {
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
                && (!matchReturnType || existingSignature.returnType == returnType)
        }) {
            return existing
        }
        return .invalid
    }

    let skipOwnerFQName: [InternedString] = if let receiverType,
                                                 let types,
                                                 let receiverOwner = bundledNominalOwnerFQName(
                                                     of: receiverType,
                                                     symbols: symbols,
                                                     types: types
                                                 )
    {
        receiverOwner
    } else {
        ownerFQName
    }

    if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
        guard let existingSignature = symbols.functionSignature(for: symbolID) else {
            return false
        }
        return existingSignature.receiverType == receiverType
            && existingSignature.parameterTypes == parameterTypes
            && (!matchReturnType || existingSignature.returnType == returnType)
    }) {
        if requireSyntheticOrNoDeclSiteForExisting,
           let existingInfo = symbols.symbol(existing),
           !existingInfo.flags.contains(.synthetic),
           existingInfo.declSite != nil
        {
            return existing
        }
        symbols.setExternalLinkName(externalLinkName, for: existing)
        if !existingFlagsToInsert.isEmpty {
            symbols.insertFlags(existingFlagsToInsert, for: existing)
        }
        if !annotations.isEmpty {
            symbols.setAnnotations(annotations, for: existing)
        }
        if updateExistingSignature,
           let existingSignature = symbols.functionSignature(for: existing)
        {
            let updatedSignature = FunctionSignature(
                receiverType: existingSignature.receiverType,
                parameterTypes: existingSignature.parameterTypes,
                returnType: returnType,
                isSuspend: existingSignature.isSuspend,
                canThrow: canThrow,
                valueParameterSymbols: existingSignature.valueParameterSymbols,
                valueParameterHasDefaultValues: parameters.map(\.hasDefault),
                valueParameterIsVararg: parameters.map(\.isVararg),
                typeParameterSymbols: typeParameterSymbols.isEmpty
                    ? existingSignature.typeParameterSymbols
                    : typeParameterSymbols,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList.isEmpty
                    ? existingSignature.typeParameterUpperBoundsList
                    : typeParameterUpperBoundsList,
                classTypeParameterCount: classTypeParameterCount == 0
                    ? existingSignature.classTypeParameterCount
                    : classTypeParameterCount
            )
            if updatedSignature != existingSignature {
                symbols.setFunctionSignature(updatedSignature, for: existing)
            }
        }
        return existing
    }

    if shouldSkipSyntheticStub(
        bundledIndex: bundledIndex,
        ownerFQName: skipOwnerFQName,
        name: functionName,
        arity: parameterTypes.count
    ) {
        skipStats?.recordSkip(
            ownerFQName: skipOwnerFQName,
            name: functionName,
            arity: parameterTypes.count,
            interner: interner
        )
        return .invalid
    }

    let functionSymbol = symbols.define(
        kind: .function,
        name: functionName,
        fqName: functionFQName,
        declSite: nil,
        visibility: .public,
        flags: flags
    )
    if let parentSymbol, parentSymbol != .invalid {
        symbols.setParentSymbol(parentSymbol, for: functionSymbol)
    }
    symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
    if !annotations.isEmpty {
        symbols.setAnnotations(annotations, for: functionSymbol)
    }

    var valueParameterSymbols: [SymbolID] = []
    valueParameterSymbols.reserveCapacity(parameters.count)
    for parameter in parameters {
        let parameterName = interner.intern(parameter.name)
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: functionFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
        valueParameterSymbols.append(parameterSymbol)
    }

    symbols.setFunctionSignature(
        FunctionSignature(
            receiverType: receiverType,
            parameterTypes: parameterTypes,
            returnType: returnType,
            canThrow: canThrow,
            valueParameterSymbols: valueParameterSymbols,
            valueParameterHasDefaultValues: parameters.map(\.hasDefault),
            valueParameterIsVararg: parameters.map(\.isVararg),
            typeParameterSymbols: typeParameterSymbols,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList,
            classTypeParameterCount: classTypeParameterCount
        ),
        for: functionSymbol
    )
    return functionSymbol
}

@discardableResult
func registerSyntheticMemberFunctionStub(
    name: InternedString,
    memberFQName: [InternedString],
    ownerSymbol: SymbolID,
    ownerFQName: [InternedString],
    receiverType: TypeID,
    parameterTypes: [TypeID],
    parameterNames: [String],
    returnType: TypeID,
    externalLinkName: String,
    flags: SymbolFlags = [.synthetic],
    canThrow: Bool = false,
    typeParameterSymbols: [SymbolID] = [],
    typeParameterUpperBoundsList: [[TypeID]] = [],
    classTypeParameterCount: Int = 0,
    bundledIndex: BundledDeclarationIndex = .empty,
    skipStats: SyntheticStubSkipStatsCollector? = nil,
    symbols: SymbolTable,
    interner: StringInterner
) -> SymbolID? {
    let alreadyRegistered = symbols.lookupAll(fqName: memberFQName).contains { symbolID in
        guard let signature = symbols.functionSignature(for: symbolID) else { return false }
        return signature.receiverType == receiverType
            && signature.parameterTypes == parameterTypes
            && signature.returnType == returnType
    }
    if alreadyRegistered {
        return nil
    }

    if shouldSkipSyntheticStub(
        bundledIndex: bundledIndex,
        ownerFQName: ownerFQName,
        name: name,
        arity: parameterTypes.count
    ) {
        skipStats?.recordSkip(
            ownerFQName: ownerFQName,
            name: name,
            arity: parameterTypes.count,
            interner: interner
        )
        return nil
    }

    let memberSymbol = symbols.define(
        kind: .function,
        name: name,
        fqName: memberFQName,
        declSite: nil,
        visibility: .public,
        flags: flags
    )
    symbols.setParentSymbol(ownerSymbol, for: memberSymbol)
    symbols.setExternalLinkName(externalLinkName, for: memberSymbol)

    var valueParameterSymbols: [SymbolID] = []
    valueParameterSymbols.reserveCapacity(parameterNames.count)
    for parameterNameString in parameterNames {
        let parameterName = interner.intern(parameterNameString)
        let parameterSymbol = symbols.define(
            kind: .valueParameter,
            name: parameterName,
            fqName: memberFQName + [parameterName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(memberSymbol, for: parameterSymbol)
        valueParameterSymbols.append(parameterSymbol)
    }

    symbols.setFunctionSignature(
        FunctionSignature(
            receiverType: receiverType,
            parameterTypes: parameterTypes,
            returnType: returnType,
            canThrow: canThrow,
            valueParameterSymbols: valueParameterSymbols,
            valueParameterHasDefaultValues: Array(repeating: false, count: parameterNames.count),
            valueParameterIsVararg: Array(repeating: false, count: parameterNames.count),
            typeParameterSymbols: typeParameterSymbols,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList,
            classTypeParameterCount: classTypeParameterCount
        ),
        for: memberSymbol
    )
    return memberSymbol
}

func bundledNominalOwnerFQName(
    of receiverType: TypeID,
    symbols: SymbolTable,
    types: TypeSystem
) -> [InternedString]? {
    guard let receiverSymbol = bundledNominalSymbolID(of: receiverType, types: types),
          let receiverInfo = symbols.symbol(receiverSymbol)
    else {
        return nil
    }
    return receiverInfo.fqName
}

private func bundledNominalSymbolID(of type: TypeID, types: TypeSystem) -> SymbolID? {
    switch types.kind(of: type) {
    case let .classType(classType):
        return classType.classSymbol
    case let .intersection(parts):
        for part in parts {
            if let symbol = bundledNominalSymbolID(of: part, types: types) {
                return symbol
            }
        }
        return nil
    default:
        return nil
    }
}

func syntheticFunctionParameters(
    _ parameters: [(name: String, type: TypeID)]
) -> [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)] {
    parameters.map { parameter in
        (name: parameter.name, type: parameter.type, hasDefault: false, isVararg: false)
    }
}
