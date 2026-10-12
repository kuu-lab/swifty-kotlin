extension DataFlowSemaPhase {
    func registerSyntheticCInteropStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let cinteropPkg = ensurePackage(
            path: ["kotlinx", "cinterop"],
            symbols: symbols,
            interner: interner
        )
        let cinteropPkgSymbol = symbols.lookup(fqName: cinteropPkg)

        let experimentalForeignApiSymbol = ensureAnnotationClassSymbol(
            named: "ExperimentalForeignApi",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: experimentalForeignApiSymbol)
        }
        appendStandardAnnotationMetadata(
            to: experimentalForeignApiSymbol,
            targets: [
                "AnnotationTarget.CLASS",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.FIELD",
                "AnnotationTarget.LOCAL_VARIABLE",
                "AnnotationTarget.VALUE_PARAMETER",
                "AnnotationTarget.CONSTRUCTOR",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY_GETTER",
                "AnnotationTarget.PROPERTY_SETTER",
                "AnnotationTarget.TYPEALIAS",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )

        let betaInteropApiSymbol = ensureAnnotationClassSymbol(
            named: "BetaInteropApi",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: betaInteropApiSymbol)
        }
        appendStandardAnnotationMetadata(
            to: betaInteropApiSymbol,
            targets: [
                "AnnotationTarget.TYPEALIAS",
                "AnnotationTarget.FUNCTION",
                "AnnotationTarget.PROPERTY",
                "AnnotationTarget.ANNOTATION_CLASS",
                "AnnotationTarget.CLASS",
            ],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        appendMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.RequiresOptIn",
                    arguments: ["level=RequiresOptIn.Level.WARNING"]
                ),
            ],
            to: betaInteropApiSymbol,
            symbols: symbols
        )

        let nativePointedSymbol = ensureClassSymbol(
            named: "NativePointed",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointedSymbol = ensureClassSymbol(
            named: "CPointed",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cVariableSymbol = ensureClassSymbol(
            named: "CVariable",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cVariableTypeSymbol = ensureClassSymbol(
            named: "Type",
            in: cinteropPkg + [interner.intern("CVariable")],
            symbols: symbols,
            interner: interner
        )
        let cPrimitiveVarSymbol = ensureClassSymbol(
            named: "CPrimitiveVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPrimitiveVarTypeSymbol = ensureClassSymbol(
            named: "Type",
            in: cinteropPkg + [interner.intern("CPrimitiveVar")],
            symbols: symbols,
            interner: interner
        )
        let cStructVarSymbol = ensureClassSymbol(
            named: "CStructVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cStructVarTypeSymbol = ensureClassSymbol(
            named: "Type",
            in: cinteropPkg + [interner.intern("CStructVar")],
            symbols: symbols,
            interner: interner
        )
        let cEnumSymbol = ensureInterfaceSymbol(
            named: "CEnum",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cEnumVarSymbol = ensureClassSymbol(
            named: "CEnumVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cFunctionSymbol = ensureClassSymbol(
            named: "CFunction",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cOpaqueSymbol = ensureClassSymbol(
            named: "COpaque",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let nativePtrSymbol = ensureClassSymbol(
            named: "NativePtr",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let nativePlacementSymbol = ensureInterfaceSymbol(
            named: "NativePlacement",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let nativeFreeablePlacementSymbol = ensureInterfaceSymbol(
            named: "NativeFreeablePlacement",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let deferScopeSymbol = ensureClassSymbol(
            named: "DeferScope",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let autofreeScopeSymbol = ensureClassSymbol(
            named: "AutofreeScope",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let arenaBaseSymbol = ensureClassSymbol(
            named: "ArenaBase",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let arenaSymbol = ensureClassSymbol(
            named: "Arena",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let memScopeSymbol = ensureClassSymbol(
            named: "MemScope",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cValuesRefSymbol = ensureClassSymbol(
            named: "CValuesRef",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cValueSymbol = ensureClassSymbol(
            named: "CValue",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cValuesSymbol = ensureClassSymbol(
            named: "CValues",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let pinnedSymbol = ensureClassSymbol(
            named: "Pinned",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointerSymbol = ensureClassSymbol(
            named: "CPointer",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointerVarSymbol = ensureSyntheticCInteropTypeAliasSymbol(
            named: "CPointerVar",
            in: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            symbols: symbols,
            interner: interner
        ) ?? ensureClassSymbol(
            named: "CPointerVar",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let cPointerVarOfSymbol = ensureClassSymbol(
            named: "CPointerVarOf",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let booleanVarOfSymbol = ensureClassSymbol(
            named: "BooleanVarOf",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let byteVarOfSymbol = ensureClassSymbol(
            named: "ByteVarOf",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        let vector128Symbol = ensureClassSymbol(
            named: "Vector128",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )

        for symbol in [
            nativePointedSymbol,
            cPointedSymbol,
            cVariableSymbol,
            cPrimitiveVarSymbol,
            cStructVarSymbol,
            cEnumSymbol,
            cEnumVarSymbol,
            cFunctionSymbol,
            cOpaqueSymbol,
            nativePtrSymbol,
            nativePlacementSymbol,
            nativeFreeablePlacementSymbol,
            deferScopeSymbol,
            autofreeScopeSymbol,
            arenaBaseSymbol,
            arenaSymbol,
            memScopeSymbol,
            cValuesRefSymbol,
            cValueSymbol,
            cValuesSymbol,
            pinnedSymbol,
            cPointerSymbol,
            cPointerVarSymbol,
            cPointerVarOfSymbol,
            booleanVarOfSymbol,
            byteVarOfSymbol,
            vector128Symbol,
        ] {
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: symbol)
            }
        }
        symbols.setParentSymbol(cVariableSymbol, for: cVariableTypeSymbol)
        symbols.setParentSymbol(cPrimitiveVarSymbol, for: cPrimitiveVarTypeSymbol)
        symbols.setParentSymbol(cStructVarSymbol, for: cStructVarTypeSymbol)

        let nativePointedType = types.make(.classType(ClassType(
            classSymbol: nativePointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePointedType, for: nativePointedSymbol)

        let cPointedType = types.make(.classType(ClassType(
            classSymbol: cPointedSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPointedType, for: cPointedSymbol)
        symbols.insertFlags([.abstractType], for: cPointedSymbol)
        symbols.setDirectSupertypes([nativePointedSymbol], for: cPointedSymbol)
        types.setNominalDirectSupertypes([nativePointedSymbol], for: cPointedSymbol)

        let cVariableType = types.make(.classType(ClassType(
            classSymbol: cVariableSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cVariableType, for: cVariableSymbol)
        symbols.insertFlags([.abstractType], for: cVariableSymbol)
        symbols.setDirectSupertypes([cPointedSymbol], for: cVariableSymbol)
        types.setNominalDirectSupertypes([cPointedSymbol], for: cVariableSymbol)

        let cVariableTypeClassType = types.make(.classType(ClassType(
            classSymbol: cVariableTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cVariableTypeClassType, for: cVariableTypeSymbol)
        symbols.insertFlags([.openType], for: cVariableTypeSymbol)
        appendMetadataAnnotations(
            [
                MetadataAnnotationRecord(
                    annotationFQName: "kotlin.Deprecated",
                    arguments: ["message = \"Use sizeOf<T>() or alignOf<T>() instead.\""]
                ),
            ],
            to: cVariableTypeSymbol,
            symbols: symbols
        )

        let cPrimitiveVarType = types.make(.classType(ClassType(
            classSymbol: cPrimitiveVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPrimitiveVarType, for: cPrimitiveVarSymbol)
        symbols.insertFlags([.sealedType, .abstractType, .openType], for: cPrimitiveVarSymbol)
        symbols.setDirectSupertypes([cVariableSymbol], for: cPrimitiveVarSymbol)
        types.setNominalDirectSupertypes([cVariableSymbol], for: cPrimitiveVarSymbol)

        let cPrimitiveVarTypeClassType = types.make(.classType(ClassType(
            classSymbol: cPrimitiveVarTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cPrimitiveVarTypeClassType, for: cPrimitiveVarTypeSymbol)
        symbols.insertFlags([.openType], for: cPrimitiveVarTypeSymbol)
        symbols.setDirectSupertypes([cVariableTypeSymbol], for: cPrimitiveVarTypeSymbol)
        types.setNominalDirectSupertypes([cVariableTypeSymbol], for: cPrimitiveVarTypeSymbol)

        let cStructVarType = types.make(.classType(ClassType(
            classSymbol: cStructVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cStructVarType, for: cStructVarSymbol)
        symbols.insertFlags([.abstractType, .openType], for: cStructVarSymbol)
        symbols.setDirectSupertypes([cVariableSymbol], for: cStructVarSymbol)
        types.setNominalDirectSupertypes([cVariableSymbol], for: cStructVarSymbol)

        let cStructVarTypeClassType = types.make(.classType(ClassType(
            classSymbol: cStructVarTypeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cStructVarTypeClassType, for: cStructVarTypeSymbol)
        symbols.insertFlags([.openType], for: cStructVarTypeSymbol)
        symbols.setDirectSupertypes([cVariableTypeSymbol], for: cStructVarTypeSymbol)
        types.setNominalDirectSupertypes([cVariableTypeSymbol], for: cStructVarTypeSymbol)

        let cEnumType = types.make(.classType(ClassType(
            classSymbol: cEnumSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cEnumType, for: cEnumSymbol)
        appendMetadataAnnotations(deprecatedCEnumAnnotations(), to: cEnumSymbol, symbols: symbols)


        let cEnumVarType = types.make(.classType(ClassType(
            classSymbol: cEnumVarSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cEnumVarType, for: cEnumVarSymbol)
        symbols.insertFlags([.abstractType], for: cEnumVarSymbol)
        symbols.setDirectSupertypes([cPrimitiveVarSymbol], for: cEnumVarSymbol)
        types.setNominalDirectSupertypes([cPrimitiveVarSymbol], for: cEnumVarSymbol)

        let cOpaqueType = types.make(.classType(ClassType(
            classSymbol: cOpaqueSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cOpaqueType, for: cOpaqueSymbol)
        symbols.insertFlags([.abstractType], for: cOpaqueSymbol)
        symbols.setDirectSupertypes([cPointedSymbol], for: cOpaqueSymbol)
        types.setNominalDirectSupertypes([cPointedSymbol], for: cOpaqueSymbol)

        let nativePtrType = types.make(.classType(ClassType(
            classSymbol: nativePtrSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePtrType, for: nativePtrSymbol)

        let vector128Type = types.make(.classType(ClassType(
            classSymbol: vector128Symbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(vector128Type, for: vector128Symbol)













        let nativePlacementType = types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePlacementType, for: nativePlacementSymbol)


        let nativePlacementAllocName = interner.intern("alloc")
        let nativePlacementAllocFQName = cinteropPkg + [nativePlacementAllocName]
        let nativePlacementAllocTypeParameterName = interner.intern("T")
        let nativePlacementAllocTypeParameterFQName = nativePlacementAllocFQName + [nativePlacementAllocTypeParameterName]
        let nativePlacementAllocTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: nativePlacementAllocTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: nativePlacementAllocTypeParameterName,
                fqName: nativePlacementAllocTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: nativePlacementAllocTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cVariableType], for: nativePlacementAllocTypeParameterSymbol)
        _ = types.make(.typeParam(TypeParamType(
            symbol: nativePlacementAllocTypeParameterSymbol,
            nullability: .nonNull
        )))



        let nativePlacementPlaceName = interner.intern("place")
        let nativePlacementPlaceFQName = cinteropPkg + [nativePlacementPlaceName]
        let nativePlacementPlaceTypeParameterName = interner.intern("T")
        let nativePlacementPlaceTypeParameterFQName = nativePlacementPlaceFQName + [nativePlacementPlaceTypeParameterName]
        let nativePlacementPlaceTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: nativePlacementPlaceTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: nativePlacementPlaceTypeParameterName,
                fqName: nativePlacementPlaceTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.insertFlags([.synthetic], for: nativePlacementPlaceTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cVariableType], for: nativePlacementPlaceTypeParameterSymbol)
        let nativePlacementPlaceTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: nativePlacementPlaceTypeParameterSymbol,
            nullability: .nonNull
        )))
        _ = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(nativePlacementPlaceTypeParameterType)],
            nullability: .nonNull
        )))
        _ = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(nativePlacementPlaceTypeParameterType)],
            nullability: .nonNull
        )))


        let nativeFreeablePlacementType = types.make(.classType(ClassType(
            classSymbol: nativeFreeablePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativeFreeablePlacementType, for: nativeFreeablePlacementSymbol)
        symbols.setDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)
        types.setNominalDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)



        let deferScopeType = types.make(.classType(ClassType(
            classSymbol: deferScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(deferScopeType, for: deferScopeSymbol)
        symbols.insertFlags([.openType], for: deferScopeSymbol)

        _ = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))


        let autofreeScopeType = types.make(.classType(ClassType(
            classSymbol: autofreeScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(autofreeScopeType, for: autofreeScopeSymbol)
        symbols.insertFlags([.abstractType], for: autofreeScopeSymbol)
        symbols.setDirectSupertypes([deferScopeSymbol, nativePlacementSymbol], for: autofreeScopeSymbol)
        types.setNominalDirectSupertypes([deferScopeSymbol, nativePlacementSymbol], for: autofreeScopeSymbol)

        let arenaBaseType = types.make(.classType(ClassType(
            classSymbol: arenaBaseSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(arenaBaseType, for: arenaBaseSymbol)
        symbols.insertFlags([.openType], for: arenaBaseSymbol)
        symbols.setDirectSupertypes([autofreeScopeSymbol], for: arenaBaseSymbol)
        types.setNominalDirectSupertypes([autofreeScopeSymbol], for: arenaBaseSymbol)

        let arenaType = types.make(.classType(ClassType(
            classSymbol: arenaSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(arenaType, for: arenaSymbol)
        symbols.setDirectSupertypes([arenaBaseSymbol], for: arenaSymbol)
        types.setNominalDirectSupertypes([arenaBaseSymbol], for: arenaSymbol)

        let memScopeType = types.make(.classType(ClassType(
            classSymbol: memScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(memScopeType, for: memScopeSymbol)
        symbols.setDirectSupertypes([arenaBaseSymbol], for: memScopeSymbol)
        types.setNominalDirectSupertypes([arenaBaseSymbol], for: memScopeSymbol)

        registerCInteropMemScopedStub(
            cinteropPkg: cinteropPkg,
            memScopeType: memScopeType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropCValuesShapes(
            cinteropPkg: cinteropPkg,
            cValuesRefSymbol: cValuesRefSymbol,
            cValueSymbol: cValueSymbol,
            cValuesSymbol: cValuesSymbol,
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            cVariableType: cVariableType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropPointerConversionStubs(
            cinteropPkg: cinteropPkg,
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropVarOfShapes(
            cinteropPkg: cinteropPkg,
            cPointerVarOfSymbol: cPointerVarOfSymbol,
            cFunctionSymbol: cFunctionSymbol,
            booleanVarOfSymbol: booleanVarOfSymbol,
            byteVarOfSymbol: byteVarOfSymbol,
            cVariableSymbol: cVariableSymbol,
            cVariableTypeSymbol: cVariableTypeSymbol,
            cPrimitiveVarSymbol: cPrimitiveVarSymbol,
            cPointedSymbol: cPointedSymbol,
            cPointerSymbol: cPointerSymbol,
            nativePtrType: nativePtrType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        let cOpaquePointerUnderlyingType = registerCInteropPrimitiveTypeAliases(
            cinteropPkg: cinteropPkg,
            cinteropPkgSymbol: cinteropPkgSymbol,
            booleanVarOfSymbol: booleanVarOfSymbol,
            byteVarOfSymbol: byteVarOfSymbol,
            cValuesSymbol: cValuesSymbol,
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropPinnedStubs(
            cinteropPkg: cinteropPkg,
            pinnedSymbol: pinnedSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropUsePinnedStub(
            cinteropPkg: cinteropPkg,
            cinteropPkgSymbol: cinteropPkgSymbol,
            pinnedSymbol: pinnedSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropPointerAliases(
            cinteropPkg: cinteropPkg,
            cinteropPkgSymbol: cinteropPkgSymbol,
            cOpaquePointerUnderlyingType: cOpaquePointerUnderlyingType,
            cPointerVarOfSymbol: cPointerVarOfSymbol,
            cPointerSymbol: cPointerSymbol,
            cPointerVarSymbol: cPointerVarSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropPrimitiveVarStubs(
            cinteropPkg: cinteropPkg,
            cinteropPkgSymbol: cinteropPkgSymbol,
            cPrimitiveVarSymbol: cPrimitiveVarSymbol,
            cPointerSymbol: cPointerSymbol,
            nativePtrType: nativePtrType,
            booleanVarOfSymbol: booleanVarOfSymbol,
            byteVarOfSymbol: byteVarOfSymbol,
            cPointerVarOfSymbol: cPointerVarOfSymbol,
            cStructVarSymbol: cStructVarSymbol,
            cEnumVarSymbol: cEnumVarSymbol,
            cVariableSymbol: cVariableSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropUnsignedVarStubs(
            cinteropPkg: cinteropPkg,
            cValuesSymbol: cValuesSymbol,
            cPointerSymbol: cPointerSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        // MARK: - KUU-1375: CPointer members, placement, native heap, strings

        let cPointerStarType = registerCInteropCPointerMembers(
            cinteropPkg: cinteropPkg,
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            byteVarOfSymbol: byteVarOfSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropPlacementScopeMembers(
            cinteropPkg: cinteropPkg,
            cinteropPkgSymbol: cinteropPkgSymbol,
            cVariableType: cVariableType,
            cPointerSymbol: cPointerSymbol,
            cPointerStarType: cPointerStarType,
            nativePlacementSymbol: nativePlacementSymbol,
            nativePlacementType: nativePlacementType,
            nativeFreeablePlacementSymbol: nativeFreeablePlacementSymbol,
            nativeFreeablePlacementType: nativeFreeablePlacementType,
            deferScopeSymbol: deferScopeSymbol,
            deferScopeType: deferScopeType,
            autofreeScopeSymbol: autofreeScopeSymbol,
            autofreeScopeType: autofreeScopeType,
            arenaSymbol: arenaSymbol,
            arenaType: arenaType,
            memScopeSymbol: memScopeSymbol,
            memScopeType: memScopeType,
            nativePtrType: nativePtrType,
            symbols: symbols,
            types: types,
            interner: interner
        )

        registerCInteropPointerUtilityFunctions(
            cinteropPkg: cinteropPkg,
            nativePtrSymbol: nativePtrSymbol,
            nativePtrType: nativePtrType,
            cVariableType: cVariableType,
            cPointedType: cPointedType,
            cPointerSymbol: cPointerSymbol,
            byteVarOfSymbol: byteVarOfSymbol,
            memScopeSymbol: memScopeSymbol,
            cValuesSymbol: cValuesSymbol,
            nativePlacementType: nativePlacementType,
            symbols: symbols,
            types: types,
            interner: interner
        )
    }
}