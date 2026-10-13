/// Type-parameter shapes and typealiases for the `kotlinx.cinterop` synthetic
/// surface (`CValuesRef`/`CValue`, `CPointerVarOf`, `CFunction`, `BooleanVarOf`,
/// `ByteVarOf`, and the `BooleanVar`/`ByteVar`/`COpaquePointer`/`CArrayPointer`
/// aliases), extracted from `registerSyntheticCInteropStubs`.
extension DataFlowSemaPhase {
    func registerCInteropCValuesShapes(
        cinteropPkg: [InternedString],
        cValuesRefSymbol: SymbolID,
        cValueSymbol: SymbolID,
        cValuesSymbol: SymbolID,
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        cVariableType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        configureSingleTypeParameterNominal(
            ownerSymbol: cValuesRefSymbol,
            fqName: cinteropPkg + [interner.intern("CValuesRef")],
            parameterName: "T",
            supertype: nil,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.insertFlags([.abstractType], for: cValuesRefSymbol)
        if let cValuesRefTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cValuesRefSymbol).first {
            symbols.setTypeParameterUpperBounds([cPointedType], for: cValuesRefTypeParameterSymbol)
            let cValuesRefTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cValuesRefTypeParameterSymbol,
                nullability: .nonNull
            )))
            _ = types.make(.classType(ClassType(
                classSymbol: cValuesRefSymbol,
                args: [.invariant(cValuesRefTypeParameterType)],
                nullability: .nonNull
            )))
            _ = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cValuesRefTypeParameterType)],
                nullability: .nonNull
            )))


        }
        configureSingleTypeParameterNominal(
            ownerSymbol: cValueSymbol,
            fqName: cinteropPkg + [interner.intern("CValue")],
            parameterName: "T",
            supertype: cValuesSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.insertFlags([.abstractType], for: cValueSymbol)
        if let cValueTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cValueSymbol).first {
            symbols.setTypeParameterUpperBounds([cVariableType], for: cValueTypeParameterSymbol)
            let cValueTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cValueTypeParameterSymbol,
                nullability: .nonNull
            )))
            _ = types.make(.classType(ClassType(
                classSymbol: cValueSymbol,
                args: [.invariant(cValueTypeParameterType)],
                nullability: .nonNull
            )))

        }
    }

    func registerCInteropVarOfShapes(
        cinteropPkg: [InternedString],
        cPointerVarOfSymbol: SymbolID,
        cFunctionSymbol: SymbolID,
        booleanVarOfSymbol: SymbolID,
        byteVarOfSymbol: SymbolID,
        cVariableSymbol: SymbolID,
        cVariableTypeSymbol: SymbolID,
        cPrimitiveVarSymbol: SymbolID,
        cPointedSymbol: SymbolID,
        cPointerSymbol: SymbolID,
        nativePtrType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        configureSingleTypeParameterNominal(
            ownerSymbol: cPointerVarOfSymbol,
            fqName: cinteropPkg + [interner.intern("CPointerVarOf")],
            parameterName: "T",
            supertype: cVariableSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let cPointerVarOfTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cPointerVarOfSymbol).first {
            symbols.setParentSymbol(cPointerVarOfSymbol, for: cPointerVarOfTypeParameterSymbol)
            let cPointerStarType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.star],
                nullability: .nonNull
            )))
            symbols.setTypeParameterUpperBounds([cPointerStarType], for: cPointerVarOfTypeParameterSymbol)
            let cPointerVarOfTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cPointerVarOfTypeParameterSymbol,
                nullability: .nonNull
            )))
            _ = types.make(.classType(ClassType(
                classSymbol: cPointerVarOfSymbol,
                args: [.invariant(cPointerVarOfTypeParameterType)],
                nullability: .nonNull
            )))

        }
        let cPointerVarOfCompanionName = interner.intern("Companion")
        let cPointerVarOfCompanionFQName = cinteropPkg + [interner.intern("CPointerVarOf"), cPointerVarOfCompanionName]
        let cPointerVarOfCompanionSymbol: SymbolID
        if let existingCompanion = symbols.companionObjectSymbol(for: cPointerVarOfSymbol) {
            cPointerVarOfCompanionSymbol = existingCompanion
        } else if let existing = symbols.lookup(fqName: cPointerVarOfCompanionFQName),
                  symbols.symbol(existing)?.kind == .object
        {
            cPointerVarOfCompanionSymbol = existing
        } else {
            cPointerVarOfCompanionSymbol = symbols.define(
                kind: .object,
                name: cPointerVarOfCompanionName,
                fqName: cPointerVarOfCompanionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
        }
        symbols.setParentSymbol(cPointerVarOfSymbol, for: cPointerVarOfCompanionSymbol)
        symbols.setCompanionObjectSymbol(cPointerVarOfCompanionSymbol, for: cPointerVarOfSymbol)
        let cPointerVarOfCompanionType = types.make(.classType(ClassType(
            classSymbol: cPointerVarOfCompanionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPointerVarOfCompanionType, for: cPointerVarOfCompanionSymbol)
        symbols.setDirectSupertypes([cVariableTypeSymbol], for: cPointerVarOfCompanionSymbol)
        types.setNominalDirectSupertypes([cVariableTypeSymbol], for: cPointerVarOfCompanionSymbol)

        configureSingleTypeParameterNominal(
            ownerSymbol: cFunctionSymbol,
            fqName: cinteropPkg + [interner.intern("CFunction")],
            parameterName: "T",
            supertype: cPointedSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let cFunctionTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cFunctionSymbol).first {
            symbols.setTypeParameterUpperBounds([types.anyType], for: cFunctionTypeParameterSymbol)
            let cFunctionTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cFunctionTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cFunctionType = types.make(.classType(ClassType(
                classSymbol: cFunctionSymbol,
                args: [.invariant(cFunctionTypeParameterType)],
                nullability: .nonNull
            )))
            registerNativeConcurrentConstructor(
                ownerSymbol: cFunctionSymbol,
                ownerType: cFunctionType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                typeParameterSymbols: [cFunctionTypeParameterSymbol],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )
        }
        configureSingleTypeParameterNominal(
            ownerSymbol: booleanVarOfSymbol,
            fqName: cinteropPkg + [interner.intern("BooleanVarOf")],
            parameterName: "T",
            supertype: cPrimitiveVarSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let booleanVarOfTypeParameterSymbol = types.nominalTypeParameterSymbols(for: booleanVarOfSymbol).first {
            symbols.setTypeParameterUpperBounds([types.booleanType], for: booleanVarOfTypeParameterSymbol)
            let booleanVarOfTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: booleanVarOfTypeParameterSymbol,
                nullability: .nonNull
            )))
            let booleanVarOfType = types.make(.classType(ClassType(
                classSymbol: booleanVarOfSymbol,
                args: [.invariant(booleanVarOfTypeParameterType)],
                nullability: .nonNull
            )))
            registerNativeConcurrentConstructor(
                ownerSymbol: booleanVarOfSymbol,
                ownerType: booleanVarOfType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                typeParameterSymbols: [booleanVarOfTypeParameterSymbol],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )

        }
        configureSingleTypeParameterNominal(
            ownerSymbol: byteVarOfSymbol,
            fqName: cinteropPkg + [interner.intern("ByteVarOf")],
            parameterName: "T",
            supertype: cPrimitiveVarSymbol,
            supertypeIsGeneric: false,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let byteVarOfTypeParameterSymbol = types.nominalTypeParameterSymbols(for: byteVarOfSymbol).first {
            symbols.setTypeParameterUpperBounds([types.byteType], for: byteVarOfTypeParameterSymbol)
            let byteVarOfTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: byteVarOfTypeParameterSymbol,
                nullability: .nonNull
            )))
            let byteVarOfType = types.make(.classType(ClassType(
                classSymbol: byteVarOfSymbol,
                args: [.invariant(byteVarOfTypeParameterType)],
                nullability: .nonNull
            )))
            registerNativeConcurrentConstructor(
                ownerSymbol: byteVarOfSymbol,
                ownerType: byteVarOfType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                typeParameterSymbols: [byteVarOfTypeParameterSymbol],
                classTypeParameterCount: 1,
                symbols: symbols,
                interner: interner
            )

        }
    }

    func registerCInteropPrimitiveTypeAliases(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        booleanVarOfSymbol: SymbolID,
        byteVarOfSymbol: SymbolID,
        cValuesSymbol: SymbolID,
        cPointerSymbol: SymbolID,
        cPointedType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let booleanVarType = types.make(.classType(ClassType(
            classSymbol: booleanVarOfSymbol,
            args: [.invariant(types.booleanType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "BooleanVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: booleanVarType,
            symbols: symbols,
            interner: interner
        )
        let byteVarType = types.make(.classType(ClassType(
            classSymbol: byteVarOfSymbol,
            args: [.invariant(types.byteType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "ByteVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: byteVarType,
            symbols: symbols,
            interner: interner
        )
        _ = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))

        // NOTE: ByteArray.toKString() with no explicit args is covered by the
        // ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence) overload
        // registered above (all three parameters have default values).
        // Registering a separate zero-parameter overload here would cause ambiguity
        // when calling bytes.toKString() with no arguments.
        let byteArrayReceiverType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        let byteArrayToCValuesReturnType = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "toCValues",
            packageFQName: cinteropPkg,
            receiverType: byteArrayReceiverType,
            parameters: [],
            returnType: byteArrayToCValuesReturnType,
            externalLinkName: "kk_byteArray_toCValues",
            symbols: symbols,
            interner: interner
        )

        let cOpaquePointerUnderlyingType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.out(cPointedType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "COpaquePointer",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: cOpaquePointerUnderlyingType,
            symbols: symbols,
            interner: interner
        )
        return cOpaquePointerUnderlyingType
    }

    func registerCInteropPointerAliases(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        cOpaquePointerUnderlyingType: TypeID,
        cPointerVarOfSymbol: SymbolID,
        cPointerSymbol: SymbolID,
        cPointerVarSymbol: SymbolID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let cOpaquePointerVarUnderlyingType = types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(cOpaquePointerUnderlyingType)],
            nullability: .nonNull
        )))
        registerSyntheticCInteropTypeAlias(
            named: "COpaquePointerVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            underlyingType: cOpaquePointerVarUnderlyingType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCInteropSingleTypeParameterTypeAlias(
            named: "CArrayPointer",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            parameterName: "T",
            targetSymbol: cPointerSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCInteropSingleTypeParameterTypeAlias(
            named: "CArrayPointerVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            parameterName: "T",
            targetSymbol: cPointerVarSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}
