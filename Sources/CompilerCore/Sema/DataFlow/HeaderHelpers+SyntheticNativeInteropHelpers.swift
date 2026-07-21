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

    func cPointerType(
        pointedTypeName: String,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let cinteropPkg = ["kotlinx", "cinterop"].map { interner.intern($0) }
        guard let cPointerSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("CPointer")]),
              let pointedSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern(pointedTypeName)])
        else {
            return types.anyType
        }

        let pointedType = types.make(.classType(ClassType(
            classSymbol: pointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        return types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(pointedType)],
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

    func registerSyntheticCPointerVarTypeAlias(
        aliasSymbol: SymbolID,
        aliasFQName: [InternedString],
        typeParameterUpperBound: TypeID,
        cPointerSymbol: SymbolID,
        cPointerVarOfSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let parameterInternedName = interner.intern("T")
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
        symbols.setParentSymbol(aliasSymbol, for: typeParameterSymbol)
        symbols.setTypeAliasTypeParameters([typeParameterSymbol], for: aliasSymbol)
        symbols.setTypeParameterUpperBounds([typeParameterUpperBound], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let pointerType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let underlyingType = types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(pointerType)],
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

    func deprecatedImmutableBlobAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["message = \"ImmutableBlob is deprecated. Use ByteArray instead.\""]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
        ]
    }

    func deprecatedImmutableBlobFactoryAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"ImmutableBlob is deprecated. Use ByteArray instead.\"",
                    "replaceWith = ReplaceWith(\"byteArrayOf(*elements)\")",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
        ]
    }

    func deprecatedImmutableBlobPointerAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"ImmutableBlob is deprecated. Use ByteArray instead. To get a stable C pointer to a `ByteArray`, pin it first.\"",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
        ]
    }

    func deprecatedNativeVector128TypeAliasAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Use kotlinx.cinterop.Vector128 instead.\"",
                    "replaceWith = ReplaceWith(\"kotlinx.cinterop.Vector128\")",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi"),
        ]
    }

    func deprecatedCEnumAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: ["message = \"Will be removed.\""]
            ),
        ]
    }

    func deprecatedNativeVectorOfAnnotations() -> [MetadataAnnotationRecord] {
        [
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.Deprecated",
                arguments: [
                    "message = \"Use kotlinx.cinterop.vectorOf instead.\"",
                    "replaceWith = ReplaceWith(\"kotlinx.cinterop.vectorOf(f0, f1, f2, f3)\")",
                ]
            ),
            MetadataAnnotationRecord(
                annotationFQName: "kotlin.DeprecatedSinceKotlin",
                arguments: [
                    "warningSince = \"1.9\"",
                    "errorSince = \"2.1\"",
                ]
            ),
            MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi"),
        ]
    }

    func experimentalNativeApiAnnotations() -> [MetadataAnnotationRecord] {
        [MetadataAnnotationRecord(annotationFQName: "kotlin.experimental.ExperimentalNativeApi")]
    }

    func experimentalNativeUnsignedApiAnnotations() -> [MetadataAnnotationRecord] {
        experimentalNativeApiAnnotations()
            + [MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalUnsignedTypes")]
    }

    func appendDeprecatedImmutableBlobAnnotations(to symbol: SymbolID, symbols: SymbolTable) {
        var annotations = symbols.annotations(for: symbol)
        var didAppend = false
        for record in deprecatedImmutableBlobAnnotations() where !annotations.contains(record) {
            annotations.append(record)
            didAppend = true
        }
        if didAppend {
            symbols.setAnnotations(annotations, for: symbol)
        }
    }

    func registerSyntheticCPointedReadFunction(
        named name: String,
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        typeParameterUpperBound: TypeID,
        returnClassSymbol: SymbolID,
        parameters: [(name: String, type: TypeID)],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let functionName = interner.intern(name)
        let functionFQName = ownerInfo.fqName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([typeParameterUpperBound], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let returnType = types.make(.classType(ClassType(
            classSymbol: returnClassSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        registerSyntheticNativeBitSetMemberFunction(
            named: name,
            ownerSymbol: ownerSymbol,
            receiverType: ownerType,
            parameters: parameters,
            returnType: returnType,
            typeParameterSymbols: [typeParameterSymbol],
            typeParameterUpperBoundsList: [[typeParameterUpperBound]],
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativeBitSetConstructor(
        ownerSymbol: SymbolID,
        ownerType: TypeID,
        parameters: [(name: String, type: TypeID)],
        defaultValues: [Bool],
        visibility: Visibility = .public,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let initName = interner.intern("<init>")
        let constructorFQName = ownerInfo.fqName + [initName]
        let parameterTypes = parameters.map(\.type)
        let existing = symbols.lookupAll(fqName: constructorFQName).contains { symbolID in
            guard symbols.symbol(symbolID)?.kind == .constructor,
                  let signature = symbols.functionSignature(for: symbolID)
            else {
                return false
            }
            return signature.parameterTypes == parameterTypes
        }
        guard !existing else {
            return
        }

        let constructorSymbol = symbols.define(
            kind: .constructor,
            name: initName,
            fqName: constructorFQName,
            declSite: nil,
            visibility: visibility,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(ownerSymbol, for: constructorSymbol)

        let valueParameterSymbols = parameters.map { parameter in
            let parameterName = interner.intern(parameter.name)
            let parameterSymbol = symbols.define(
                kind: .valueParameter,
                name: parameterName,
                fqName: constructorFQName + [parameterName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(constructorSymbol, for: parameterSymbol)
            symbols.setPropertyType(parameter.type, for: parameterSymbol)
            return parameterSymbol
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: ownerType,
                valueParameterSymbols: valueParameterSymbols,
                valueParameterHasDefaultValues: defaultValues,
                valueParameterIsVararg: Array(repeating: false, count: valueParameterSymbols.count)
            ),
            for: constructorSymbol
        )
    }

    func registerSyntheticNativeBitSetProperty(
        named name: String,
        ownerSymbol: SymbolID,
        propertyType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard let ownerInfo = symbols.symbol(ownerSymbol) else {
            return
        }
        let propertyName = interner.intern(name)
        let propertyFQName = ownerInfo.fqName + [propertyName]
        if let existing = symbols.lookup(fqName: propertyFQName) {
            symbols.setPropertyType(propertyType, for: existing)
            symbols.insertFlags(flags, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(ownerSymbol, for: propertySymbol)
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    func registerSyntheticNativeTopLevelProperty(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        propertyType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            symbols.setPropertyType(propertyType, for: existing)
            symbols.insertFlags(flags, for: existing)
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(propertyType, for: propertySymbol)
    }

    func registerSyntheticNativeBitSetMemberFunction(
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

    func registerSyntheticCPointerPointedProperty(
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let propertyName = interner.intern("pointed")
        let propertyFQName = packageFQName + [propertyName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = propertyFQName + [typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([cPointedType], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        let getterSignature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: typeParameterType,
            typeParameterSymbols: [typeParameterSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            classTypeParameterCount: 0
        )

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.setParentSymbol(existing, for: typeParameterSymbol)
            symbols.setPropertyType(typeParameterType, for: existing)
            symbols.setExtensionPropertyReceiverType(receiverType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(getterSignature, for: getterSymbol)
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setParentSymbol(propertySymbol, for: typeParameterSymbol)
        symbols.setPropertyType(typeParameterType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)

        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(getterSignature, for: getterSymbol)
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
    }

    func registerSyntheticNativeExtensionProperty(
        named name: String,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        receiverType: TypeID,
        propertyType: TypeID,
        flags: SymbolFlags = [.synthetic],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let propertyName = interner.intern(name)
        let propertyFQName = packageFQName + [propertyName]
        let getterSignature = FunctionSignature(
            receiverType: receiverType,
            parameterTypes: [],
            returnType: propertyType
        )

        if let existing = symbols.lookupAll(fqName: propertyFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.extensionPropertyReceiverType(for: symbolID) == receiverType
        }) {
            symbols.insertFlags(flags, for: existing)
            symbols.setPropertyType(propertyType, for: existing)
            symbols.setExtensionPropertyReceiverType(receiverType, for: existing)
            if let getterSymbol = symbols.extensionPropertyGetterAccessor(for: existing) {
                symbols.setFunctionSignature(getterSignature, for: getterSymbol)
            }
            return
        }

        let propertySymbol = symbols.define(
            kind: .property,
            name: propertyName,
            fqName: propertyFQName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: propertySymbol)
        }
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExtensionPropertyReceiverType(receiverType, for: propertySymbol)

        let getterSymbol = symbols.define(
            kind: .function,
            name: interner.intern("get"),
            fqName: propertyFQName + [interner.intern("$get")],
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(propertySymbol, for: getterSymbol)
        symbols.setFunctionSignature(getterSignature, for: getterSymbol)
        symbols.setExtensionPropertyGetterAccessor(getterSymbol, for: propertySymbol)
        symbols.setAccessorOwnerProperty(propertySymbol, for: getterSymbol)
    }

    func registerSyntheticCPointerPlusFunction(
        indexType: TypeID,
        typeParameterDiscriminator: String,
        typeParameterUpperBound: TypeID,
        cPointerSymbol: SymbolID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("plus")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [interner.intern(typeParameterDiscriminator), typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.insertFlags([.synthetic], for: typeParameterSymbol)
        symbols.setTypeParameterUpperBounds([typeParameterUpperBound], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let pointerType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "plus",
            packageFQName: packageFQName,
            receiverType: pointerType,
            parameters: [(name: "index", type: indexType)],
            returnType: pointerType,
            typeParameterSymbols: [typeParameterSymbol],
            typeParameterUpperBoundsList: [[typeParameterUpperBound]],
            flags: [.synthetic, .inlineFunction, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativePlacementAllocArrayFunction(
        lengthType: TypeID,
        typeParameterDiscriminator: String,
        cVariableType: TypeID,
        cPointerSymbol: SymbolID,
        nativePlacementType: TypeID,
        packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("allocArray")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [interner.intern(typeParameterDiscriminator), typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: typeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cVariableType], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let cArrayPointerReturnType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "allocArray",
            packageFQName: packageFQName,
            receiverType: nativePlacementType,
            parameters: [(name: "length", type: lengthType)],
            returnType: cArrayPointerReturnType,
            typeParameterSymbols: [typeParameterSymbol],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
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
    func registerSyntheticCPointerGetFunction(
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("get")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [interner.intern("$cPointerGet"), typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([cPointedType], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        let existingMatch = symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == receiverType
                && sig.parameterTypes == [types.intType]
                && sig.returnType == typeParameterType
                && sig.typeParameterSymbols == [typeParameterSymbol]
        }
        if let existing = existingMatch {
            symbols.insertFlags([.synthetic, .operatorFunction], for: existing)
            symbols.setParentSymbol(existing, for: typeParameterSymbol)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)

        let indexName = interner.intern("index")
        let indexSymbol = symbols.define(
            kind: .valueParameter,
            name: indexName,
            fqName: functionFQName + [indexName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: indexSymbol)
        symbols.setPropertyType(types.intType, for: indexSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType],
                returnType: typeParameterType,
                typeParameterSymbols: [typeParameterSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }

    func registerSyntheticCPointerSetFunction(
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        packageFQName: [InternedString],
        packageSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let functionName = interner.intern("set")
        let functionFQName = packageFQName + [functionName]
        let typeParameterName = interner.intern("T")
        let typeParameterFQName = functionFQName + [interner.intern("$cPointerSet"), typeParameterName]
        let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: typeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: typeParameterName,
                fqName: typeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([cPointedType], for: typeParameterSymbol)

        let typeParameterType = types.make(.typeParam(TypeParamType(
            symbol: typeParameterSymbol,
            nullability: .nonNull
        )))
        let receiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(typeParameterType)],
            nullability: .nonNull
        )))

        let existingMatch = symbols.lookupAll(fqName: functionFQName).first { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == receiverType
                && sig.parameterTypes == [types.intType, typeParameterType]
                && sig.returnType == types.unitType
                && sig.typeParameterSymbols == [typeParameterSymbol]
        }
        if let existing = existingMatch {
            symbols.insertFlags([.synthetic, .operatorFunction], for: existing)
            symbols.setParentSymbol(existing, for: typeParameterSymbol)
            return
        }

        let functionSymbol = symbols.define(
            kind: .function,
            name: functionName,
            fqName: functionFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic, .operatorFunction]
        )
        if let packageSymbol {
            symbols.setParentSymbol(packageSymbol, for: functionSymbol)
        }
        symbols.setParentSymbol(functionSymbol, for: typeParameterSymbol)

        let indexName = interner.intern("index")
        let indexSymbol = symbols.define(
            kind: .valueParameter,
            name: indexName,
            fqName: functionFQName + [indexName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: indexSymbol)
        symbols.setPropertyType(types.intType, for: indexSymbol)

        let valueName = interner.intern("value")
        let valueSymbol = symbols.define(
            kind: .valueParameter,
            name: valueName,
            fqName: functionFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(functionSymbol, for: valueSymbol)
        symbols.setPropertyType(typeParameterType, for: valueSymbol)

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [types.intType, typeParameterType],
                returnType: types.unitType,
                typeParameterSymbols: [typeParameterSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                classTypeParameterCount: 0
            ),
            for: functionSymbol
        )
    }
}
