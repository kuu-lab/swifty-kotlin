
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
        // KSP-657: arrayOf / emptyArray / arrayOfNulls factories are now declared
        // as bundled Kotlin intrinsics in Stdlib/kotlin/ArrayIntrinsics.kt.

        // --- Array extension functions: sliceArray, reversedArray ---
        //
        // KSP-658: generic Array<T>.contentEquals / contentToString / copyOf /
        // copyOfRange are bundled Kotlin source
        // (Stdlib/kotlin/collections/ArrayContentAndCopy.kt); their synthetic
        // stubs were removed so source resolution takes precedence.

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
        // Keep primitive array class shells synthetic for the primitive type
        // system. Their `size` / conversion members are bundled Kotlin source.
        let unsignedPrimitiveArrayNames = [
            "UByteArray",
            "UShortArray",
            "UIntArray",
            "ULongArray",
        ]
        for name in primitiveArrayNames {
            let primName = interner.intern(name)
            let fqName = kotlinPkg + [primName]
            if symbols.lookup(fqName: fqName) == nil {
                _ = symbols.define(
                    kind: .class,
                    name: primName,
                    fqName: fqName,
                    declSite: nil,
                    visibility: .public,
                    flags: [.synthetic]
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
                    // KSP-1515: this is the residual toTypedArray allocation bridge;
                    // the public Array.copyOf overloads are source-backed below.
                    symbols.setExternalLinkName("__kk_array_copyOf", for: toTypedArraySym)

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

        }

        let primitiveArrayFactoryTypes: [(String, String, TypeID)] = [
            ("uintArrayOf", "UIntArray", types.uintType),
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
