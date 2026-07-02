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
    symbols: SymbolTable,
    interner: StringInterner
) -> SymbolID {
    let functionName = interner.intern(name)
    let functionFQName = ownerFQName + [functionName]
    let parameterTypes = parameters.map(\.type)
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

func syntheticFunctionParameters(
    _ parameters: [(name: String, type: TypeID)]
) -> [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)] {
    parameters.map { parameter in
        (name: parameter.name, type: parameter.type, hasDefault: false, isVararg: false)
    }
}
