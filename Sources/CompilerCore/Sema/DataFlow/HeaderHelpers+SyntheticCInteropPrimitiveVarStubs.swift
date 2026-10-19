extension DataFlowSemaPhase {
    func registerCInteropPrimitiveVarStubs(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        cPrimitiveVarSymbol: SymbolID,
        cPointerSymbol: SymbolID,
        nativePtrType: TypeID,
        booleanVarOfSymbol: SymbolID,
        byteVarOfSymbol: SymbolID,
        cPointerVarOfSymbol: SymbolID,
        cStructVarSymbol: SymbolID,
        cEnumVarSymbol: SymbolID,
        cVariableSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        // KUU-1375: primitive `*Var` classes subtype `CPrimitiveVar` (which is a
        // `CVariable`) so `alloc<IntVar>()` satisfies its `T : CVariable` bound.
        let primitiveVarKinds: [(name: String, valueType: TypeID, linkPrefix: String)] = [
            (name: "UByteVar", valueType: types.ubyteType, linkPrefix: "kk_cvar_ubyte"),
            (name: "ShortVar", valueType: types.shortType, linkPrefix: "kk_cvar_short"),
            (name: "UShortVar", valueType: types.ushortType, linkPrefix: "kk_cvar_ushort"),
            (name: "IntVar", valueType: types.intType, linkPrefix: "kk_cvar_int"),
            (name: "UIntVar", valueType: types.uintType, linkPrefix: "kk_cvar_uint"),
            (name: "LongVar", valueType: types.longType, linkPrefix: "kk_cvar_long"),
            (name: "ULongVar", valueType: types.ulongType, linkPrefix: "kk_cvar_ulong"),
            (name: "FloatVar", valueType: types.floatType, linkPrefix: "kk_cvar_float"),
            (name: "DoubleVar", valueType: types.doubleType, linkPrefix: "kk_cvar_double"),
        ]
        for (primitiveVar, primitiveValueType, linkPrefix) in primitiveVarKinds {
            let symbol = ensureClassSymbol(
                named: primitiveVar,
                in: cinteropPkg,
                symbols: symbols,
                interner: interner
            )
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: symbol)
            }
            let type = types.make(.classType(ClassType(
                classSymbol: symbol,
                args: [],
                nullability: .nonNull
            )))
            symbols.setPropertyType(type, for: symbol)
            symbols.setDirectSupertypes([cPrimitiveVarSymbol], for: symbol)
            types.setNominalDirectSupertypes([cPrimitiveVarSymbol], for: symbol)
            registerAtomicValueProperty(
                ownerSymbol: symbol,
                valueType: primitiveValueType,
                getterLinkName: "\(linkPrefix)_load",
                symbols: symbols,
                interner: interner
            )
            let primitivePtrType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(type)],
                nullability: .nonNull
            )))
            registerAtomicReadOnlyProperty(
                ownerSymbol: symbol,
                propertyName: "ptr",
                valueType: primitivePtrType,
                getterLinkName: "kk_cvar_ptr",
                symbols: symbols,
                interner: interner
            )
            registerAtomicReadOnlyProperty(
                ownerSymbol: symbol,
                propertyName: "rawPtr",
                valueType: nativePtrType,
                getterLinkName: "kk_cvar_raw_ptr",
                symbols: symbols,
                interner: interner
            )
        }
        // BooleanVarOf<T>/ByteVarOf<T> already subtype CPrimitiveVar; they just
        // need the `value` bridge. CPointerVarOf<T> stores a pointer word.
        registerAtomicValueProperty(
            ownerSymbol: booleanVarOfSymbol,
            valueType: types.booleanType,
            getterLinkName: "kk_cvar_bool_load",
            symbols: symbols,
            interner: interner
        )
        registerAtomicValueProperty(
            ownerSymbol: byteVarOfSymbol,
            valueType: types.byteType,
            getterLinkName: "kk_cvar_byte_load",
            symbols: symbols,
            interner: interner
        )
        if let cPointerVarOfT = types.nominalTypeParameterSymbols(for: cPointerVarOfSymbol).first {
            let cPointerVarOfTType = types.make(.typeParam(TypeParamType(
                symbol: cPointerVarOfT,
                nullability: .nonNull
            )))
            registerAtomicValueProperty(
                ownerSymbol: cPointerVarOfSymbol,
                valueType: cPointerVarOfTType,
                getterLinkName: "kk_cvar_cpointer_load",
                symbols: symbols,
                interner: interner
            )
        }
        // Class type-param substitution fills in the concrete pointee of `ptr`.
        for genericVarSymbol in [booleanVarOfSymbol, byteVarOfSymbol, cPointerVarOfSymbol] {
            guard let tSym = types.nominalTypeParameterSymbols(for: genericVarSymbol).first
            else { continue }
            let tType = types.make(.typeParam(TypeParamType(symbol: tSym, nullability: .nonNull)))
            let genericVarType = types.make(.classType(ClassType(
                classSymbol: genericVarSymbol,
                args: [.invariant(tType)],
                nullability: .nonNull
            )))
            let genericPtrType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(genericVarType)],
                nullability: .nonNull
            )))
            registerAtomicReadOnlyProperty(
                ownerSymbol: genericVarSymbol,
                propertyName: "ptr",
                valueType: genericPtrType,
                getterLinkName: "kk_cvar_ptr",
                symbols: symbols,
                interner: interner
            )
            registerAtomicReadOnlyProperty(
                ownerSymbol: genericVarSymbol,
                propertyName: "rawPtr",
                valueType: nativePtrType,
                getterLinkName: "kk_cvar_raw_ptr",
                symbols: symbols,
                interner: interner
            )
        }
        for aggregateVarSymbol in [cStructVarSymbol, cEnumVarSymbol, cVariableSymbol] {
            guard symbols.symbol(aggregateVarSymbol) != nil else { continue }
            let aggregateVarType = types.make(.classType(ClassType(
                classSymbol: aggregateVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let aggregatePtrType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(aggregateVarType)],
                nullability: .nonNull
            )))
            registerAtomicReadOnlyProperty(
                ownerSymbol: aggregateVarSymbol,
                propertyName: "ptr",
                valueType: aggregatePtrType,
                getterLinkName: "kk_cvar_ptr",
                symbols: symbols,
                interner: interner
            )
            registerAtomicReadOnlyProperty(
                ownerSymbol: aggregateVarSymbol,
                propertyName: "rawPtr",
                valueType: nativePtrType,
                getterLinkName: "kk_cvar_raw_ptr",
                symbols: symbols,
                interner: interner
            )
        }
    }

    func registerCInteropUnsignedVarStubs(
        cinteropPkg: [InternedString],
        cValuesSymbol: SymbolID,
        cPointerSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        if let uIntVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UIntVar")]) {
            let uIntVarType = types.make(.classType(ClassType(
                classSymbol: uIntVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uIntArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "UIntArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uIntArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uIntVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uIntArrayReceiverType,
                parameters: [],
                returnType: uIntArrayToCValuesReturnType,
                externalLinkName: "kk_uIntArray_toCValues",
                symbols: symbols,
                interner: interner
            )
        }

        if let uLongVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("ULongVar")]) {
            let uLongVarType = types.make(.classType(ClassType(
                classSymbol: uLongVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uLongArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "ULongArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uLongArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uLongVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uLongArrayReceiverType,
                parameters: [],
                returnType: uLongArrayToCValuesReturnType,
                externalLinkName: "kk_uLongArray_toCValues",
                symbols: symbols,
                interner: interner
            )
        }
        if let intVarSymbolForUtf32 = symbols.lookup(fqName: cinteropPkg + [interner.intern("IntVar")]) {
            let intVarTypeForUtf32 = types.make(.classType(ClassType(
                classSymbol: intVarSymbolForUtf32,
                args: [],
                nullability: .nonNull
            )))
            let toKStringFromUtf32ReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(intVarTypeForUtf32)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKStringFromUtf32",
                packageFQName: cinteropPkg,
                receiverType: toKStringFromUtf32ReceiverType,
                parameters: [],
                returnType: types.stringType,
                externalLinkName: "kk_cpointer_toKStringFromUtf32",
                symbols: symbols,
                interner: interner
            )
        }

        if let shortVarSymbolForToKString = symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]) {
            let shortVarTypeForToKString = types.make(.classType(ClassType(
                classSymbol: shortVarSymbolForToKString,
                args: [],
                nullability: .nonNull
            )))
            let toKStringShortVarReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(shortVarTypeForToKString)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKString",
                packageFQName: cinteropPkg,
                receiverType: toKStringShortVarReceiverType,
                parameters: [],
                returnType: types.stringType,
                externalLinkName: "kk_cpointer_toKStringFromUtf16",
                symbols: symbols,
                interner: interner
            )
        }

        if let uShortVarSymbolForUtf16 = symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]) {
            let uShortVarTypeForUtf16 = types.make(.classType(ClassType(
                classSymbol: uShortVarSymbolForUtf16,
                args: [],
                nullability: .nonNull
            )))
            let toKStringFromUtf16UShortReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(uShortVarTypeForUtf16)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKStringFromUtf16",
                packageFQName: cinteropPkg,
                receiverType: toKStringFromUtf16UShortReceiverType,
                parameters: [],
                returnType: types.stringType,
                externalLinkName: "kk_cpointer_toKStringFromUtf16",
                symbols: symbols,
                interner: interner
            )
        }
        // STDLIB-CINTEROP-FN-032: Alias for toKStringFromUtf16(): reuses the same UTF-16 runtime decoder.
        if let uShortVarSymbolForToKString = symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]) {
            let uShortVarTypeForToKString = types.make(.classType(ClassType(
                classSymbol: uShortVarSymbolForToKString,
                args: [],
                nullability: .nonNull
            )))
            let toKStringUShortVarReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(uShortVarTypeForToKString)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKString",
                packageFQName: cinteropPkg,
                receiverType: toKStringUShortVarReceiverType,
                parameters: [],
                returnType: types.stringType,
                externalLinkName: "kk_cpointer_toKStringFromUtf16",
                symbols: symbols,
                interner: interner
            )
        }
        if let uByteVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UByteVar")]) {
            let uByteVarType = types.make(.classType(ClassType(
                classSymbol: uByteVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uByteArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "UByteArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uByteArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uByteVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uByteArrayReceiverType,
                parameters: [],
                returnType: uByteArrayToCValuesReturnType,
                externalLinkName: "kk_uByteArray_toCValues",
                symbols: symbols,
                interner: interner
            )
        }
    }
}
