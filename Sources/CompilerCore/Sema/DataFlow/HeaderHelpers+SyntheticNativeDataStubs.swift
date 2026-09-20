extension DataFlowSemaPhase {
    /// Source declarations do not carry the synthetic throwing-function flag,
    /// but this bridge has an outThrown ABI channel that must remain visible to
    /// Sema and later lowering passes.
    func patchSourceBackedNativeUnhandledExceptionHookContract(
        symbols: SymbolTable,
        interner: StringInterner,
        bundledIndex: BundledDeclarationIndex
    ) {
        let nativePkg = [
            interner.intern("kotlin"),
            interner.intern("native"),
        ]
        let functionName = interner.intern("processUnhandledException")
        guard bundledIndex.contains(
            ownerFQName: nativePkg,
            name: functionName,
            arity: 1
        ),
        let functionSymbol = symbols.lookup(fqName: nativePkg + [functionName]),
        let signature = symbols.functionSignature(for: functionSymbol)
        else {
            return
        }

        symbols.insertFlags([.throwingFunction], for: functionSymbol)
        guard !signature.canThrow else { return }
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: signature.receiverType,
                parameterTypes: signature.parameterTypes,
                returnType: signature.returnType,
                isSuspend: signature.isSuspend,
                canThrow: true,
                valueParameterSymbols: signature.valueParameterSymbols,
                valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                valueParameterIsVararg: signature.valueParameterIsVararg,
                valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
                typeParameterSymbols: signature.typeParameterSymbols,
                reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
                typeParameterUpperBounds: signature.typeParameterUpperBounds,
                typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
                classTypeParameterCount: signature.classTypeParameterCount
            ),
            for: functionSymbol
        )
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
            ("getByteAt", types.byteType, "kk_native_byteArray_getByteAt", experimentalNativeApiAnnotations()),
            ("getShortAt", types.shortType, "kk_native_byteArray_getShortAt", experimentalNativeApiAnnotations()),
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
            ("setByteAt", types.byteType, "kk_native_byteArray_setByteAt", experimentalNativeApiAnnotations()),
            ("setShortAt", types.shortType, "kk_native_byteArray_setShortAt", experimentalNativeApiAnnotations()),
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
        // KSP-1191: Runtime.kt now owns this surface. Keep the synthetic
        // registration only for configurations without the bundled source.
        guard !BundledSyntheticStubRegistration.bundledIndex.contains(
            ownerFQName: nativePkg,
            name: interner.intern("getUnhandledExceptionHook"),
            arity: 0
        ) else {
            return
        }
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
