extension DataFlowSemaPhase {
    func registerSyntheticNativeBitSetStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let bitSetSymbol = ensureClassSymbol(
            named: "BitSet",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: bitSetSymbol)
        }

        let bitSetType = types.make(.classType(ClassType(
            classSymbol: bitSetSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(bitSetType, for: bitSetSymbol)

        var bitSetAnnotations = symbols.annotations(for: bitSetSymbol)
        let obsoleteNativeApiRecord = MetadataAnnotationRecord(annotationFQName: "kotlin.native.ObsoleteNativeApi")
        if !bitSetAnnotations.contains(obsoleteNativeApiRecord) {
            bitSetAnnotations.append(obsoleteNativeApiRecord)
            symbols.setAnnotations(bitSetAnnotations, for: bitSetSymbol)
        }

        let companionName = interner.intern("Companion")
        let companionFQName = nativePkg + [interner.intern("BitSet"), companionName]
        let companionSymbol: SymbolID
        if let existing = symbols.lookup(fqName: companionFQName), symbols.symbol(existing)?.kind == .object {
            companionSymbol = existing
        } else {
            companionSymbol = symbols.define(
                kind: .object,
                name: companionName,
                fqName: companionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
        }
        symbols.setParentSymbol(bitSetSymbol, for: companionSymbol)
        let companionType = types.make(.classType(ClassType(
            classSymbol: companionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(companionType, for: companionSymbol)

        let intRangeType = syntheticClassType(
            packagePath: ["kotlin", "ranges"],
            name: "IntRange",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let initializerType = types.make(.functionType(FunctionType(
            params: [types.intType],
            returnType: types.booleanType
        )))

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: bitSetSymbol,
            ownerType: bitSetType,
            parameters: [(name: "size", type: types.intType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: bitSetSymbol,
            ownerType: bitSetType,
            parameters: [
                (name: "length", type: types.intType),
                (name: "initializer", type: initializerType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetProperty(
            named: "isEmpty",
            ownerSymbol: bitSetSymbol,
            propertyType: types.booleanType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "lastTrueIndex",
            ownerSymbol: bitSetSymbol,
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "size",
            ownerSymbol: bitSetSymbol,
            propertyType: types.intType,
            flags: [.synthetic, .mutable],
            symbols: symbols,
            interner: interner
        )

        for name in ["and", "andNot", "or", "xor"] {
            registerSyntheticNativeBitSetMemberFunction(
                named: name,
                ownerSymbol: bitSetSymbol,
                receiverType: bitSetType,
                parameters: [(name: "another", type: bitSetType)],
                returnType: types.unitType,
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticNativeBitSetMemberFunction(
            named: "intersects",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "another", type: bitSetType)],
            returnType: types.booleanType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "range", type: intRangeType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "clear",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "from", type: types.intType),
                (name: "to", type: types.intType),
            ],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "flip",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "flip",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "range", type: intRangeType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "flip",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "from", type: types.intType),
                (name: "to", type: types.intType),
            ],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "get",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetMemberFunction(
            named: "set",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "index", type: types.intType),
                (name: "value", type: types.booleanType),
            ],
            returnType: types.unitType,
            defaultValues: [false, true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "set",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "range", type: intRangeType),
                (name: "value", type: types.booleanType),
            ],
            returnType: types.unitType,
            defaultValues: [false, true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "set",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "from", type: types.intType),
                (name: "to", type: types.intType),
                (name: "value", type: types.booleanType),
            ],
            returnType: types.unitType,
            defaultValues: [false, false, true],
            symbols: symbols,
            interner: interner
        )

        for name in ["nextClearBit", "nextSetBit"] {
            registerSyntheticNativeBitSetMemberFunction(
                named: name,
                ownerSymbol: bitSetSymbol,
                receiverType: bitSetType,
                parameters: [(name: "startIndex", type: types.intType)],
                returnType: types.intType,
                defaultValues: [true],
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticNativeBitSetMemberFunction(
            named: "previousBit",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "lookFor", type: types.booleanType),
            ],
            returnType: types.intType,
            symbols: symbols,
            interner: interner
        )
        for name in ["previousClearBit", "previousSetBit"] {
            registerSyntheticNativeBitSetMemberFunction(
                named: name,
                ownerSymbol: bitSetSymbol,
                receiverType: bitSetType,
                parameters: [(name: "startIndex", type: types.intType)],
                returnType: types.intType,
                symbols: symbols,
                interner: interner
            )
        }

        registerSyntheticNativeBitSetMemberFunction(
            named: "equals",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [(name: "other", type: types.makeNullable(types.anyType))],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "hashCode",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [],
            returnType: types.intType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "toString",
            ownerSymbol: bitSetSymbol,
            receiverType: bitSetType,
            parameters: [],
            returnType: types.stringType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativeImmutableBlobStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let immutableBlobSymbol = ensureClassSymbol(
            named: "ImmutableBlob",
            in: nativePkg,
            symbols: symbols,
            interner: interner
        )
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: immutableBlobSymbol)
        }

        let immutableBlobType = types.make(.classType(ClassType(
            classSymbol: immutableBlobSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(immutableBlobType, for: immutableBlobSymbol)
        appendDeprecatedImmutableBlobAnnotations(to: immutableBlobSymbol, symbols: symbols)

        let kotlinPkg = ensurePackage(
            path: ["kotlin"],
            symbols: symbols,
            interner: interner
        )
        let byteIteratorSymbol = ensureClassSymbol(
            named: "ByteIterator",
            in: kotlinPkg,
            symbols: symbols,
            interner: interner
        )
        if let kotlinPkgSymbol = symbols.lookup(fqName: kotlinPkg) {
            symbols.setParentSymbol(kotlinPkgSymbol, for: byteIteratorSymbol)
        }
        let byteIteratorType = types.make(.classType(ClassType(
            classSymbol: byteIteratorSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(byteIteratorType, for: byteIteratorSymbol)

        let byteArrayType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let uByteArrayType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "UByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cPointerByteVarType = cPointerType(
            pointedTypeName: "ByteVar",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cPointerUByteVarType = cPointerType(
            pointedTypeName: "UByteVar",
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerSyntheticNativeBitSetProperty(
            named: "size",
            ownerSymbol: immutableBlobSymbol,
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "get",
            ownerSymbol: immutableBlobSymbol,
            receiverType: immutableBlobType,
            parameters: [(name: "index", type: types.intType)],
            returnType: types.intType,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "iterator",
            ownerSymbol: immutableBlobSymbol,
            receiverType: immutableBlobType,
            parameters: [],
            returnType: byteIteratorType,
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeTopLevelFunction(
            named: "immutableBlobOf",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [(name: "elements", type: types.intType)],
            returnType: immutableBlobType,
            defaultValues: [false],
            varargs: [true],
            annotations: deprecatedImmutableBlobFactoryAnnotations(),
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "toByteArray",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
            ],
            returnType: byteArrayType,
            defaultValues: [true, true],
            annotations: deprecatedImmutableBlobAnnotations(),
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "toUByteArray",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
            ],
            returnType: uByteArrayType,
            defaultValues: [true, true],
            annotations: deprecatedImmutableBlobAnnotations()
                + [MetadataAnnotationRecord(annotationFQName: "kotlin.ExperimentalUnsignedTypes")],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "asCPointer",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [(name: "offset", type: types.intType)],
            returnType: cPointerByteVarType,
            defaultValues: [true],
            annotations: deprecatedImmutableBlobPointerAnnotations(),
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "asUCPointer",
            packageFQName: nativePkg,
            receiverType: immutableBlobType,
            parameters: [(name: "offset", type: types.intType)],
            returnType: cPointerUByteVarType,
            defaultValues: [true],
            annotations: deprecatedImmutableBlobPointerAnnotations(),
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativeVector128Stubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let cinteropPkg = ensurePackage(
            path: ["kotlinx", "cinterop"],
            symbols: symbols,
            interner: interner
        )
        guard let cinteropVector128Symbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("Vector128")]) else {
            return
        }

        let cinteropVector128Type = types.make(.classType(ClassType(
            classSymbol: cinteropVector128Symbol,
            args: [],
            nullability: .nonNull
        )))
        let vector128Name = interner.intern("Vector128")
        let vector128AliasFQName = nativePkg + [vector128Name]
        let vector128AliasSymbol: SymbolID
        if let existing = symbols.lookup(fqName: vector128AliasFQName),
           symbols.symbol(existing)?.kind == .typeAlias
        {
            vector128AliasSymbol = existing
            symbols.insertFlags([.synthetic], for: existing)
        } else if symbols.lookup(fqName: vector128AliasFQName) == nil {
            vector128AliasSymbol = symbols.define(
                kind: .typeAlias,
                name: vector128Name,
                fqName: vector128AliasFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        } else {
            return
        }
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: vector128AliasSymbol)
        }
        symbols.setTypeAliasUnderlyingType(cinteropVector128Type, for: vector128AliasSymbol)
        appendMetadataAnnotations(
            deprecatedNativeVector128TypeAliasAnnotations(),
            to: vector128AliasSymbol,
            symbols: symbols
        )

        let vectorOfAnnotations = deprecatedNativeVectorOfAnnotations()
        for parameterType in [types.floatType, types.intType] {
            registerSyntheticNativeTopLevelFunction(
                named: "vectorOf",
                packageFQName: nativePkg,
                receiverType: nil,
                parameters: [
                    (name: "f0", type: parameterType),
                    (name: "f1", type: parameterType),
                    (name: "f2", type: parameterType),
                    (name: "f3", type: parameterType),
                ],
                returnType: cinteropVector128Type,
                annotations: vectorOfAnnotations,
                symbols: symbols,
                interner: interner
            )
        }
    }

    func registerSyntheticNativeByteArrayAccessorStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let byteArrayType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )

        let accessors: [(name: String, returnType: TypeID, externalLinkName: String, annotations: [MetadataAnnotationRecord])] = [
            ("getByteAt", types.intType, "kk_native_byteArray_getByteAt", experimentalNativeApiAnnotations()),
            ("getShortAt", types.intType, "kk_native_byteArray_getShortAt", experimentalNativeApiAnnotations()),
            ("getIntAt", types.intType, "kk_native_byteArray_getIntAt", experimentalNativeApiAnnotations()),
            ("getLongAt", types.longType, "kk_native_byteArray_getLongAt", experimentalNativeApiAnnotations()),
            ("getUByteAt", types.ubyteType, "kk_native_byteArray_getUByteAt", experimentalNativeUnsignedApiAnnotations()),
            ("getUShortAt", types.ushortType, "kk_native_byteArray_getUShortAt", experimentalNativeUnsignedApiAnnotations()),
            ("getUIntAt", types.uintType, "kk_native_byteArray_getUIntAt", experimentalNativeUnsignedApiAnnotations()),
            ("getULongAt", types.ulongType, "kk_native_byteArray_getULongAt", experimentalNativeUnsignedApiAnnotations()),
            ("getCharAt", types.charType, "kk_native_byteArray_getCharAt", experimentalNativeApiAnnotations()),
            ("getFloatAt", types.floatType, "kk_native_byteArray_getFloatAt", experimentalNativeApiAnnotations()),
            ("getDoubleAt", types.doubleType, "kk_native_byteArray_getDoubleAt", experimentalNativeApiAnnotations()),
        ]
        for accessor in accessors {
            registerSyntheticNativeTopLevelFunction(
                named: accessor.name,
                packageFQName: nativePkg,
                receiverType: byteArrayType,
                parameters: [(name: "index", type: types.intType)],
                returnType: accessor.returnType,
                annotations: accessor.annotations,
                externalLinkName: accessor.externalLinkName,
                symbols: symbols,
                interner: interner
            )
        }

        let setters: [(name: String, valueType: TypeID, externalLinkName: String, annotations: [MetadataAnnotationRecord])] = [
            ("setByteAt", types.intType, "kk_native_byteArray_setByteAt", experimentalNativeApiAnnotations()),
            ("setShortAt", types.intType, "kk_native_byteArray_setShortAt", experimentalNativeApiAnnotations()),
            ("setIntAt", types.intType, "kk_native_byteArray_setIntAt", experimentalNativeApiAnnotations()),
            ("setLongAt", types.longType, "kk_native_byteArray_setLongAt", experimentalNativeApiAnnotations()),
            ("setUByteAt", types.ubyteType, "kk_native_byteArray_setUByteAt", experimentalNativeUnsignedApiAnnotations()),
            ("setUShortAt", types.ushortType, "kk_native_byteArray_setUShortAt", experimentalNativeUnsignedApiAnnotations()),
            ("setUIntAt", types.uintType, "kk_native_byteArray_setUIntAt", experimentalNativeUnsignedApiAnnotations()),
            ("setULongAt", types.ulongType, "kk_native_byteArray_setULongAt", experimentalNativeUnsignedApiAnnotations()),
            ("setCharAt", types.charType, "kk_native_byteArray_setCharAt", experimentalNativeApiAnnotations()),
            ("setFloatAt", types.floatType, "kk_native_byteArray_setFloatAt", experimentalNativeApiAnnotations()),
            ("setDoubleAt", types.doubleType, "kk_native_byteArray_setDoubleAt", experimentalNativeApiAnnotations()),
        ]
        for setter in setters {
            registerSyntheticNativeTopLevelFunction(
                named: setter.name,
                packageFQName: nativePkg,
                receiverType: byteArrayType,
                parameters: [
                    (name: "index", type: types.intType),
                    (name: "value", type: setter.valueType),
                ],
                returnType: types.unitType,
                annotations: setter.annotations,
                externalLinkName: setter.externalLinkName,
                symbols: symbols,
                interner: interner
            )
        }
    }

    func registerSyntheticNativeIdentityHashCodeStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "identityHashCode",
            packageFQName: nativePkg,
            receiverType: types.makeNullable(types.anyType),
            parameters: [],
            returnType: types.intType,
            annotations: experimentalNativeApiAnnotations(),
            externalLinkName: "kk_native_identityHashCode",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativeStackTraceAddressStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let listLongType = syntheticListType(
            elementType: types.longType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "getStackTraceAddresses",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [],
            returnType: listLongType,
            annotations: experimentalNativeApiAnnotations(),
            externalLinkName: "kk_native_getStackTraceAddresses",
            symbols: symbols,
            interner: interner
        )
    }

    func registerSyntheticNativeUnhandledExceptionHookStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let nativePkg = ensurePackage(
            path: ["kotlin", "native"],
            symbols: symbols,
            interner: interner
        )
        let nativePkgSymbol = symbols.lookup(fqName: nativePkg)
        let throwableType = syntheticThrowableType(
            symbols: symbols,
            types: types,
            interner: interner
        )
        let hookType = types.make(.functionType(FunctionType(
            params: [throwableType],
            returnType: types.unitType
        )))
        let nullableHookType = types.makeNullable(hookType)

        let hookAliasName = interner.intern("ReportUnhandledExceptionHook")
        let hookAliasFQName = nativePkg + [hookAliasName]
        let hookAliasSymbol: SymbolID
        if let existing = symbols.lookup(fqName: hookAliasFQName),
           symbols.symbol(existing)?.kind == .typeAlias
        {
            hookAliasSymbol = existing
            symbols.insertFlags([.synthetic], for: existing)
        } else if symbols.lookup(fqName: hookAliasFQName) == nil {
            hookAliasSymbol = symbols.define(
                kind: .typeAlias,
                name: hookAliasName,
                fqName: hookAliasFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        } else {
            return
        }
        if let nativePkgSymbol {
            symbols.setParentSymbol(nativePkgSymbol, for: hookAliasSymbol)
        }
        symbols.setTypeAliasUnderlyingType(hookType, for: hookAliasSymbol)
        appendMetadataAnnotations(
            experimentalNativeApiAnnotations(),
            to: hookAliasSymbol,
            symbols: symbols
        )

        let annotations = experimentalNativeApiAnnotations()
        registerSyntheticNativeTopLevelFunction(
            named: "getUnhandledExceptionHook",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [],
            returnType: nullableHookType,
            annotations: annotations,
            externalLinkName: "kk_native_getUnhandledExceptionHook",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "setUnhandledExceptionHook",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [("hook", nullableHookType)],
            returnType: types.unitType,
            annotations: annotations,
            externalLinkName: "kk_native_setUnhandledExceptionHook",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "processUnhandledException",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [("throwable", throwableType)],
            returnType: types.unitType,
            annotations: annotations,
            externalLinkName: "kk_native_processUnhandledException",
            canThrow: true,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "terminateWithUnhandledException",
            packageFQName: nativePkg,
            receiverType: nil,
            parameters: [("throwable", throwableType)],
            returnType: types.nothingType,
            annotations: annotations,
            externalLinkName: "kk_native_terminateWithUnhandledException",
            symbols: symbols,
            interner: interner
        )
    }

    private func syntheticListType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let collectionsPkg = ensurePackage(
            path: ["kotlin", "collections"],
            symbols: symbols,
            interner: interner
        )
        let listFQName = collectionsPkg + [interner.intern("List")]
        guard let listSymbol = symbols.lookup(fqName: listFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: listSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
