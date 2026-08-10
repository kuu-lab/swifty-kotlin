extension DataFlowSemaPhase {
    func appendStandardAnnotationMetadata(
        to symbol: SymbolID,
        targets: [String],
        retention: String,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        let targetRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Target",
            arguments: targets
        )
        if !annotations.contains(targetRecord) {
            annotations.append(targetRecord)
        }

        let retentionRecord = MetadataAnnotationRecord(
            annotationFQName: "kotlin.annotation.Retention",
            arguments: [retention]
        )
        if !annotations.contains(retentionRecord) {
            annotations.append(retentionRecord)
        }
        symbols.setAnnotations(annotations, for: symbol)
    }

    func appendMetadataAnnotations(
        _ records: [MetadataAnnotationRecord],
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        var annotations = symbols.annotations(for: symbol)
        var didAppend = false
        for record in records where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    func syntheticClassType(
        packagePath: [String],
        name: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let packageFQName = packagePath.map { interner.intern($0) }
        let classFQName = packageFQName + [interner.intern(name)]
        guard let symbol = symbols.lookup(fqName: classFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func syntheticThrowableType(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let throwableName = interner.intern("Throwable")
        let throwableFQName = kotlinPkg + [throwableName]
        let throwableSymbol: SymbolID
        if let existing = symbols.lookup(fqName: throwableFQName) {
            throwableSymbol = existing
        } else {
            throwableSymbol = symbols.define(
                kind: .class,
                name: throwableName,
                fqName: throwableFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
                symbols.setParentSymbol(kotlinPkgSymbol, for: throwableSymbol)
            }
        }
        return types.make(.classType(ClassType(
            classSymbol: throwableSymbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func registerSyntheticCInteropTypeAlias(
        named aliasName: String,
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        underlyingType: TypeID,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let aliasSymbol = ensureSyntheticCInteropTypeAliasSymbol(
            named: aliasName,
            in: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        ) else {
            return
        }
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    func registerSyntheticCInteropSingleTypeParameterTypeAlias(
        named aliasName: String,
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        parameterName: String,
        targetSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let aliasSymbol = ensureSyntheticCInteropTypeAliasSymbol(
            named: aliasName,
            in: packageFQName,
            packageSymbol: packageSymbol,
            symbols: symbols,
            interner: interner
        ) else {
            return
        }

        let aliasFQName = packageFQName + [interner.intern(aliasName)]
        let parameterInternedName = interner.intern(parameterName)
        let typeParameterFQName = aliasFQName + [parameterInternedName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: parameterInternedName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeAliasTypeParameters([typeParameterSymbol], for: aliasSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: targetSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        symbols.setTypeAliasUnderlyingType(underlyingType, for: aliasSymbol)
    }

    func ensureSyntheticCInteropTypeAliasSymbol(
        named aliasName: String,
        in packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        let aliasInternedName = interner.intern(aliasName)
        let aliasFQName = packageFQName + [aliasInternedName]
        let aliasSymbol: SymbolID
        if let existing = symbols.lookup(fqName: aliasFQName),
           symbols.symbol(existing)?.kind == .typeAlias
        {
            aliasSymbol = existing
            symbols.insertFlags([.synthetic], for: existing)
        } else if symbols.lookup(fqName: aliasFQName) == nil {
            aliasSymbol = symbols.define(
                kind: .typeAlias,
                name: aliasInternedName,
                fqName: aliasFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        } else {
            return nil
        }

        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: aliasSymbol)
        }
        return aliasSymbol
    }

    func deprecatedCEnumAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["message = \"Will be removed.\""]
            ),
        ]
    }

    func experimentalNativeApiAnnotations() -> [MetadataAnnotationRecord] {
        [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")]
    }

    func experimentalNativeUnsignedApiAnnotations() -> [MetadataAnnotationRecord] {
        experimentalNativeApiAnnotations()
            + [MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalUnsignedTypes")]
    }

    func registerSyntheticNativeMemberFunction(
        named name: String,
        ownerSymbol: SymbolID,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        defaultValues: [Bool]? = nil,
        typeParameterSymbols: [SymbolID] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        classTypeParameterCount: Int = 0,
        flags: SymbolFlags = [.synthetic],
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let parameterTypes = parameters.map(\.type)
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.classTypeParameterCount == classTypeParameterCount
        }) {
            symbols.insertFlags(flags, for: existing)
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
            appendMetadataAnnotations(annotations, to: existing, symbols: symbols)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: functionSymbol)
        for typeParameterSymbol in typeParameterSymbols {
            symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
        }

        let valueParameterSymbols = parameters.map { parameter in
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
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues ?? Array(repeating: false, count: valueParameterSymbols.count),
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count),
                typeParameterSymbols: typeParameterSymbols,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList,
                classTypeParameterCount: classTypeParameterCount
            ),
            for: functionSymbol
        )
        if let externalLinkName {
            symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
        }
        appendMetadataAnnotations(annotations, to: functionSymbol, symbols: symbols)
    }

    func registerSyntheticNativeTopLevelFunction(
        named name: String,
        packageFQName: [InternedString],
        receiverType: TypeID?,
        parameters: [(name: String, type: TypeID)],
        returnType: TypeID,
        defaultValues: [Bool]? = nil,
        varargs: [Bool]? = nil,
        typeParameterSymbols: [SymbolID] = [],
        typeParameterUpperBoundsList: [[TypeID]] = [],
        reifiedTypeParameterIndices: Set<Int> = [],
        annotations: [MetadataAnnotationRecord] = [],
        externalLinkName: String? = nil,
        flags: SymbolFlags = [.synthetic],
        canThrow: Bool = false,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        var functionFlags = flags
        if canThrow {
            functionFlags.insert(.throwingFunction)
        }
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        let parameterTypes = parameters.map(\.type)
        let functionSymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: functionFQName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else {
                return false
            }
            return signature.receiverType == receiverType
                && signature.parameterTypes == parameterTypes
                && signature.returnType == returnType
                && signature.typeParameterSymbols == typeParameterSymbols
                && signature.typeParameterUpperBoundsList == typeParameterUpperBoundsList
                && signature.reifiedTypeParameterIndices == reifiedTypeParameterIndices
        }) {
            functionSymbol = existing
            symbols.insertFlags(functionFlags, for: existing)
            for typeParameterSymbol in typeParameterSymbols {
                symbols.setParentSymbol(existing, for: typeParameterSymbol)
            }
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: existing)
            }
        } else {
            functionSymbol = symbols.define(
                kind: .function,
                name: functionName,
                fqName: functionFQName,
                declSite: nil,
                visibility: .public,
                flags: functionFlags
            )
            if let packageSymbol = symbols.lookup(fqName: packageFQName) {
                symbols.setParentSymbol(packageSymbol, for: functionSymbol)
            }
            for typeParameterSymbol in typeParameterSymbols {
                symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)
            }

            // Use typeParameterSymbols to create a unique FQName discriminator for
            // value parameters.  Without this, overloads that differ only in receiver
            // type (e.g. CPointer<T1>.plus vs CPointer<T2>.plus) share the same
            // parameter FQName, causing define() to return the same SymbolID for
            // all of them and the last setPropertyType call to win.
            let paramFQNameDiscriminator: [InternedString] = typeParameterSymbols.isEmpty
                ? []
                : [interner.intern("$tp" + typeParameterSymbols.map { String($0.rawValue) }.joined(separator: "_"))]
            let valueParameterSymbols = parameters.map { parameter in
                let parameterName = interner.intern(parameter.name)
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: parameterName,
                    fqName: functionFQName + paramFQNameDiscriminator + [parameterName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(functionSymbol, for: parameterSymbol)
                symbols.setPropertyType(parameter.type, for: parameterSymbol)
                return parameterSymbol
            }

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: parameterTypes,
                    returnType: returnType,
                    isSuspend: false,
                    canThrow: canThrow,
                    valueParameterSymbols: valueParameterSymbols,
                    valueParameterHasDefaultValues: defaultValues ?? Array(repeating: false, count: valueParameterSymbols.count),
                    valueParameterIsVararg: varargs ?? Array(repeating: false, count: valueParameterSymbols.count),
                    typeParameterSymbols: typeParameterSymbols,
                    reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                    typeParameterUpperBoundsList: typeParameterUpperBoundsList
                ),
                for: functionSymbol
            )
            if let externalLinkName {
                symbols.setExternalLinkName(externalLinkName, for: functionSymbol)
            }
        }

        if !annotations.isEmpty {
            var existingAnnotations = symbols.annotations(for: functionSymbol)
            var didAppend = false
            for record in annotations where !existingAnnotations.contains(record) {
                existingAnnotations.append(record)
                didAppend = true
            }
            if didAppend {
                symbols.setAnnotations(existingAnnotations, for: functionSymbol)
            }
        }
    }

    func configureSingleTypeParameterNominal(
        ownerSymbol: SymbolID,
        fqName: [InternedString],
        parameterName: String,
        supertype: SymbolID?,
        supertypeIsGeneric: Bool = true,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let parameterInternedName = interner.intern(parameterName)
        let typeParameterFQName = fqName + [parameterInternedName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: parameterInternedName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }

        let parameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let ownerType = types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.invariant(parameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(ownerType, for: ownerSymbol)
        types.setNominalTypeParameterSymbols([typeParameterSymbol], for: ownerSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: ownerSymbol)

        if let supertype {
            let supertypeTypeArgs: [TypeArg] = supertypeIsGeneric ? [.invariant(parameterType)] : []
            symbols.setDirectSupertypes([supertype], for: ownerSymbol)
            types.setNominalDirectSupertypes([supertype], for: ownerSymbol)
            symbols.setSupertypeTypeArgs(supertypeTypeArgs, for: ownerSymbol, supertype: supertype)
            types.setNominalSupertypeTypeArgs(supertypeTypeArgs, for: ownerSymbol, supertype: supertype)
        }
    }

    /// Registers `operator fun <T : CPointed> CPointer<T>.get(index: Int): T`.

}
