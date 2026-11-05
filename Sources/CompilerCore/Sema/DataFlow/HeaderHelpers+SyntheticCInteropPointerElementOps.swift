extension DataFlowSemaPhase {
    /// KUU-4028: upstream kotlinx.cinterop pointer element access that was
    /// missing from the synthetic layer — `CPointer.getPointer(scope)`
    /// (identity, upstream `CPointer` overrides `CValuesRef.getPointer` to
    /// return `this`), `CPointer.rawValue`, the `Long` index `get`, and the
    /// per-kind `plus`/`set` operators from upstream `Generated.kt` /
    /// `Types.kt` (`CPointer<T : XVarOf<*>>?.plus`, `CPointer<XVarOf<T>>.set`,
    /// `CPointer<CPointerVarOf<T>>.get/set/plus`).
    ///
    /// This backend models `IntVar`, `LongVar`, ... as concrete classes rather
    /// than upstream's `XVarOf<T>` generics, so the receivers are the concrete
    /// `CPointer<ConcreteVar>` shapes; `ByteVar`/`BooleanVar`-style aliases
    /// resolve to their `*VarOf<Byte>` concrete nominals exactly like the
    /// `toKString` registration does.
    func registerCInteropPointerElementOperators(
        cinteropPkg: [InternedString],
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        cPointerStarType: TypeID,
        nativePtrType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let classTypeParameters = types.nominalTypeParameterSymbols(for: cPointerSymbol)
        let cPointerElementType = classTypeParameters.first.map {
            types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull)))
        } ?? cPointedType
        let cPointerGenericType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(cPointerElementType)],
            nullability: .nonNull
        )))

        // `CPointer<T>.getPointer(scope): CPointer<T>` — upstream returns
        // `this`; the scope argument is accepted for signature parity and
        // ignored at runtime.
        if let nativePlacementSymbol = symbols.lookup(
            fqName: cinteropPkg + [interner.intern("NativePlacement")]
        ) {
            let scopeType = types.make(.classType(ClassType(
                classSymbol: nativePlacementSymbol,
                args: [],
                nullability: .nonNull
            )))
            registerSyntheticNativeMemberFunction(
                named: "getPointer",
                ownerSymbol: cPointerSymbol,
                receiverType: cPointerGenericType,
                parameters: [(name: "scope", type: scopeType)],
                returnType: cPointerGenericType,
                typeParameterSymbols: classTypeParameters,
                typeParameterUpperBoundsList: classTypeParameters.map { _ in [cPointedType] },
                classTypeParameterCount: 1,
                externalLinkName: "kk_cpointer_get_pointer",
                symbols: symbols,
                interner: interner
            )
        }

        // `CPointer<T>.rawValue: NativePtr` — the raw address as a NativePtr
        // box (upstream `CPointer.rawValue`).
        registerAtomicReadOnlyProperty(
            ownerSymbol: cPointerSymbol,
            propertyName: "rawValue",
            valueType: nativePtrType,
            getterLinkName: "kk_cpointer_raw_ptr",
            symbols: symbols,
            interner: interner
        )

        // `CPointer<T>.get(index: Long): T` — the Int-index `get` is
        // registered in registerCInteropCPointerMembers; upstream declares
        // both index widths.
        do {
            let longGetTypeParameterName = interner.intern("T")
            let longGetTypeParameterFQName = cinteropPkg
                + [interner.intern("get"), longGetTypeParameterName, interner.intern("$longIndex")]
            let longGetTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
                fqName: longGetTypeParameterFQName
            ) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: longGetTypeParameterName,
                    fqName: longGetTypeParameterFQName,
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
            }
            symbols.setTypeParameterUpperBounds([cPointedType], for: longGetTypeParameterSymbol)
            let longGetElementType = types.make(.typeParam(TypeParamType(
                symbol: longGetTypeParameterSymbol,
                nullability: .nonNull
            )))
            let longGetReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(longGetElementType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "get",
                packageFQName: cinteropPkg,
                receiverType: longGetReceiverType,
                parameters: [(name: "index", type: types.longType)],
                returnType: longGetElementType,
                typeParameterSymbols: [longGetTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                externalLinkName: "kk_cpointer_get",
                flags: [.synthetic, .operatorFunction],
                symbols: symbols,
                interner: interner
            )
        }

        // Per-kind `plus`/`set` operators. `plus` advances by
        // `index * sizeOf<pointee>()` — the runtime derives the element size
        // from the pointer box's stored pointee type token, so a single
        // `kk_cpointer_plus` entry point covers every kind. `set` writes the
        // primitive value through a per-kind store bridge.
        var elementKinds: [(pointee: TypeID, value: TypeID, setLinkName: String)] = []
        func appendElementKind(
            className: String,
            genericArgument: TypeID?,
            valueType: TypeID,
            setLinkName: String
        ) {
            guard let classSymbol = symbols.lookup(
                fqName: cinteropPkg + [interner.intern(className)]
            ) else { return }
            let args: [TypeArg] = genericArgument.map { [.invariant($0)] } ?? []
            let pointeeType = types.make(.classType(ClassType(
                classSymbol: classSymbol,
                args: args,
                nullability: .nonNull
            )))
            elementKinds.append((pointeeType, valueType, setLinkName))
        }
        appendElementKind(className: "BooleanVarOf", genericArgument: types.booleanType, valueType: types.booleanType, setLinkName: "kk_cpointer_set_bool")
        appendElementKind(className: "ByteVarOf", genericArgument: types.byteType, valueType: types.byteType, setLinkName: "kk_cpointer_set_byte")
        appendElementKind(className: "ShortVar", genericArgument: nil, valueType: types.shortType, setLinkName: "kk_cpointer_set_short")
        appendElementKind(className: "IntVar", genericArgument: nil, valueType: types.intType, setLinkName: "kk_cpointer_set_int")
        appendElementKind(className: "LongVar", genericArgument: nil, valueType: types.longType, setLinkName: "kk_cpointer_set_long")
        appendElementKind(className: "UByteVar", genericArgument: nil, valueType: types.ubyteType, setLinkName: "kk_cpointer_set_ubyte")
        appendElementKind(className: "UShortVar", genericArgument: nil, valueType: types.ushortType, setLinkName: "kk_cpointer_set_ushort")
        appendElementKind(className: "UIntVar", genericArgument: nil, valueType: types.uintType, setLinkName: "kk_cpointer_set_uint")
        appendElementKind(className: "ULongVar", genericArgument: nil, valueType: types.ulongType, setLinkName: "kk_cpointer_set_ulong")
        appendElementKind(className: "FloatVar", genericArgument: nil, valueType: types.floatType, setLinkName: "kk_cpointer_set_float")
        appendElementKind(className: "DoubleVar", genericArgument: nil, valueType: types.doubleType, setLinkName: "kk_cpointer_set_double")

        for kind in elementKinds {
            let nullableReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(kind.pointee)],
                nullability: .nullable
            )))
            let nonNullReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(kind.pointee)],
                nullability: .nonNull
            )))
            for indexType in [types.intType, types.longType] {
                registerSyntheticNativeTopLevelFunction(
                    named: "plus",
                    packageFQName: cinteropPkg,
                    receiverType: nullableReceiverType,
                    parameters: [(name: "index", type: indexType)],
                    returnType: nullableReceiverType,
                    externalLinkName: "kk_cpointer_plus",
                    flags: [.synthetic, .operatorFunction],
                    symbols: symbols,
                    interner: interner
                )
                registerSyntheticNativeTopLevelFunction(
                    named: "set",
                    packageFQName: cinteropPkg,
                    receiverType: nonNullReceiverType,
                    parameters: [
                        (name: "index", type: indexType),
                        (name: "value", type: kind.value),
                    ],
                    returnType: types.unitType,
                    externalLinkName: kind.setLinkName,
                    flags: [.synthetic, .operatorFunction],
                    symbols: symbols,
                    interner: interner
                )
            }
        }

        // Pointer-element arrays: `CPointer<CPointerVarOf<P>>` where
        // `P : CPointer<*>`. Upstream declares `plus` and `set` (taking `P?`)
        // for this shape. Reads intentionally keep the generic
        // `CPointer<T>.get`, which yields the `CPointerVarOf<P>` var whose
        // `.value` is the stored `P?` — a dedicated `get` returning `P?`
        // would be ambiguous with the generic operator during resolution.
        if let cPointerVarOfSymbol = symbols.lookup(
            fqName: cinteropPkg + [interner.intern("CPointerVarOf")]
        ) {
            for opName in ["plus", "set"] {
                for indexTypeName in ["int", "long"] {
                    let typeParameterName = interner.intern("P")
                    let typeParameterFQName = cinteropPkg
                        + [interner.intern(opName), interner.intern("CPointerVarOf"), interner.intern(indexTypeName)]
                        + [typeParameterName]
                    let typeParameterSymbol: SymbolID = if let existing = symbols.lookup(
                        fqName: typeParameterFQName
                    ) {
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
                    symbols.setTypeParameterUpperBounds([cPointerStarType], for: typeParameterSymbol)
                    let pType = types.make(.typeParam(TypeParamType(
                        symbol: typeParameterSymbol,
                        nullability: .nonNull
                    )))
                    let pVarType = types.make(.classType(ClassType(
                        classSymbol: cPointerVarOfSymbol,
                        args: [.invariant(pType)],
                        nullability: .nonNull
                    )))
                    let indexType: TypeID = indexTypeName == "int" ? types.intType : types.longType
                    switch opName {
                    case "plus":
                        let receiverType = types.make(.classType(ClassType(
                            classSymbol: cPointerSymbol,
                            args: [.invariant(pVarType)],
                            nullability: .nullable
                        )))
                        registerSyntheticNativeTopLevelFunction(
                            named: "plus",
                            packageFQName: cinteropPkg,
                            receiverType: receiverType,
                            parameters: [(name: "index", type: indexType)],
                            returnType: receiverType,
                            typeParameterSymbols: [typeParameterSymbol],
                            typeParameterUpperBoundsList: [[cPointerStarType]],
                            externalLinkName: "kk_cpointer_plus",
                            flags: [.synthetic, .operatorFunction],
                            symbols: symbols,
                            interner: interner
                        )
                    case "set":
                        let nullablePType = types.make(.typeParam(TypeParamType(
                            symbol: typeParameterSymbol,
                            nullability: .nullable
                        )))
                        let receiverType = types.make(.classType(ClassType(
                            classSymbol: cPointerSymbol,
                            args: [.invariant(pVarType)],
                            nullability: .nonNull
                        )))
                        registerSyntheticNativeTopLevelFunction(
                            named: "set",
                            packageFQName: cinteropPkg,
                            receiverType: receiverType,
                            parameters: [
                                (name: "index", type: indexType),
                                (name: "value", type: nullablePType),
                            ],
                            returnType: types.unitType,
                            typeParameterSymbols: [typeParameterSymbol],
                            typeParameterUpperBoundsList: [[cPointerStarType]],
                            externalLinkName: "kk_cpointer_set_cpointer",
                            flags: [.synthetic, .operatorFunction],
                            symbols: symbols,
                            interner: interner
                        )
                    default:
                        break
                    }
                }
            }
        }
    }
}
