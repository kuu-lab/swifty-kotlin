
/// Synthetic stdlib stubs split from `HeaderHelpers+SyntheticComparableAndCollectionStubs.swift`:
/// Array<T> and primitive array types (TYPE-103) plus the synthetic factory function helper.
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    // MARK: - Array<T> and primitive arrays (TYPE-103)

    func registerSyntheticArrayStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let kotlinPkg: [InternedString] = [interner.intern("kotlin")]

        // --- kotlin.Array<T> ---
        let arrayFQName = kotlinPkg + [interner.intern("Array")]
        let arraySymbol: SymbolID = if let existing = symbols.lookup(fqName: arrayFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: interner.intern("Array"),
                fqName: arrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        let tParamName = interner.intern("T")
        let tParamSymbol = symbols.lookup(fqName: arrayFQName + [tParamName]) ?? symbols.define(
            kind: .typeParameter,
            name: tParamName,
            fqName: arrayFQName + [tParamName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([tParamSymbol], for: arraySymbol)
        types.setNominalTypeParameterVariances([.invariant], for: arraySymbol)
        let sizeReturnType = types.intType
        let sizeName = interner.intern("size")
        let sizeFQName = arrayFQName + [sizeName]
        if symbols.lookup(fqName: sizeFQName) == nil {
            let sizeSym = symbols.define(
                kind: .property,
                name: sizeName,
                fqName: sizeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: sizeSym)
            symbols.setPropertyType(sizeReturnType, for: sizeSym)
            symbols.setExternalLinkName("kk_array_size", for: sizeSym)
        }

        let toListName = interner.intern("toList")
        let toListFQName = arrayFQName + [toListName]
        if symbols.lookup(fqName: toListFQName) == nil {
            let toListSym = symbols.define(
                kind: .function,
                name: toListName,
                fqName: toListFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: toListSym)
            symbols.setExternalLinkName("kk_array_toList", for: toListSym)

            // Get List<T> type for return type
            let listFQName = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
            if let listSymbol = symbols.lookup(fqName: listFQName) {
                let listElementType = types.make(.typeParam(TypeParamType(
                    symbol: tParamSymbol,
                    nullability: .nonNull
                )))
                let listReturnType = types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(listElementType)],
                    nullability: .nonNull
                )))

                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [.invariant(listElementType)],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: listReturnType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: [tParamSymbol]
                    ),
                    for: toListSym
                )
            }
        }

        // KSP-657: arrayOf / emptyArray / arrayOfNulls factories are now declared
        // as bundled Kotlin intrinsics in Stdlib/kotlin/ArrayIntrinsics.kt.

        // --- Array extension functions: contentDeepEquals, contentDeepToString, contentDeepHashCode, contentHashCode, copyInto, sliceArray, reversedArray ---
        //
        // KSP-658: generic Array<T>.contentEquals / contentToString / copyOf /
        // copyOfRange are bundled Kotlin source
        // (Stdlib/kotlin/collections/ArrayContentAndCopy.kt); their synthetic
        // stubs were removed so source resolution takes precedence.

        // contentDeepEquals(other: Array<T>): Boolean
        let contentDeepEqualsName = interner.intern("contentDeepEquals")
        let contentDeepEqualsFQName = arrayFQName + [contentDeepEqualsName]
        if symbols.lookup(fqName: contentDeepEqualsFQName) == nil {
            let contentDeepEqualsSymbol = symbols.define(
                kind: .function,
                name: contentDeepEqualsName,
                fqName: contentDeepEqualsFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentDeepEqualsSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            let otherArrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [otherArrayType],
                    returnType: types.booleanType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentDeepEqualsSymbol
            )
            symbols.setExternalLinkName("kk_array_contentDeepEquals", for: contentDeepEqualsSymbol)
        }

        // contentHashCode(): Int
        let contentHashCodeName = interner.intern("contentHashCode")
        let contentHashCodeFQName = arrayFQName + [contentHashCodeName]
        if symbols.lookup(fqName: contentHashCodeFQName) == nil {
            let contentHashCodeSymbol = symbols.define(
                kind: .function,
                name: contentHashCodeName,
                fqName: contentHashCodeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentHashCodeSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.intType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentHashCodeSymbol
            )
            symbols.setExternalLinkName("kk_array_contentHashCode", for: contentHashCodeSymbol)
        }

        // contentDeepToString(): String
        let contentDeepToStringName = interner.intern("contentDeepToString")
        let contentDeepToStringFQName = arrayFQName + [contentDeepToStringName]
        if symbols.lookup(fqName: contentDeepToStringFQName) == nil {
            let contentDeepToStringSymbol = symbols.define(
                kind: .function,
                name: contentDeepToStringName,
                fqName: contentDeepToStringFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentDeepToStringSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.stringType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentDeepToStringSymbol
            )
            symbols.setExternalLinkName("kk_array_contentDeepToString", for: contentDeepToStringSymbol)
        }

        // contentDeepHashCode(): Int
        let contentDeepHashCodeName = interner.intern("contentDeepHashCode")
        let contentDeepHashCodeFQName = arrayFQName + [contentDeepHashCodeName]
        if symbols.lookup(fqName: contentDeepHashCodeFQName) == nil {
            let contentDeepHashCodeSymbol = symbols.define(
                kind: .function,
                name: contentDeepHashCodeName,
                fqName: contentDeepHashCodeFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: contentDeepHashCodeSymbol)
            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let receiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: types.intType,
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: contentDeepHashCodeSymbol
            )
            symbols.setExternalLinkName("kk_array_contentDeepHashCode", for: contentDeepHashCodeSymbol)
        }

        // reversedArray(): Array<T>
        let reversedArrayName = interner.intern("reversedArray")
        let reversedArrayFQName = arrayFQName + [reversedArrayName]
        if symbols.lookup(fqName: reversedArrayFQName) == nil {
            let reversedArraySymbol = symbols.define(
                kind: .function,
                name: reversedArrayName,
                fqName: reversedArrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: reversedArraySymbol)
            symbols.setExternalLinkName("kk_array_reversedArray", for: reversedArraySymbol)

            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let arrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: arrayType,
                    parameterTypes: [],
                    returnType: arrayType,
                    isSuspend: false,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: reversedArraySymbol
            )
        }

        // copyInto(destination, destinationOffset, startIndex, endIndex): Array<T>
        let copyIntoName = interner.intern("copyInto")
        let copyIntoFQName = arrayFQName + [copyIntoName]
        if symbols.lookup(fqName: copyIntoFQName) == nil {
            let copyIntoSymbol = symbols.define(
                kind: .function,
                name: copyIntoName,
                fqName: copyIntoFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: copyIntoSymbol)
            symbols.setExternalLinkName("kk_array_copyInto", for: copyIntoSymbol)

            let arrayTypeParam = types.make(.typeParam(TypeParamType(symbol: tParamSymbol, nullability: .nonNull)))
            let arrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [.invariant(arrayTypeParam)],
                nullability: .nonNull
            )))
            let parameterSymbols = ["destination", "destinationOffset", "startIndex", "endIndex"].map { parameterName in
                let internedParameterName = interner.intern(parameterName)
                let parameterSymbol = symbols.define(
                    kind: .valueParameter,
                    name: internedParameterName,
                    fqName: copyIntoFQName + [internedParameterName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(copyIntoSymbol, for: parameterSymbol)
                return parameterSymbol
            }
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: arrayType,
                    parameterTypes: [arrayType, types.intType, types.intType, types.intType],
                    returnType: arrayType,
                    isSuspend: false,
                    valueParameterSymbols: parameterSymbols,
                    valueParameterHasDefaultValues: [false, true, true, true],
                    valueParameterIsVararg: [false, false, false, false],
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: copyIntoSymbol
            )
        }

        // sliceArray(indices: IntRange) and sliceArray(indices: Iterable<Int>)
        let sliceArrayName = interner.intern("sliceArray")
        let sliceArrayFQName = arrayFQName + [sliceArrayName]
        let arrayElementType = types.make(.typeParam(TypeParamType(
            symbol: tParamSymbol,
            nullability: .nonNull
        )))
        let arrayReceiverType = types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.invariant(arrayElementType)],
            nullability: .nonNull
        )))
        let listOfIntType = symbols.lookup(
            fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
        ).map { listSymbol in
            types.make(.classType(ClassType(
                classSymbol: listSymbol,
                args: [.out(types.intType)],
                nullability: .nonNull
            )))
        }
        let existingSliceArray = symbols.lookupAll(fqName: sliceArrayFQName)

        func registerGenericSliceArrayOverload(
            parameterType: TypeID,
            externalLinkName: String
        ) {
            let alreadyRegistered = existingSliceArray.contains { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.receiverType == arrayReceiverType
                    && signature.parameterTypes == [parameterType]
                    && symbols.externalLinkName(for: symbolID) == externalLinkName
            }
            guard !alreadyRegistered else { return }

            let sliceArraySymbol = symbols.define(
                kind: .function,
                name: sliceArrayName,
                fqName: sliceArrayFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(arraySymbol, for: sliceArraySymbol)
            symbols.setExternalLinkName(externalLinkName, for: sliceArraySymbol)

            let indicesName = interner.intern("indices")
            let indicesSymbol = symbols.define(
                kind: .valueParameter,
                name: indicesName,
                fqName: sliceArrayFQName + [interner.intern("indices$\(externalLinkName)")],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(sliceArraySymbol, for: indicesSymbol)

            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: arrayReceiverType,
                    parameterTypes: [parameterType],
                    returnType: arrayReceiverType,
                    isSuspend: false,
                    valueParameterSymbols: [indicesSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [tParamSymbol],
                    classTypeParameterCount: 1
                ),
                for: sliceArraySymbol
            )
        }

        registerGenericSliceArrayOverload(
            parameterType: types.intType,
            externalLinkName: "kk_array_sliceArray_range"
        )
        if let listOfIntType {
            registerGenericSliceArrayOverload(
                parameterType: listOfIntType,
                externalLinkName: "kk_array_sliceArray_iterable"
            )
        }

        // --- Primitive array types: IntArray, LongArray, etc. ---
        let primitiveArrayNames = [
            "IntArray",
            "LongArray",
            "UIntArray",
            "ULongArray",
            "DoubleArray",
            "FloatArray",
            "BooleanArray",
            "CharArray",
            "ByteArray",
            "ShortArray",
            "UByteArray",
            "UShortArray",
        ]
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            let sym: SymbolID = if let existing = symbols.lookup(fqName: fqName) {
                existing
            } else {
                symbols.define(
                    kind: .class,
                    name: primName,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
            }
            // Register size property independently of class existence,
            // so that even if the class was defined elsewhere without size,
            // we still add the property.
            let primSizeFQName = fqName + [sizeName]
            if symbols.lookup(fqName: primSizeFQName) == nil {
                let primSizeSym = symbols.define(
                    kind: .property,
                    name: sizeName,
                    fqName: primSizeFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(sym, for: primSizeSym)
                symbols.setPropertyType(sizeReturnType, for: primSizeSym)

                // Set external link name for size property
                let sizeLinkName: String = switch name {
                case "IntArray": "kk_intArray_size"
                case "LongArray": "kk_longArray_size"
                case "ByteArray": "kk_byteArray_size"
                case "ShortArray": "kk_shortArray_size"
                case "UIntArray": "kk_uIntArray_size"
                case "ULongArray": "kk_uLongArray_size"
                case "DoubleArray": "kk_doubleArray_size"
                case "FloatArray": "kk_floatArray_size"
                case "BooleanArray": "kk_booleanArray_size"
                case "CharArray": "kk_charArray_size"
                case "UByteArray": "kk_uByteArray_size"
                case "UShortArray": "kk_uShortArray_size"
                default: "kk_array_size"
                }
                symbols.setExternalLinkName(sizeLinkName, for: primSizeSym)
            }
        }

        let listFQName = [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
        let listInterfaceSym = symbols.lookup(fqName: listFQName)

        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let toListName = interner.intern("toList")
            let toListFQName = fqName + [toListName]
            if symbols.lookup(fqName: toListFQName) == nil, let listInterfaceSym = listInterfaceSym {
                let toListSym = symbols.define(
                    kind: .function,
                    name: toListName,
                    fqName: toListFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: toListSym)

                let externalLinkName: String = switch name {
                case "IntArray": "kk_intArray_toList"
                case "LongArray": "kk_longArray_toList"
                case "ByteArray": "kk_byteArray_toList"
                case "ShortArray": "kk_shortArray_toList"
                case "UIntArray": "kk_uIntArray_toList"
                case "ULongArray": "kk_uLongArray_toList"
                case "DoubleArray": "kk_doubleArray_toList"
                case "FloatArray": "kk_floatArray_toList"
                case "BooleanArray": "kk_booleanArray_toList"
                case "CharArray": "kk_charArray_toList"
                case "UByteArray": "kk_uByteArray_toList"
                case "UShortArray": "kk_uShortArray_toList"
                default: "kk_array_toList"
                }
                symbols.setExternalLinkName(externalLinkName, for: toListSym)

                let elementType: TypeID = switch name {
                case "IntArray": types.intType
                case "LongArray": types.longType
                case "ByteArray": types.byteType
                case "ShortArray": types.shortType
                case "UIntArray": types.uintType
                case "ULongArray": types.ulongType
                case "DoubleArray": types.doubleType
                case "FloatArray": types.floatType
                case "BooleanArray": types.booleanType
                case "CharArray": types.charType
                case "UByteArray": types.ubyteType
                case "UShortArray": types.ushortType
                default: types.intType
                }

                let listReturnType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSym,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))

                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: listReturnType,
                        isSuspend: false
                    ),
                    for: toListSym
                )
            }
        }

        let unsignedPrimitiveArrayNames = [
            "UByteArray",
            "UShortArray",
            "UIntArray",
            "ULongArray",
        ]
        for name in unsignedPrimitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName), let listInterfaceSym = listInterfaceSym else {
                continue
            }

            let asListName = interner.intern("asList")
            let asListFQName = fqName + [asListName]
            if symbols.lookup(fqName: asListFQName) == nil {
                let asListSym = symbols.define(
                    kind: .function,
                    name: asListName,
                    fqName: asListFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: asListSym)

                let externalLinkName: String = switch name {
                case "UByteArray": "kk_uByteArray_asList"
                case "UShortArray": "kk_uShortArray_asList"
                case "UIntArray": "kk_uIntArray_asList"
                case "ULongArray": "kk_uLongArray_asList"
                default: "kk_array_toList"
                }
                symbols.setExternalLinkName(externalLinkName, for: asListSym)

                let elementType: TypeID = switch name {
                case "UByteArray": types.ubyteType
                case "UShortArray": types.ushortType
                case "UIntArray": types.uintType
                case "ULongArray": types.ulongType
                default: types.intType
                }

                let listReturnType = types.make(.classType(ClassType(
                    classSymbol: listInterfaceSym,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))

                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: listReturnType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: asListSym
                )
            }
        }

        // KSP-660: ByteArray/ShortArray/IntArray/LongArray -> unsigned array view
        // conversions (asUByteArray/asUShortArray/asUIntArray/asULongArray) are now
        // implemented in bundled Kotlin (Stdlib/kotlin/collections/UArrays.kt), which
        // delegates to the __kk_*_asU*Array runtime bridges.

        // Register toTypedArray() for unsigned primitive arrays.
        if let genericArraySymbol = symbols.lookup(fqName: arrayFQName) {
            for name in unsignedPrimitiveArrayNames {
                let primName = interner.intern(name)
                let fqName = kotlinPkg + [primName]
                guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                    continue
                }

                let toTypedArrayName = interner.intern("toTypedArray")
                let toTypedArrayFQName = fqName + [toTypedArrayName]
                if symbols.lookup(fqName: toTypedArrayFQName) == nil {
                    let toTypedArraySym = symbols.define(
                        kind: .function,
                        name: toTypedArrayName,
                        fqName: toTypedArrayFQName,
                        declSite: nil,
                        visibility: .public,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(arraySymbol, for: toTypedArraySym)
                    symbols.setExternalLinkName("kk_array_copyOf", for: toTypedArraySym)

                    let elementType: TypeID = switch name {
                    case "UByteArray": types.ubyteType
                    case "UShortArray": types.ushortType
                    case "UIntArray": types.uintType
                    case "ULongArray": types.ulongType
                    default: types.intType
                    }
                    let receiverType = types.make(.classType(ClassType(
                        classSymbol: arraySymbol,
                        args: [],
                        nullability: .nonNull
                    )))
                    let returnType = types.make(.classType(ClassType(
                        classSymbol: genericArraySymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))

                    symbols.setFunctionSignature(
                        FunctionSignature(
                            receiverType: receiverType,
                            parameterTypes: [],
                            returnType: returnType,
                            isSuspend: false,
                            valueParameterSymbols: [],
                            valueParameterHasDefaultValues: [],
                            valueParameterIsVararg: [],
                            typeParameterSymbols: []
                        ),
                        for: toTypedArraySym
                    )
                }
            }
        }

        // KSP-660: UByteArray/UShortArray/UIntArray/ULongArray -> signed array view
        // conversions (asByteArray/asShortArray/asIntArray/asLongArray) are now
        // implemented in bundled Kotlin (Stdlib/kotlin/collections/UArrays.kt), which
        // delegates to the __kk_u*Array_as*Array runtime bridges.

        // Register copyOf(newSize) and copyOf(newSize, init) for unsigned primitive arrays.
        for name in unsignedPrimitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let elementType: TypeID = switch name {
            case "UByteArray": types.ubyteType
            case "UShortArray": types.ushortType
            case "UIntArray": types.uintType
            case "ULongArray": types.ulongType
            default: types.intType
            }
            let arrayReceiverType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            let initFunctionType = types.make(.functionType(FunctionType(
                params: [types.intType],
                returnType: elementType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let copyOfName = interner.intern("copyOf")
            let copyOfFQName = fqName + [copyOfName]

            func registerCopyOfOverload(
                parameterTypes: [TypeID],
                parameterNames: [String],
                parameterFQNameSuffix: String,
                externalLinkName: String,
                flags: SymbolFlags = [.synthetic]
            ) {
                let alreadyRegistered = symbols.lookupAll(fqName: copyOfFQName).contains { symbolID in
                    guard let sig = symbols.functionSignature(for: symbolID) else { return false }
                    return sig.receiverType == arrayReceiverType
                        && sig.parameterTypes == parameterTypes
                        && sig.returnType == arrayReceiverType
                }
                guard !alreadyRegistered else { return }
                let copyOfSym = symbols.define(
                    kind: .function,
                    name: copyOfName,
                    fqName: copyOfFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: flags
                )
                symbols.setParentSymbol(arraySymbol, for: copyOfSym)
                symbols.setExternalLinkName(externalLinkName, for: copyOfSym)
                let parameterSymbols = parameterNames.map { parameterName -> SymbolID in
                    let internedParameterName = interner.intern(parameterName)
                    let parameterSymbol = symbols.define(
                        kind: .valueParameter,
                        name: internedParameterName,
                        fqName: copyOfFQName + [interner.intern("\(parameterName)$\(parameterFQNameSuffix)")],
                        declSite: nil,
                        visibility: .private,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(copyOfSym, for: parameterSymbol)
                    return parameterSymbol
                }
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: parameterTypes,
                        returnType: arrayReceiverType,
                        isSuspend: false,
                        valueParameterSymbols: parameterSymbols,
                        valueParameterHasDefaultValues: Array(repeating: false, count: parameterTypes.count),
                        valueParameterIsVararg: Array(repeating: false, count: parameterTypes.count),
                        typeParameterSymbols: []
                    ),
                    for: copyOfSym
                )
            }

            registerCopyOfOverload(
                parameterTypes: [types.intType],
                parameterNames: ["newSize"],
                parameterFQNameSuffix: "newSize",
                externalLinkName: "kk_array_copyOf_newSize"
            )
            registerCopyOfOverload(
                parameterTypes: [types.intType, initFunctionType],
                parameterNames: ["newSize", "init"],
                parameterFQNameSuffix: "newSizeInit",
                externalLinkName: "kk_array_copyOf_newSize_init",
                flags: [.synthetic, .inlineFunction, .throwingFunction]
            )
        }

        // Register copyOfRange(fromIndex, toIndex) for unsigned primitive arrays.
        for name in unsignedPrimitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let copyOfRangeName = interner.intern("copyOfRange")
            let copyOfRangeFQName = fqName + [copyOfRangeName]
            if symbols.lookup(fqName: copyOfRangeFQName) == nil {
                let copyOfRangeSym = symbols.define(
                    kind: .function,
                    name: copyOfRangeName,
                    fqName: copyOfRangeFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: copyOfRangeSym)
                symbols.setExternalLinkName("kk_array_copyOfRange", for: copyOfRangeSym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [types.intType, types.intType],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: copyOfRangeSym
                )
            }
        }

        // Register sliceArray(indices: IntRange) and sliceArray(indices: Iterable<Int>) for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let sliceArrayName = interner.intern("sliceArray")
            let sliceArrayFQName = fqName + [sliceArrayName]
            let arrayType = types.make(.classType(ClassType(
                classSymbol: arraySymbol,
                args: [],
                nullability: .nonNull
            )))
            let listOfIntType = symbols.lookup(
                fqName: [interner.intern("kotlin"), interner.intern("collections"), interner.intern("List")]
            ).map { listSymbol in
                types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.out(types.intType)],
                    nullability: .nonNull
                )))
            }
            let existingSliceArray = symbols.lookupAll(fqName: sliceArrayFQName)

            func registerPrimitiveSliceArrayOverload(
                parameterType: TypeID,
                externalLinkName: String
            ) {
                let alreadyRegistered = existingSliceArray.contains { symbolID in
                    guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                    return signature.receiverType == arrayType
                        && signature.parameterTypes == [parameterType]
                        && symbols.externalLinkName(for: symbolID) == externalLinkName
                }
                guard !alreadyRegistered else { return }

                let sliceArraySym = symbols.define(
                    kind: .function,
                    name: sliceArrayName,
                    fqName: sliceArrayFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: sliceArraySym)
                symbols.setExternalLinkName(externalLinkName, for: sliceArraySym)

                let indicesName = interner.intern("indices")
                let indicesSymbol = symbols.define(
                    kind: .valueParameter,
                    name: indicesName,
                    fqName: sliceArrayFQName + [interner.intern("indices$\(externalLinkName)")],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(sliceArraySym, for: indicesSymbol)

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [parameterType],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: [indicesSymbol],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false],
                        typeParameterSymbols: []
                    ),
                    for: sliceArraySym
                )
            }

            registerPrimitiveSliceArrayOverload(
                parameterType: types.intType,
                externalLinkName: "kk_array_sliceArray_range"
            )
            if let listOfIntType {
                registerPrimitiveSliceArrayOverload(
                    parameterType: listOfIntType,
                    externalLinkName: "kk_array_sliceArray_iterable"
                )
            }
        }

        // Register contentToString() methods for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let contentToStringName = interner.intern("contentToString")
            let contentToStringFQName = fqName + [contentToStringName]
            if symbols.lookup(fqName: contentToStringFQName) == nil {
                let contentToStringSym = symbols.define(
                    kind: .function,
                    name: contentToStringName,
                    fqName: contentToStringFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: contentToStringSym)

                let externalLinkName: String = switch name {
                case "IntArray": "kk_intArray_contentToString"
                case "LongArray": "kk_longArray_contentToString"
                case "ByteArray": "kk_byteArray_contentToString"
                case "ShortArray": "kk_shortArray_contentToString"
                case "UIntArray": "kk_uIntArray_contentToString"
                case "ULongArray": "kk_uLongArray_contentToString"
                case "DoubleArray": "kk_doubleArray_contentToString"
                case "FloatArray": "kk_floatArray_contentToString"
                case "BooleanArray": "kk_booleanArray_contentToString"
                case "CharArray": "kk_charArray_contentToString"
                case "UByteArray": "kk_uByteArray_contentToString"
                case "UShortArray": "kk_uShortArray_contentToString"
                default: fatalError("unhandled primitive array \(name) for contentToString")
                }
                symbols.setExternalLinkName(externalLinkName, for: contentToStringSym)

                let arrayReceiverType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayReceiverType,
                        parameterTypes: [],
                        returnType: types.stringType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: contentToStringSym
                )
            }
        }

        // --- ByteArray.contentEquals / ByteArray.joinToString (DEBT-DIFF-005) ---
        if let byteArraySymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern("ByteArray")]) {
            let byteArrayFQName = kotlinPkg + [interner.intern("ByteArray")]
            let byteArrayType = types.make(.classType(ClassType(
                classSymbol: byteArraySymbol,
                args: [],
                nullability: .nonNull
            )))

            let byteContentEqualsName = interner.intern("contentEquals")
            let byteContentEqualsFQName = byteArrayFQName + [byteContentEqualsName]
            if symbols.lookup(fqName: byteContentEqualsFQName) == nil {
                let contentEqualsSym = symbols.define(
                    kind: .function,
                    name: byteContentEqualsName,
                    fqName: byteContentEqualsFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(byteArraySymbol, for: contentEqualsSym)
                symbols.setExternalLinkName("kk_byteArray_contentEquals", for: contentEqualsSym)

                let otherParamName = interner.intern("other")
                let otherParamSym = symbols.define(
                    kind: .valueParameter,
                    name: otherParamName,
                    fqName: byteContentEqualsFQName + [otherParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(contentEqualsSym, for: otherParamSym)

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: byteArrayType,
                        parameterTypes: [byteArrayType],
                        returnType: types.booleanType,
                        isSuspend: false,
                        valueParameterSymbols: [otherParamSym],
                        valueParameterHasDefaultValues: [false],
                        valueParameterIsVararg: [false],
                        typeParameterSymbols: []
                    ),
                    for: contentEqualsSym
                )
            }

            // `ByteArray.joinToString` (both the plain and transform overloads) is
            // registered uniformly for all primitive array types by the
            // `primitiveArrayNames` loop below — including `ByteArray` — so it is
            // deliberately not duplicated here. (It used to be duplicated, which
            // made this block's `symbols.define` win the race and left the later
            // loop's `if symbols.lookup(...) == nil` guard permanently false for
            // `ByteArray`, silently skipping its transform overloads.)
        }

        // Register reversedArray() and copyInto(destination, destinationOffset, startIndex, endIndex) for primitive arrays.
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            guard let arraySymbol = symbols.lookup(fqName: fqName) else {
                continue
            }

            let reversedArrayName = interner.intern("reversedArray")
            let reversedArrayFQName = fqName + [reversedArrayName]
            if symbols.lookup(fqName: reversedArrayFQName) == nil {
                let reversedArraySym = symbols.define(
                    kind: .function,
                    name: reversedArrayName,
                    fqName: reversedArrayFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: reversedArraySym)
                symbols.setExternalLinkName("kk_array_reversedArray", for: reversedArraySym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: [],
                        valueParameterHasDefaultValues: [],
                        valueParameterIsVararg: [],
                        typeParameterSymbols: []
                    ),
                    for: reversedArraySym
                )
            }

            let copyIntoName = interner.intern("copyInto")
            let copyIntoFQName = fqName + [copyIntoName]
            if symbols.lookup(fqName: copyIntoFQName) == nil {
                let copyIntoSym = symbols.define(
                    kind: .function,
                    name: copyIntoName,
                    fqName: copyIntoFQName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
                )
                symbols.setParentSymbol(arraySymbol, for: copyIntoSym)
                symbols.setExternalLinkName("kk_array_copyInto", for: copyIntoSym)

                let arrayType = types.make(.classType(ClassType(
                    classSymbol: arraySymbol,
                    args: [],
                    nullability: .nonNull
                )))
                let parameterSymbols = ["destination", "destinationOffset", "startIndex", "endIndex"].map { parameterName in
                    let internedParameterName = interner.intern(parameterName)
                    let parameterSymbol = symbols.define(
                        kind: .valueParameter,
                        name: internedParameterName,
                        fqName: copyIntoFQName + [internedParameterName],
                        declSite: nil,
                        visibility: .private,
                        flags: [.synthetic]
                    )
                    symbols.setParentSymbol(copyIntoSym, for: parameterSymbol)
                    return parameterSymbol
                }

                symbols.setFunctionSignature(
                    FunctionSignature(
                        receiverType: arrayType,
                        parameterTypes: [arrayType, types.intType, types.intType, types.intType],
                        returnType: arrayType,
                        isSuspend: false,
                        valueParameterSymbols: parameterSymbols,
                        valueParameterHasDefaultValues: [false, true, true, true],
                        valueParameterIsVararg: [false, false, false, false],
                        typeParameterSymbols: []
                    ),
                    for: copyIntoSym
                )
            }
        }

        let primitiveArrayFactoryTypes: [(String, String, TypeID)] = [
            ("intArrayOf", "IntArray", types.intType),
            ("longArrayOf", "LongArray", types.longType),
            ("doubleArrayOf", "DoubleArray", types.doubleType),
            ("floatArrayOf", "FloatArray", types.floatType),
            ("booleanArrayOf", "BooleanArray", types.booleanType),
            ("charArrayOf", "CharArray", types.charType),
            ("shortArrayOf", "ShortArray", types.shortType),
            ("ubyteArrayOf", "UByteArray", types.ubyteType),
            ("ushortArrayOf", "UShortArray", types.ushortType),
            ("uintArrayOf", "UIntArray", types.uintType),
            ("ulongArrayOf", "ULongArray", types.ulongType),
        ]
        for (factoryName, arrayName, elementType) in primitiveArrayFactoryTypes {
            guard let primitiveArraySymbol = symbols.lookup(fqName: kotlinPkg + [interner.intern(arrayName)]) else {
                continue
            }
            let returnType = types.make(.classType(ClassType(
                classSymbol: primitiveArraySymbol,
                args: [],
                nullability: .nonNull
            )))
            registerSyntheticArrayFactoryFunction(
                named: factoryName,
                packageFQName: kotlinPkg,
                returnType: returnType,
                valueParameterTypes: [elementType],
                valueParameterIsVararg: [true],
                typeParamNames: [],
                externalLinkName: "kk_array_of",
                symbols: symbols,
                interner: interner
            )
        }
    }

    private func registerSyntheticArrayFactoryFunction(
        named name: String,
        packageFQName: [InternedString],
        returnType: TypeID,
        valueParameterTypes: [TypeID],
        valueParameterIsVararg: [Bool],
        typeParamNames: [String],
        externalLinkName: String,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        let functionName = interner.intern(name)
        let functionFQName = packageFQName + [functionName]
        guard symbols.lookup(fqName: functionFQName) == nil else { return }

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

        var typeParameterSymbols: [SymbolID] = []
        for paramName in typeParamNames {
            let typeParamName = interner.intern(paramName)
            let typeParamSymbol = symbols.define(
                kind: .typeParameter,
                name: typeParamName,
                fqName: functionFQName + [typeParamName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(functionSymbol, for: typeParamSymbol)
            typeParameterSymbols.append(typeParamSymbol)
        }

        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: nil,
                parameterTypes: valueParameterTypes,
                returnType: returnType,
                isSuspend: false,
                valueParameterSymbols: [],
                valueParameterHasDefaultValues: Array(repeating: false, count: valueParameterTypes.count),
                valueParameterIsVararg: valueParameterIsVararg,
                typeParameterSymbols: typeParameterSymbols
            ),
            for: functionSymbol
        )
    }
}
