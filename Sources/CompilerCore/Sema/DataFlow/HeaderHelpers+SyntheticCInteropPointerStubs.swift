extension DataFlowSemaPhase {
    func registerCInteropPointerConversionStubs(
        cinteropPkg: [InternedString],
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let pointerToLongFunctionName = interner.intern("toLong")
        let pointerToLongFunctionFQName = cinteropPkg + [pointerToLongFunctionName]
        let pointerToLongTypeParameterName = interner.intern("T")
        let pointerToLongTypeParameterFQName = pointerToLongFunctionFQName + [pointerToLongTypeParameterName]
        let pointerToLongTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: pointerToLongTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pointerToLongTypeParameterName,
                fqName: pointerToLongTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.insertFlags([.synthetic], for: pointerToLongTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cPointedType], for: pointerToLongTypeParameterSymbol)
        let pointerToLongTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pointerToLongTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pointerToLongNullableReceiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(pointerToLongTypeParameterType)],
            nullability: .nullable
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "toLong",
            packageFQName: cinteropPkg,
            receiverType: pointerToLongNullableReceiverType,
            parameters: [],
            returnType: types.longType,
            typeParameterSymbols: [pointerToLongTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            externalLinkName: "kk_cpointer_toLong",
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        let unwrapHolderFunctionName = interner.intern("unwrapKotlinObjectHolder")
        let unwrapHolderFunctionFQName = cinteropPkg + [unwrapHolderFunctionName]
        let unwrapHolderTypeParameterName = interner.intern("T")
        let unwrapHolderTypeParameterFQName = unwrapHolderFunctionFQName + [unwrapHolderTypeParameterName]
        let unwrapHolderTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: unwrapHolderTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: unwrapHolderTypeParameterName,
                fqName: unwrapHolderTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: unwrapHolderTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: unwrapHolderTypeParameterSymbol)
        _ = types.make(.typeParam(TypeParamType(
            symbol: unwrapHolderTypeParameterSymbol,
            nullability: .nonNull
        )))
        _ = if let cOpaquePointerSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("COpaquePointer")]) {
            types.make(.classType(ClassType(
                classSymbol: cOpaquePointerSymbol,
                args: [],
                nullability: .nullable
            )))
        } else {
            types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.star],
                nullability: .nullable
            )))
        }
    }

    func registerCInteropCPointerMembers(
        cinteropPkg: [InternedString],
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        byteVarOfSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        // Declare T so member lookups can substitute the pointee type for
        // `pointed`, `get`, and `reinterpret`.
        configureSingleTypeParameterNominal(
            ownerSymbol: cPointerSymbol,
            fqName: cinteropPkg + [interner.intern("CPointer")],
            parameterName: "T",
            supertype: nil,
            symbols: symbols,
            types: types,
            interner: interner
        )
        var cPointerElementType = cPointedType
        if let cPointerTypeParameter = types.nominalTypeParameterSymbols(for: cPointerSymbol).first {
            symbols.setTypeParameterUpperBounds([cPointedType], for: cPointerTypeParameter)
            cPointerElementType = types.make(.typeParam(TypeParamType(
                symbol: cPointerTypeParameter,
                nullability: .nonNull
            )))
        }
        let cPointerGenericType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(cPointerElementType)],
            nullability: .nonNull
        )))
        let cPointerStarType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))

        // Reads the pointee var box via kk_cpointer_pointed (structural
        // CVariable value on the same address).
        registerAtomicReadOnlyProperty(
            ownerSymbol: cPointerSymbol,
            propertyName: "pointed",
            valueType: cPointerElementType,
            getterLinkName: "kk_cpointer_pointed",
            symbols: symbols,
            interner: interner
        )
        // The generic operator is an extension, allowing the more specific
        // source Byte pointer operator to return its primitive value.
        let getTypeParameterFQName = cinteropPkg + [interner.intern("get"), interner.intern("T")]
        let getTypeParameter = symbols.lookup(fqName: getTypeParameterFQName) ?? symbols.define(
            kind: .typeParameter,
            name: interner.intern("T"),
            fqName: getTypeParameterFQName,
            declSite: nil,
            visibility: .private,
            flags: [.synthetic]
        )
        symbols.setTypeParameterUpperBounds([cPointedType], for: getTypeParameter)
        let getElementType = types.make(.typeParam(TypeParamType(symbol: getTypeParameter, nullability: .nonNull)))
        let getReceiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol, args: [.invariant(getElementType)], nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "get",
            packageFQName: cinteropPkg,
            receiverType: getReceiverType,
            parameters: [(name: "index", type: types.intType)],
            returnType: getElementType,
            typeParameterSymbols: [getTypeParameter],
            typeParameterUpperBoundsList: [[cPointedType]],
            externalLinkName: "kk_cpointer_get",
            flags: [.synthetic, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        let reinterpretRName = interner.intern("R")
        let reinterpretFunctionFQName = cinteropPkg + [interner.intern("CPointer"), interner.intern("reinterpret")]
        let reinterpretRSymbol: SymbolID = if let existing = symbols.lookup(fqName: reinterpretFunctionFQName + [reinterpretRName]) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: reinterpretRName,
                fqName: reinterpretFunctionFQName + [reinterpretRName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.setTypeParameterUpperBounds([cPointedType], for: reinterpretRSymbol)
        let reinterpretRType = types.make(.typeParam(TypeParamType(
            symbol: reinterpretRSymbol,
            nullability: .nonNull
        )))
        let reinterpretReturnType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(reinterpretRType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeMemberFunction(
            named: "reinterpret",
            ownerSymbol: cPointerSymbol,
            receiverType: cPointerGenericType,
            parameters: [],
            returnType: reinterpretReturnType,
            typeParameterSymbols: types.nominalTypeParameterSymbols(for: cPointerSymbol) + [reinterpretRSymbol],
            typeParameterUpperBoundsList: [[cPointedType], [cPointedType]],
            classTypeParameterCount: 1,
            reifiedTypeParameterIndices: [1],
            externalLinkName: "kk_cpointer_reinterpret",
            symbols: symbols,
            interner: interner
        )

        // ByteVar is a typealias for ByteVarOf<Byte>, so the concrete nominal
        // must be used here — a ClassType built on the alias symbol cannot
        // satisfy bound checks or member lookups.
        do {
            let byteVarTypeForToKString = types.make(.classType(ClassType(
                classSymbol: byteVarOfSymbol,
                args: [.invariant(types.byteType)],
                nullability: .nonNull
            )))
            let toKStringByteVarReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(byteVarTypeForToKString)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKString",
                packageFQName: cinteropPkg,
                receiverType: toKStringByteVarReceiverType,
                parameters: [],
                returnType: types.stringType,
                externalLinkName: "kk_cpointer_toKString",
                symbols: symbols,
                interner: interner
            )
        }
        return cPointerStarType
    }

    func registerCInteropPointerUtilityFunctions(
        cinteropPkg: [InternedString],
        nativePtrSymbol: SymbolID,
        nativePtrType: TypeID,
        cVariableType: TypeID,
        cPointedType: TypeID,
        cPointerSymbol: SymbolID,
        byteVarOfSymbol: SymbolID,
        memScopeSymbol: SymbolID,
        cValuesSymbol: SymbolID,
        nativePlacementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        registerSyntheticNativeMemberFunction(
            named: "toLong",
            ownerSymbol: nativePtrSymbol,
            receiverType: nativePtrType,
            parameters: [],
            returnType: types.longType,
            externalLinkName: "kk_native_ptr_toLong",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "nativeNullPtr",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [],
            returnType: nativePtrType,
            externalLinkName: "kk_native_null_ptr",
            symbols: symbols,
            interner: interner
        )
        let sizeOfName = interner.intern("sizeOf")
        let sizeOfFQName = cinteropPkg + [sizeOfName]
        let sizeOfT: SymbolID = if let existing = symbols.lookup(fqName: sizeOfFQName + [interner.intern("T")]) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: interner.intern("T"),
                fqName: sizeOfFQName + [interner.intern("T")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.setTypeParameterUpperBounds([cVariableType], for: sizeOfT)
        registerSyntheticNativeTopLevelFunction(
            named: "sizeOf",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [],
            returnType: types.longType,
            typeParameterSymbols: [sizeOfT],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            externalLinkName: "kk_cinterop_sizeof",
            symbols: symbols,
            interner: interner
        )
        let alignOfName = interner.intern("alignOf")
        let alignOfFQName = cinteropPkg + [alignOfName]
        let alignOfT: SymbolID = if let existing = symbols.lookup(fqName: alignOfFQName + [interner.intern("T")]) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: interner.intern("T"),
                fqName: alignOfFQName + [interner.intern("T")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.setTypeParameterUpperBounds([cVariableType], for: alignOfT)
        registerSyntheticNativeTopLevelFunction(
            named: "alignOf",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [],
            returnType: types.longType,
            typeParameterSymbols: [alignOfT],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            externalLinkName: "kk_cinterop_alignof",
            symbols: symbols,
            interner: interner
        )
        let interpretCPointerName = interner.intern("interpretCPointer")
        let interpretCPointerFQName = cinteropPkg + [interpretCPointerName]
        let interpretCPointerT: SymbolID = if let existing = symbols.lookup(fqName: interpretCPointerFQName + [interner.intern("T")]) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: interner.intern("T"),
                fqName: interpretCPointerFQName + [interner.intern("T")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.setTypeParameterUpperBounds([cPointedType], for: interpretCPointerT)
        let interpretCPointerTType = types.make(.typeParam(TypeParamType(
            symbol: interpretCPointerT,
            nullability: .nonNull
        )))
        let interpretCPointerReturnType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(interpretCPointerTType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "interpretCPointer",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            returnType: interpretCPointerReturnType,
            typeParameterSymbols: [interpretCPointerT],
            typeParameterUpperBoundsList: [[cPointedType]],
            reifiedTypeParameterIndices: [0],
            externalLinkName: "kk_interpret_cpointer",
            symbols: symbols,
            interner: interner
        )
        let longToCPointerName = interner.intern("toCPointer")
        let longToCPointerFQName = cinteropPkg + [longToCPointerName]
        let longToCPointerT: SymbolID = if let existing = symbols.lookup(fqName: longToCPointerFQName + [interner.intern("T")]) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: interner.intern("T"),
                fqName: longToCPointerFQName + [interner.intern("T")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([cPointedType], for: longToCPointerT)
        let longToCPointerTType = types.make(.typeParam(TypeParamType(
            symbol: longToCPointerT,
            nullability: .nonNull
        )))
        let longToCPointerReturnType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(longToCPointerTType)],
            nullability: .nullable
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "toCPointer",
            packageFQName: cinteropPkg,
            receiverType: types.longType,
            parameters: [],
            returnType: longToCPointerReturnType,
            typeParameterSymbols: [longToCPointerT],
            typeParameterUpperBoundsList: [[cPointedType]],
            externalLinkName: "kk_long_to_cpointer",
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        // Member extension on MemScope so `s.cstr` inside memScoped picks the
        // arena-allocated UTF-8 buffer.
        // ByteVar is a typealias for ByteVarOf<Byte>; build the arg on the
        // concrete nominal so bound checks and member lookups resolve.
        do {
            let byteVarForCstr = types.make(.classType(ClassType(
                classSymbol: byteVarOfSymbol,
                args: [.invariant(types.byteType)],
                nullability: .nonNull
            )))
            let cstrReturnType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(byteVarForCstr)],
                nullability: .nonNull
            )))
            let cstrPropertyName = interner.intern("cstr")
            let cstrPropertyFQName = cinteropPkg + [interner.intern("MemScope"), cstrPropertyName]
            if symbols.lookupAll(fqName: cstrPropertyFQName).contains(where: { symbols.symbol($0)?.kind == .property }) {
            } else {
                let cstrPropertySymbol = symbols.define(
                    kind: .property,
                    name: cstrPropertyName,
                    fqName: cstrPropertyFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic, .memberExtension]
                )
                symbols.setParentSymbol(memScopeSymbol, for: cstrPropertySymbol)
                symbols.setExtensionPropertyReceiverType(types.stringType, for: cstrPropertySymbol)
                symbols.setPropertyType(cstrReturnType, for: cstrPropertySymbol)
                symbols.setExternalLinkName("kk_string_to_cptr", for: cstrPropertySymbol)
                let cstrGetterName = interner.intern("$get")
                let cstrGetterSymbol = symbols.define(
                    kind: .function,
                    name: cstrGetterName,
                    fqName: cstrPropertyFQName + [cstrGetterName],
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(cstrPropertySymbol, for: cstrGetterSymbol)
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: types.stringType,
                        parameterTypes: [],
                        returnType: cstrReturnType
                    ),
                    for: cstrGetterSymbol
                )
                symbols.setExternalLinkName("kk_string_to_cptr", for: cstrGetterSymbol)
                symbols.setExtensionPropertyGetterAccessor(cstrGetterSymbol, for: cstrPropertySymbol)
                symbols.setAccessorOwnerProperty(cstrPropertySymbol, for: cstrGetterSymbol)
            }
        }
        configureSingleTypeParameterNominal(
            ownerSymbol: cValuesSymbol,
            fqName: cinteropPkg + [interner.intern("CValues")],
            parameterName: "T",
            supertype: nil,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let cValuesT = types.nominalTypeParameterSymbols(for: cValuesSymbol).first {
            let cValuesTType = types.make(.typeParam(TypeParamType(
                symbol: cValuesT,
                nullability: .nonNull
            )))
            let cValuesGenericType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(cValuesTType)],
                nullability: .nonNull
            )))
            let getPointerReturnType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cValuesTType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeMemberFunction(
                named: "getPointer",
                ownerSymbol: cValuesSymbol,
                receiverType: cValuesGenericType,
                parameters: [(name: "scope", type: nativePlacementType)],
                returnType: getPointerReturnType,
                typeParameterSymbols: [cValuesT],
                classTypeParameterCount: 1,
                externalLinkName: "kk_cvalues_get_pointer",
                symbols: symbols,
                interner: interner
            )
        }
    }
}
