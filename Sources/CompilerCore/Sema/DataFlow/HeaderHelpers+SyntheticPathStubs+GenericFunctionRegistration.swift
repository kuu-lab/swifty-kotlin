extension DataFlowSemaPhase {
    func registerPathUseLinesFunction(
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        sequenceOfStringType: TypeID,
        charsetType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerPathUseLinesFunction(
            ownerSymbol: ownerSymbol,
            receiverType: receiverType,
            sequenceOfStringType: sequenceOfStringType,
            parameters: [("charset", charsetType)],
            externalLinkName: "kk_path_useLines",
            valueParameterHasDefaultValuesPrefix: [true],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPathUseLinesFunction(
            ownerSymbol: ownerSymbol,
            receiverType: receiverType,
            sequenceOfStringType: sequenceOfStringType,
            parameters: [],
            externalLinkName: "kk_path_useLines_default",
            valueParameterHasDefaultValuesPrefix: [],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerPathUseLinesFunction(
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        sequenceOfStringType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        valueParameterHasDefaultValuesPrefix: [Bool],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("useLines")
        // Register as a non-generic class member of Path (mirroring File.useLines).
        // Non-generic Any return lets Sema set chosenCallee directly, which makes
        // recoverMemberCallBinding step 1 return early with the correct externalLinkName.
        guard let ownerInfo = symbols.symbol(ownerSymbol) else { return }
        let functionFQName = ownerInfo.fqName + [functionName]
        let parameterTypesPrefix = parameters.map(\.type)
        let blockType = types.make(.functionType(FunctionType(
            params: [sequenceOfStringType],
            returnType: types.anyType,
            isSuspend: false,
            nullability: .nonNull
        )))

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && Array(signature.parameterTypes.dropLast()) == parameterTypesPrefix
                && signature.typeParameterSymbols.isEmpty
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        var valueParameterSymbols: [SymbolID] = []
        for parameterName in parameters.map(\.name) + ["block"] {
            let name = interner.intern(parameterName)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: name,
                fqName: functionFQName + [name, interner.intern(externalLinkName)],
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
                parameterTypes: parameterTypesPrefix + [blockType],
                returnType: types.anyType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: valueParameterHasDefaultValuesPrefix + [false],
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: []
            ),
            for: functionSymbol
        )
    }

    func registerPathUseDirectoryEntriesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        sequenceOfPathType: TypeID,
        globType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerPathUseDirectoryEntriesFunction(
            packageFQName: packageFQName,
            receiverType: receiverType,
            sequenceOfPathType: sequenceOfPathType,
            parameters: [("glob", globType)],
            externalLinkName: "kk_path_useDirectoryEntries",
            valueParameterHasDefaultValuesPrefix: [true],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerPathUseDirectoryEntriesFunction(
            packageFQName: packageFQName,
            receiverType: receiverType,
            sequenceOfPathType: sequenceOfPathType,
            parameters: [],
            externalLinkName: "kk_path_useDirectoryEntries_default",
            valueParameterHasDefaultValuesPrefix: [],
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    func registerPathUseDirectoryEntriesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        sequenceOfPathType: TypeID,
        parameters: [(name: String, type: TypeID)],
        externalLinkName: String,
        valueParameterHasDefaultValuesPrefix: [Bool],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("useDirectoryEntries")
        let functionFQName = packageFQName + [functionName]
        let parameterTypesPrefix = parameters.map(\.type)

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && Array(signature.parameterTypes.dropLast()) == parameterTypesPrefix
                && signature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName(externalLinkName, for: functionSymbol)

        let typeParamName = interner.intern("T")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName, interner.intern(externalLinkName)],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))
        let blockType = types.make(.functionType(FunctionType(
            params: [sequenceOfPathType],
            returnType: typeParamType,
            isSuspend: false,
            nullability: .nonNull
        )))

        var valueParameterSymbols: [SymbolID] = []
        for parameterName in parameters.map(\.name) + ["block"] {
            let name = interner.intern(parameterName)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: name,
                fqName: functionFQName + [name, interner.intern(externalLinkName)],
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
                parameterTypes: parameterTypesPrefix + [blockType],
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: valueParameterHasDefaultValuesPrefix + [false],
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: [typeParamSymbol]
            ),
            for: functionSymbol
        )
    }

    func registerPathReadAttributesFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        optionsType: TypeID,
        basicFileAttributesUpperBound: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("readAttributes")
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = [optionsType]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
                && existingSignature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_path_readAttributes", for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               let typeParamSymbol = existingSignature.typeParameterSymbols.first {
                let returnType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([basicFileAttributesUpperBound], for: typeParamSymbol)
                symbols.insertFlags([.reifiedTypeParameter], for: typeParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [true],
                        typeParameterSymbols: [typeParamSymbol],
                        reifiedTypeParameterIndices: [0],
                        typeParameterUpperBoundsList: [[basicFileAttributesUpperBound]]
                    ),
                    for: existing
                )
            }
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_path_readAttributes", for: functionSymbol)

        let typeParamName = interner.intern("A")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic, .reifiedTypeParameter]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([basicFileAttributesUpperBound], for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        let optionsParamName = interner.intern("options")
        let optionsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: optionsParamName,
            fqName: functionFQName + [optionsParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: optionsParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: [optionsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                reifiedTypeParameterIndices: [0],
                typeParameterUpperBoundsList: [[basicFileAttributesUpperBound]]
            ),
            for: functionSymbol
        )
    }

    func registerPathFileAttributesViewFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        optionsType: TypeID,
        fileAttributeViewUpperBound: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("fileAttributesView")
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = [optionsType]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
                && existingSignature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_path_fileAttributesView", for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               let typeParamSymbol = existingSignature.typeParameterSymbols.first {
                let returnType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: parameterTypes,
                        returnType: returnType,
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [true],
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
                    ),
                    for: existing
                )
            }
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_path_fileAttributesView", for: functionSymbol)

        let typeParamName = interner.intern("V")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        let optionsParamName = interner.intern("options")
        let optionsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: optionsParamName,
            fqName: functionFQName + [optionsParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: optionsParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: typeParamType,
                isSuspend: false,
                valueParameterSymbols: [optionsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
            ),
            for: functionSymbol
        )
    }

    func registerPathFileAttributesViewOrNullFunction(
        packageFQName: [InternedString],
        receiverType: TypeID,
        optionsType: TypeID,
        fileAttributeViewUpperBound: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("fileAttributesViewOrNull")
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = [optionsType]

        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let existingSignature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return existingSignature.receiverType == receiverType
                && existingSignature.parameterTypes == parameterTypes
                && existingSignature.typeParameterSymbols.count == 1
        }) {
            symbols.setExternalLinkName("kk_path_fileAttributesViewOrNull", for: existing)
            if let existingSignature = symbols.functionSignature(for: existing),
               let typeParamSymbol = existingSignature.typeParameterSymbols.first {
                let typeParamType = types.make(.typeParam(TypeParamType(
                    symbol: typeParamSymbol,
                    nullability: .nonNull
                )))
                symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: receiverType,
                        parameterTypes: parameterTypes,
                        returnType: types.makeNullable(typeParamType),
                        isSuspend: existingSignature.isSuspend,
                        valueParameterSymbols: existingSignature.valueParameterSymbols,
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [true],
                        typeParameterSymbols: [typeParamSymbol],
                        typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
                    ),
                    for: existing
                )
            }
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol = symbols.lookup(fqName: packageFQName) {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setExternalLinkName("kk_path_fileAttributesViewOrNull", for: functionSymbol)

        let typeParamName = interner.intern("V")
        let typeParamSymbol = symbols.define(
            kind: .typeParameter,
            name: typeParamName,
            fqName: functionFQName + [interner.intern("$synthetic"), typeParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
        symbols.setTypeParameterUpperBounds([fileAttributeViewUpperBound], for: typeParamSymbol)
        let typeParamType = types.make(.typeParam(TypeParamType(
            symbol: typeParamSymbol,
            nullability: .nonNull
        )))

        let optionsParamName = interner.intern("options")
        let optionsParamSymbol = symbols.define(
            kind: .valueParameter,
            name: optionsParamName,
            fqName: functionFQName + [optionsParamName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: optionsParamSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: types.makeNullable(typeParamType),
                isSuspend: false,
                valueParameterSymbols: [optionsParamSymbol],
                valueParameterHasDefaultValues: [false],
                valueParameterIsVararg: [true],
                typeParameterSymbols: [typeParamSymbol],
                typeParameterUpperBoundsList: [[fileAttributeViewUpperBound]]
            ),
            for: functionSymbol
        )
    }
}
