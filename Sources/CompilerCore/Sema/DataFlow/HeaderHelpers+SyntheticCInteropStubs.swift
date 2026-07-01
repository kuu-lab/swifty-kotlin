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
        let stableRefSymbol = ensureClassSymbol(
            named: "StableRef",
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
            stableRefSymbol,
            pinnedSymbol,
            cPointerSymbol,
            cPointerVarSymbol,
            cPointerVarOfSymbol,
            booleanVarOfSymbol,
            byteVarOfSymbol,
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
        registerSyntheticNativeBitSetProperty(
            named: "value",
            ownerSymbol: cEnumSymbol,
            propertyType: types.anyType,
            flags: [.synthetic, .abstractType],
            symbols: symbols,
            interner: interner
        )

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

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cPointedSymbol,
            ownerType: cPointedType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "rawPtr",
            ownerSymbol: cPointedSymbol,
            propertyType: nativePtrType,
            flags: [.synthetic, .mutable],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cVariableSymbol,
            ownerType: cVariableType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cVariableTypeSymbol,
            ownerType: cVariableTypeClassType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "size",
            ownerSymbol: cVariableTypeSymbol,
            propertyType: types.longType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "align",
            ownerSymbol: cVariableTypeSymbol,
            propertyType: types.intType,
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cPrimitiveVarSymbol,
            ownerType: cPrimitiveVarType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            visibility: .protected,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cPrimitiveVarTypeSymbol,
            ownerType: cPrimitiveVarTypeClassType,
            parameters: [(name: "size", type: types.intType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cStructVarSymbol,
            ownerType: cStructVarType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cStructVarTypeSymbol,
            ownerType: cStructVarTypeClassType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            defaultValues: [false, false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cEnumVarSymbol,
            ownerType: cEnumVarType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cOpaqueSymbol,
            ownerType: cOpaqueType,
            parameters: [(name: "rawPtr", type: nativePtrType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )

        let nativePlacementType = types.make(.classType(ClassType(
            classSymbol: nativePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativePlacementType, for: nativePlacementSymbol)
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: nativePlacementSymbol,
            receiverType: nativePlacementType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .abstractType],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: nativePlacementSymbol,
            receiverType: nativePlacementType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )
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
        let nativePlacementAllocTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: nativePlacementAllocTypeParameterSymbol,
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "alloc",
            packageFQName: cinteropPkg,
            receiverType: nativePlacementType,
            parameters: [],
            returnType: nativePlacementAllocTypeParameterType,
            typeParameterSymbols: [nativePlacementAllocTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativePlacementAllocArrayFunction(
            lengthType: types.longType,
            typeParameterDiscriminator: "$lengthLong",
            cVariableType: cVariableType,
            cPointerSymbol: cPointerSymbol,
            nativePlacementType: nativePlacementType,
            packageFQName: cinteropPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativePlacementAllocArrayFunction(
            lengthType: types.intType,
            typeParameterDiscriminator: "$lengthInt",
            cVariableType: cVariableType,
            cPointerSymbol: cPointerSymbol,
            nativePlacementType: nativePlacementType,
            packageFQName: cinteropPkg,
            symbols: symbols,
            types: types,
            interner: interner
        )
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
        let cValuesOfPlaceTypeParameterType = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(nativePlacementPlaceTypeParameterType)],
            nullability: .nonNull
        )))
        let cPointerOfPlaceTypeParameterType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(nativePlacementPlaceTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "place",
            packageFQName: cinteropPkg,
            receiverType: nativePlacementType,
            parameters: [(name: "value", type: cValuesOfPlaceTypeParameterType)],
            returnType: cPointerOfPlaceTypeParameterType,
            typeParameterSymbols: [nativePlacementPlaceTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cVariableType]],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )

        let nativeFreeablePlacementType = types.make(.classType(ClassType(
            classSymbol: nativeFreeablePlacementSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(nativeFreeablePlacementType, for: nativeFreeablePlacementSymbol)
        symbols.setDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)
        types.setNominalDirectSupertypes([nativePlacementSymbol], for: nativeFreeablePlacementSymbol)

        registerSyntheticNativeTopLevelProperty(
            named: "nativeHeap",
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            propertyType: nativeFreeablePlacementType,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "free",
            packageFQName: cinteropPkg,
            receiverType: nativeFreeablePlacementType,
            parameters: [(name: "pointed", type: nativePointedType)],
            returnType: types.unitType,
            symbols: symbols,
            interner: interner
        )

        let deferScopeType = types.make(.classType(ClassType(
            classSymbol: deferScopeSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(deferScopeType, for: deferScopeSymbol)
        symbols.insertFlags([.openType], for: deferScopeSymbol)
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: deferScopeSymbol,
            ownerType: deferScopeType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        let deferBlockType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType
        )))
        registerSyntheticNativeBitSetMemberFunction(
            named: "defer",
            ownerSymbol: deferScopeSymbol,
            receiverType: deferScopeType,
            parameters: [(name: "block", type: deferBlockType)],
            returnType: types.unitType,
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )

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

        // inline fun <R> memScoped(block: MemScope.() -> R): R
        let memScopedName = interner.intern("memScoped")
        let memScopedFQName = cinteropPkg + [memScopedName]
        if symbols.lookupAll(fqName: memScopedFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil && sig.parameterTypes.count == 1 && sig.typeParameterSymbols.count == 1
        }) {
            // already registered
        } else {
            let memScopedRName = interner.intern("R")
            let memScopedRFQName = memScopedFQName + [memScopedRName]
            let memScopedRSymbol = symbols.define(
                kind: .typeParameter,
                name: memScopedRName,
                fqName: memScopedRFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
            let memScopedRType = types.make(.typeParam(TypeParamType(
                symbol: memScopedRSymbol,
                nullability: .nonNull
            )))
            let memScopedBlockType = types.make(.functionType(FunctionType(
                receiver: memScopeType,
                params: [],
                returnType: memScopedRType,
                isSuspend: false,
                nullability: .nonNull
            )))
            let memScopedBlockName = interner.intern("block")
            let memScopedBlockSymbol = symbols.define(
                kind: .valueParameter,
                name: memScopedBlockName,
                fqName: memScopedFQName + [memScopedBlockName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
            let memScopedSymbolID = symbols.define(
                kind: .function,
                name: memScopedName,
                fqName: memScopedFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .inlineFunction]
            )
            if let packageSymbol = symbols.lookup(fqName: cinteropPkg) {
                symbols.setParentSymbol(packageSymbol, for: memScopedSymbolID)
            }
            symbols.setParentSymbol(memScopedSymbolID, for: memScopedRSymbol)
            symbols.setParentSymbol(memScopedSymbolID, for: memScopedBlockSymbol)
            symbols.setPropertyType(memScopedBlockType, for: memScopedBlockSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [memScopedBlockType],
                    returnType: memScopedRType,
                    isSuspend: false,
                    valueParameterSymbols: [memScopedBlockSymbol],
                    valueParameterHasDefaultValues: [false],
                    valueParameterIsVararg: [false],
                    typeParameterSymbols: [memScopedRSymbol],
                    typeParameterUpperBoundsList: [[]],
                    classTypeParameterCount: 0
                ),
                for: memScopedSymbolID
            )
        }

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: arenaBaseSymbol,
            ownerType: arenaBaseType,
            parameters: [(name: "parent", type: nativeFreeablePlacementType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaBaseSymbol,
            receiverType: arenaBaseType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaBaseSymbol,
            receiverType: arenaBaseType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: arenaSymbol,
            ownerType: arenaType,
            parameters: [(name: "parent", type: nativeFreeablePlacementType)],
            defaultValues: [true],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaSymbol,
            receiverType: arenaType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: arenaSymbol,
            receiverType: arenaType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )

        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: autofreeScopeSymbol,
            ownerType: autofreeScopeType,
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: autofreeScopeSymbol,
            receiverType: autofreeScopeType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .abstractType, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "alloc",
            ownerSymbol: autofreeScopeSymbol,
            receiverType: autofreeScopeType,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePointedType,
            flags: [.synthetic, .openType],
            symbols: symbols,
            interner: interner
        )

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
            let cValuesRefType = types.make(.classType(ClassType(
                classSymbol: cValuesRefSymbol,
                args: [.invariant(cValuesRefTypeParameterType)],
                nullability: .nonNull
            )))
            let cPointerToCValuesRefTypeParameterType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cValuesRefTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cValuesRefSymbol,
                ownerType: cValuesRefType,
                parameters: [],
                defaultValues: [],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetMemberFunction(
                named: "getPointer",
                ownerSymbol: cValuesRefSymbol,
                receiverType: cValuesRefType,
                parameters: [(name: "scope", type: autofreeScopeType)],
                returnType: cPointerToCValuesRefTypeParameterType,
                typeParameterSymbols: [cValuesRefTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .abstractType],
                symbols: symbols,
                interner: interner
            )
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
            let cValueType = types.make(.classType(ClassType(
                classSymbol: cValueSymbol,
                args: [.invariant(cValueTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cValueSymbol,
                ownerType: cValueType,
                parameters: [],
                defaultValues: [],
                symbols: symbols,
                interner: interner
            )
            // CValue<T>.write(location: T) — STDLIB-CINTEROP-FN-045
            registerSyntheticNativeBitSetMemberFunction(
                named: "write",
                ownerSymbol: cValueSymbol,
                receiverType: cValueType,
                parameters: [(name: "location", type: cValueTypeParameterType)],
                returnType: types.unitType,
                typeParameterSymbols: [cValueTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cVariableType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .abstractType],
                symbols: symbols,
                interner: interner
            )
        }
        configureSingleTypeParameterNominal(
            ownerSymbol: cValuesSymbol,
            fqName: cinteropPkg + [interner.intern("CValues")],
            parameterName: "T",
            supertype: cValuesRefSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        symbols.insertFlags([.abstractType], for: cValuesSymbol)
        if let cValuesTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cValuesSymbol).first {
            symbols.setTypeParameterUpperBounds([cVariableType], for: cValuesTypeParameterSymbol)
            let cValuesTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cValuesTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cValuesType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(cValuesTypeParameterType)],
                nullability: .nonNull
            )))
            let cPointerToCValuesTypeParameterType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cValuesTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cValuesSymbol,
                ownerType: cValuesType,
                parameters: [],
                defaultValues: [],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetProperty(
                named: "align",
                ownerSymbol: cValuesSymbol,
                propertyType: types.intType,
                flags: [.synthetic, .abstractType],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetProperty(
                named: "size",
                ownerSymbol: cValuesSymbol,
                propertyType: types.intType,
                flags: [.synthetic, .abstractType],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetMemberFunction(
                named: "getPointer",
                ownerSymbol: cValuesSymbol,
                receiverType: cValuesType,
                parameters: [(name: "scope", type: autofreeScopeType)],
                returnType: cPointerToCValuesTypeParameterType,
                typeParameterSymbols: [cValuesTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cVariableType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .openType, .overrideMember],
                symbols: symbols,
                interner: interner
            )
            registerSyntheticNativeBitSetMemberFunction(
                named: "place",
                ownerSymbol: cValuesSymbol,
                receiverType: cValuesType,
                parameters: [(name: "placement", type: cPointerToCValuesTypeParameterType)],
                returnType: cPointerToCValuesTypeParameterType,
                typeParameterSymbols: [cValuesTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cVariableType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .abstractType],
                annotations: [MetadataAnnotationRecord(annotationFQName: "kotlin.IgnorableReturnValue")],
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticCPointedReadFunction(
            named: "readValue",
            ownerSymbol: cPointedSymbol,
            ownerType: cPointedType,
            typeParameterUpperBound: cVariableType,
            returnClassSymbol: cValueSymbol,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCPointedReadFunction(
            named: "readValues",
            ownerSymbol: cPointedSymbol,
            ownerType: cPointedType,
            typeParameterUpperBound: cVariableType,
            returnClassSymbol: cValuesSymbol,
            parameters: [
                (name: "size", type: types.intType),
                (name: "align", type: types.intType),
            ],
            symbols: symbols,
            types: types,
            interner: interner
        )
        configureSingleTypeParameterNominal(
            ownerSymbol: cPointerSymbol,
            fqName: cinteropPkg + [interner.intern("CPointer")],
            parameterName: "T",
            supertype: cValuesRefSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        if let cPointerTypeParameterSymbol = types.nominalTypeParameterSymbols(for: cPointerSymbol).first {
            symbols.setTypeParameterUpperBounds([cPointedType], for: cPointerTypeParameterSymbol)
            let cPointerTypeParameterType = types.make(.typeParam(TypeParamType(
                symbol: cPointerTypeParameterSymbol,
                nullability: .nonNull
            )))
            let cPointerType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(cPointerTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetMemberFunction(
                named: "getPointer",
                ownerSymbol: cPointerSymbol,
                receiverType: cPointerType,
                parameters: [(name: "scope", type: autofreeScopeType)],
                returnType: cPointerType,
                typeParameterSymbols: [cPointerTypeParameterSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                classTypeParameterCount: 1,
                flags: [.synthetic, .openType, .overrideMember],
                symbols: symbols,
                interner: interner
            )
        }
        let cPointerPlusOverloadUpperBounds = [
            types.make(.classType(ClassType(
                classSymbol: byteVarOfSymbol,
                args: [.star],
                nullability: .nonNull
            ))),
            types.make(.classType(ClassType(
                classSymbol: cPointerVarOfSymbol,
                args: [.star],
                nullability: .nonNull
            ))),
        ]
        for (upperBoundIndex, upperBound) in cPointerPlusOverloadUpperBounds.enumerated() {
            registerSyntheticCPointerPlusFunction(
                indexType: types.intType,
                typeParameterDiscriminator: "$upper\(upperBoundIndex)$indexInt",
                typeParameterUpperBound: upperBound,
                cPointerSymbol: cPointerSymbol,
                packageFQName: cinteropPkg,
                symbols: symbols,
                types: types,
                interner: interner
            )
            registerSyntheticCPointerPlusFunction(
                indexType: types.longType,
                typeParameterDiscriminator: "$upper\(upperBoundIndex)$indexLong",
                typeParameterUpperBound: upperBound,
                cPointerSymbol: cPointerSymbol,
                packageFQName: cinteropPkg,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }
        registerSyntheticCPointerPointedProperty(
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        // operator fun <T : CPointed> CPointer<T>.get(index: Int): T
        registerSyntheticCPointerGetFunction(
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        // operator fun <T : CPointed> CPointer<T>.set(index: Int, value: T): Unit
        registerSyntheticCPointerSetFunction(
            cPointerSymbol: cPointerSymbol,
            cPointedType: cPointedType,
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeBitSetProperty(
            named: "rawValue",
            ownerSymbol: cPointerSymbol,
            propertyType: nativePtrType,
            symbols: symbols,
            interner: interner
        )
        // inline fun <reified T : CPointed> CPointer<*>.reinterpret(): CPointer<T>
        let reinterpretStarReceiverType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let reinterpretFunctionName = interner.intern("reinterpret")
        let reinterpretFunctionFQName = cinteropPkg + [reinterpretFunctionName]
        let reinterpretTypeParameterName = interner.intern("T")
        let reinterpretTypeParameterFQName = reinterpretFunctionFQName + [reinterpretTypeParameterName]
        let reinterpretTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: reinterpretTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: reinterpretTypeParameterName,
                fqName: reinterpretTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: reinterpretTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cPointedType], for: reinterpretTypeParameterSymbol)
        let reinterpretTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: reinterpretTypeParameterSymbol,
            nullability: .nonNull
        )))
        let reinterpretReturnType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(reinterpretTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "reinterpret",
            packageFQName: cinteropPkg,
            receiverType: reinterpretStarReceiverType,
            parameters: [],
            returnType: reinterpretReturnType,
            typeParameterSymbols: [reinterpretTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        // inline fun <T : CPointed> CPointer<T>?.toLong(): Long
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
        // inline operator fun <T : CPointed> CPointer<T>?.plus(index: Long): CPointer<T>?
        let plusFunctionName = interner.intern("plus")
        let plusFunctionFQName = cinteropPkg + [plusFunctionName]
        let plusTypeParameterName = interner.intern("T")
        let plusTypeParameterFQName = plusFunctionFQName + [plusTypeParameterName]
        let plusTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: plusTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: plusTypeParameterName,
                fqName: plusTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.insertFlags([.synthetic], for: plusTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cPointedType], for: plusTypeParameterSymbol)
        let plusTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: plusTypeParameterSymbol,
            nullability: .nonNull
        )))
        let plusNullableCPointerType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(plusTypeParameterType)],
            nullability: .nullable
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "plus",
            packageFQName: cinteropPkg,
            receiverType: plusNullableCPointerType,
            parameters: [(name: "index", type: types.longType)],
            returnType: plusNullableCPointerType,
            typeParameterSymbols: [plusTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            flags: [.synthetic, .inlineFunction, .operatorFunction],
            symbols: symbols,
            interner: interner
        )
        // inline fun <reified T : Any> unwrapKotlinObjectHolder(holder: COpaquePointer?): T
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
        let unwrapHolderTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: unwrapHolderTypeParameterSymbol,
            nullability: .nonNull
        )))
        let unwrapHolderHolderType: TypeID = if let cOpaquePointerSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("COpaquePointer")]) {
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
        registerSyntheticNativeTopLevelFunction(
            named: "unwrapKotlinObjectHolder",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [(name: "holder", type: unwrapHolderHolderType)],
            returnType: unwrapHolderTypeParameterType,
            typeParameterSymbols: [unwrapHolderTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
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
            let cPointerVarOfType = types.make(.classType(ClassType(
                classSymbol: cPointerVarOfSymbol,
                args: [.invariant(cPointerVarOfTypeParameterType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeBitSetConstructor(
                ownerSymbol: cPointerVarOfSymbol,
                ownerType: cPointerVarOfType,
                parameters: [(name: "rawPtr", type: nativePtrType)],
                defaultValues: [false],
                symbols: symbols,
                interner: interner
            )
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
        registerSyntheticCPointerVarTypeAlias(
            aliasSymbol: cPointerVarSymbol,
            aliasFQName: cinteropPkg + [interner.intern("CPointerVar")],
            typeParameterUpperBound: cPointedType,
            cPointerSymbol: cPointerSymbol,
            cPointerVarOfSymbol: cPointerVarOfSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
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
            registerSyntheticNativeBitSetProperty(
                named: "value",
                ownerSymbol: booleanVarOfSymbol,
                propertyType: booleanVarOfTypeParameterType,
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
            symbols.setTypeParameterUpperBounds([types.intType], for: byteVarOfTypeParameterSymbol)
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
            registerSyntheticNativeBitSetProperty(
                named: "value",
                ownerSymbol: byteVarOfSymbol,
                propertyType: byteVarOfTypeParameterType,
                symbols: symbols,
                interner: interner
            )
        }
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
            args: [.invariant(types.intType)],
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
        let cstrReturnType = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(byteVarType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeExtensionProperty(
            named: "cstr",
            packageFQName: cinteropPkg,
            packageSymbol: cinteropPkgSymbol,
            receiverType: types.stringType,
            propertyType: cstrReturnType,
            symbols: symbols,
            interner: interner
        )
        // NOTE: ByteArray.toKString() with no explicit args is covered by the
        // ByteArray.toKString(startIndex, endIndex, throwOnInvalidSequence) overload
        // registered above (all three parameters have default values).
        // Registering a separate zero-parameter overload here would cause ambiguity
        // when calling bytes.toKString() with no arguments.
        //
        // fun ByteArray.toCValues(): CValues<ByteVar>
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
        // fun ByteArray.toKString(startIndex: Int = 0, endIndex: Int = size, throwOnInvalidSequence: Boolean = false): String
        let byteArrayToKStringReceiverType = syntheticClassType(
            packagePath: ["kotlin"],
            name: "ByteArray",
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticNativeTopLevelFunction(
            named: "toKString",
            packageFQName: cinteropPkg,
            receiverType: byteArrayToKStringReceiverType,
            parameters: [
                (name: "startIndex", type: types.intType),
                (name: "endIndex", type: types.intType),
                (name: "throwOnInvalidSequence", type: types.booleanType),
            ],
            returnType: types.stringType,
            defaultValues: [true, true, true],
            externalLinkName: "kk_bytearray_toKString",
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
        let pinnedFQName = cinteropPkg + [interner.intern("Pinned")]
        let pinnedTypeParameterName = interner.intern("T")
        let pinnedTypeParameterFQName = pinnedFQName + [pinnedTypeParameterName]
        let pinnedTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: pinnedTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pinnedTypeParameterName,
                fqName: pinnedTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: pinnedTypeParameterSymbol)
        let pinnedTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pinnedTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pinnedType = types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinnedTypeParameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(pinnedType, for: pinnedSymbol)
        types.setNominalTypeParameterSymbols([pinnedTypeParameterSymbol], for: pinnedSymbol)
        types.setNominalTypeParameterVariances([.invariant], for: pinnedSymbol)

        let pinName = interner.intern("pin")
        let pinFQName = cinteropPkg + [pinName]
        let pinTypeParameterName = interner.intern("T")
        let pinTypeParameterFQName = pinFQName + [pinTypeParameterName]
        let pinTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: pinTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: pinTypeParameterName,
                fqName: pinTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: pinTypeParameterSymbol)
        let pinTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: pinTypeParameterSymbol,
            nullability: .nonNull
        )))
        let pinReturnType = types.make(.classType(ClassType(
            classSymbol: pinnedSymbol,
            args: [.invariant(pinTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "pin",
            packageFQName: cinteropPkg,
            receiverType: pinTypeParameterType,
            parameters: [],
            returnType: pinReturnType,
            typeParameterSymbols: [pinTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            externalLinkName: "kk_pin_object",
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
        // Pinned<T>.get(): T — STDLIB-CINTEROP-FN-009
        registerSyntheticNativeBitSetMemberFunction(
            named: "get",
            ownerSymbol: pinnedSymbol,
            receiverType: pinnedType,
            parameters: [],
            returnType: pinnedTypeParameterType,
            typeParameterSymbols: [pinnedTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            externalLinkName: "kk_pinned_get",
            symbols: symbols,
            interner: interner
        )
        // Pinned<T>.unpin(): Unit — STDLIB-CINTEROP-FN-009
        registerSyntheticNativeBitSetMemberFunction(
            named: "unpin",
            ownerSymbol: pinnedSymbol,
            receiverType: pinnedType,
            parameters: [],
            returnType: types.unitType,
            typeParameterSymbols: [pinnedTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            externalLinkName: "kk_unpin_object",
            symbols: symbols,
            interner: interner
        )

        let stableRefFQName = cinteropPkg + [interner.intern("StableRef")]
        let stableRefTypeParameterName = interner.intern("T")
        let stableRefTypeParameterFQName = stableRefFQName + [stableRefTypeParameterName]
        let stableRefTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: stableRefTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: stableRefTypeParameterName,
                fqName: stableRefTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: stableRefTypeParameterSymbol)
        let stableRefTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: stableRefTypeParameterSymbol,
            nullability: .nonNull
        )))
        let stableRefType = types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(stableRefTypeParameterType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(stableRefType, for: stableRefSymbol)
        symbols.insertFlags([.valueType], for: stableRefSymbol)
        symbols.setValueClassUnderlyingType(cOpaquePointerUnderlyingType, for: stableRefSymbol)
        types.setNominalTypeParameterSymbols([stableRefTypeParameterSymbol], for: stableRefSymbol)
        types.setNominalTypeParameterVariances([.out], for: stableRefSymbol)
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: stableRefSymbol,
            ownerType: stableRefType,
            parameters: [(name: "source", type: cOpaquePointerUnderlyingType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "asCPointer",
            ownerSymbol: stableRefSymbol,
            receiverType: stableRefType,
            parameters: [],
            returnType: cOpaquePointerUnderlyingType,
            typeParameterSymbols: [stableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "dispose",
            ownerSymbol: stableRefSymbol,
            receiverType: stableRefType,
            parameters: [],
            returnType: types.unitType,
            typeParameterSymbols: [stableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "get",
            ownerSymbol: stableRefSymbol,
            receiverType: stableRefType,
            parameters: [],
            returnType: stableRefTypeParameterType,
            typeParameterSymbols: [stableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            classTypeParameterCount: 1,
            symbols: symbols,
            interner: interner
        )
        let stableRefCompanionName = interner.intern("Companion")
        let stableRefCompanionFQName = stableRefFQName + [stableRefCompanionName]
        let stableRefCompanionSymbol: SymbolID
        if let existingCompanion = symbols.companionObjectSymbol(for: stableRefSymbol) {
            stableRefCompanionSymbol = existingCompanion
        } else if let existing = symbols.lookup(fqName: stableRefCompanionFQName),
                  symbols.symbol(existing)?.kind == .object
        {
            stableRefCompanionSymbol = existing
        } else {
            stableRefCompanionSymbol = symbols.define(
                kind: .object,
                name: stableRefCompanionName,
                fqName: stableRefCompanionFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .static]
            )
        }
        symbols.setParentSymbol(stableRefSymbol, for: stableRefCompanionSymbol)
        symbols.setCompanionObjectSymbol(stableRefCompanionSymbol, for: stableRefSymbol)
        let stableRefCompanionType = types.make(.classType(ClassType(
            classSymbol: stableRefCompanionSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(stableRefCompanionType, for: stableRefCompanionSymbol)
        let createTypeParameterName = interner.intern("T")
        let createFunctionName = interner.intern("create")
        let createTypeParameterFQName = stableRefCompanionFQName + [createFunctionName, createTypeParameterName]
        let createTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(fqName: createTypeParameterFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: createTypeParameterName,
                fqName: createTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        symbols.setTypeParameterUpperBounds([types.anyType], for: createTypeParameterSymbol)
        let createTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: createTypeParameterSymbol,
            nullability: .nonNull
        )))
        let createReturnType = types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(createTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeBitSetMemberFunction(
            named: "create",
            ownerSymbol: stableRefCompanionSymbol,
            receiverType: stableRefCompanionType,
            parameters: [(name: "any", type: createTypeParameterType)],
            returnType: createReturnType,
            typeParameterSymbols: [createTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            flags: [.synthetic, .static],
            symbols: symbols,
            interner: interner
        )
        let asStableRefName = interner.intern("asStableRef")
        let asStableRefFQName = cinteropPkg + [asStableRefName]
        let asStableRefTypeParameterName = interner.intern("T")
        let asStableRefTypeParameterFQName = asStableRefFQName + [asStableRefTypeParameterName]
        let asStableRefTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: asStableRefTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: asStableRefTypeParameterName,
                fqName: asStableRefTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: asStableRefTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([types.anyType], for: asStableRefTypeParameterSymbol)
        let asStableRefTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: asStableRefTypeParameterSymbol,
            nullability: .nonNull
        )))
        let cPointerStarType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        let asStableRefReturnType = types.make(.classType(ClassType(
            classSymbol: stableRefSymbol,
            args: [.out(asStableRefTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "asStableRef",
            packageFQName: cinteropPkg,
            receiverType: cPointerStarType,
            parameters: [],
            returnType: asStableRefReturnType,
            typeParameterSymbols: [asStableRefTypeParameterSymbol],
            typeParameterUpperBoundsList: [[types.anyType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )
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

        for primitiveVar in [
            "UByteVar",
            "ShortVar",
            "UShortVar",
            "IntVar",
            "UIntVar",
            "LongVar",
            "ULongVar",
            "FloatVar",
            "DoubleVar",
        ] {
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
            symbols.setDirectSupertypes([cPointedSymbol], for: symbol)
            types.setNominalDirectSupertypes([cPointedSymbol], for: symbol)
        }
        if let uShortVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]) {
            let uShortVarType = types.make(.classType(ClassType(
                classSymbol: uShortVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let wcstrReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uShortVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeExtensionProperty(
                named: "wcstr",
                packageFQName: cinteropPkg,
                packageSymbol: cinteropPkgSymbol,
                receiverType: types.stringType,
                propertyType: wcstrReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun UIntArray.toCValues(): CValues<UIntVar>
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
                symbols: symbols,
                interner: interner
            )
        }

        // fun LongArray.toCValues(): CValues<LongVar>
        if let longVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("LongVar")]) {
            let longVarType = types.make(.classType(ClassType(
                classSymbol: longVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let longArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "LongArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let longArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(longVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: longArrayReceiverType,
                parameters: [],
                returnType: longArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun FloatArray.toCValues(): CValues<FloatVar>
        if let floatVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("FloatVar")]) {
            let floatVarType = types.make(.classType(ClassType(
                classSymbol: floatVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let floatArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "FloatArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let floatArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(floatVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: floatArrayReceiverType,
                parameters: [],
                returnType: floatArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun DoubleArray.toCValues(): CValues<DoubleVar>
        if let doubleVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("DoubleVar")]) {
            let doubleVarType = types.make(.classType(ClassType(
                classSymbol: doubleVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let doubleArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "DoubleArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let doubleArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(doubleVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: doubleArrayReceiverType,
                parameters: [],
                returnType: doubleArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }

        // fun ULongArray.toCValues(): CValues<ULongVar>
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
        // fun CPointer<IntVar>.toKStringFromUtf32(): String
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

        // fun CPointer<ShortVar>.toKString(): String
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

        // fun CPointer<ShortVar>.toKStringFromUtf16(): String — STDLIB-CINTEROP-FN-034
        if let shortVarSymbolForUtf16 = symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]) {
            let shortVarTypeForUtf16 = types.make(.classType(ClassType(
                classSymbol: shortVarSymbolForUtf16,
                args: [],
                nullability: .nonNull
            )))
            let toKStringFromUtf16ShortReceiverType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(shortVarTypeForUtf16)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toKStringFromUtf16",
                packageFQName: cinteropPkg,
                receiverType: toKStringFromUtf16ShortReceiverType,
                parameters: [],
                returnType: types.stringType,
                symbols: symbols,
                interner: interner
            )
        }

        // fun CPointer<UShortVar>.toKStringFromUtf16(): String
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
        // fun CPointer<UShortVar>.toKString(): String
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
                symbols: symbols,
                interner: interner
            )
        }
        // fun UByteArray.toCValues(): CValues<UByteVar>
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
                symbols: symbols,
                interner: interner
            )
        }

        // fun ShortArray.toCValues(): CValues<ShortVar>
        if let shortVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("ShortVar")]) {
            let shortVarType = types.make(.classType(ClassType(
                classSymbol: shortVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let shortArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "ShortArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let shortArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(shortVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: shortArrayReceiverType,
                parameters: [],
                returnType: shortArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun UShortArray.toCValues(): CValues<UShortVar>
        if let uShortVarSymbol = symbols.lookup(fqName: cinteropPkg + [interner.intern("UShortVar")]) {
            let uShortVarType = types.make(.classType(ClassType(
                classSymbol: uShortVarSymbol,
                args: [],
                nullability: .nonNull
            )))
            let uShortArrayReceiverType = syntheticClassType(
                packagePath: ["kotlin"],
                name: "UShortArray",
                symbols: symbols,
                types: types,
                interner: interner
            )
            let uShortArrayToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(uShortVarType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: uShortArrayReceiverType,
                parameters: [],
                returnType: uShortArrayToCValuesReturnType,
                symbols: symbols,
                interner: interner
            )
        }
        // fun <T : CPointed> Array<CPointer<T>?>.toCValues(): CValues<CPointerVarOf<CPointer<T>>>
        let arrayCPointerToCValuesTParamName = interner.intern("T")
        let arrayCPointerToCValuesFunctionFQName = cinteropPkg + [interner.intern("toCValues")]
        let arrayCPointerToCValuesTParamFQName = arrayCPointerToCValuesFunctionFQName + [arrayCPointerToCValuesTParamName]
        let arrayCPointerToCValuesTParamSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: arrayCPointerToCValuesTParamFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: arrayCPointerToCValuesTParamName,
                fqName: arrayCPointerToCValuesTParamFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic]
            )
        }
        symbols.insertFlags([.synthetic], for: arrayCPointerToCValuesTParamSymbol)
        symbols.setTypeParameterUpperBounds([cPointedType], for: arrayCPointerToCValuesTParamSymbol)
        let arrayCPointerToCValuesTParamType = types.make(.typeParam(TypeParamType(
            symbol: arrayCPointerToCValuesTParamSymbol,
            nullability: .nonNull
        )))
        let arrayCPointerNullableElementType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(arrayCPointerToCValuesTParamType)],
            nullability: .nullable
        )))
        let kotlinArrayFQName = [interner.intern("kotlin"), interner.intern("Array")]
        if let kotlinArraySymbol = symbols.lookup(fqName: kotlinArrayFQName) {
            let arrayCPointerTReceiverType = types.make(.classType(ClassType(
                classSymbol: kotlinArraySymbol,
                args: [.invariant(arrayCPointerNullableElementType)],
                nullability: .nonNull
            )))
            let cPointerTNonNullType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(arrayCPointerToCValuesTParamType)],
                nullability: .nonNull
            )))
            let cPointerVarOfCPointerTType = types.make(.classType(ClassType(
                classSymbol: cPointerVarOfSymbol,
                args: [.invariant(cPointerTNonNullType)],
                nullability: .nonNull
            )))
            let arrayCPointerToCValuesReturnType = types.make(.classType(ClassType(
                classSymbol: cValuesSymbol,
                args: [.invariant(cPointerVarOfCPointerTType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeTopLevelFunction(
                named: "toCValues",
                packageFQName: cinteropPkg,
                receiverType: arrayCPointerTReceiverType,
                parameters: [],
                returnType: arrayCPointerToCValuesReturnType,
                typeParameterSymbols: [arrayCPointerToCValuesTParamSymbol],
                typeParameterUpperBoundsList: [[cPointedType]],
                symbols: symbols,
                interner: interner
            )
        }
        // fun <T : CPointed> List<CPointer<T>?>.toCValues(): CValues<CPointerVarOf<T>>
        let listCPointerTParamFQName = arrayCPointerToCValuesFunctionFQName + [interner.intern("T")]
        let listCPointerTParamSymbol: SymbolID = symbols.lookup(fqName: listCPointerTParamFQName) ?? arrayCPointerToCValuesTParamSymbol
        symbols.insertFlags([.synthetic], for: listCPointerTParamSymbol)
        symbols.setTypeParameterUpperBounds([cPointedType], for: listCPointerTParamSymbol)
        let listCPointerTParamType = types.make(.typeParam(TypeParamType(
            symbol: listCPointerTParamSymbol,
            nullability: .nonNull
        )))
        let nullableCPointerTType = types.make(.classType(ClassType(
            classSymbol: cPointerSymbol,
            args: [.invariant(listCPointerTParamType)],
            nullability: .nullable
        )))
        let listCPointerReceiverType = syntheticListType(
            elementType: nullableCPointerTType,
            symbols: symbols,
            types: types,
            interner: interner
        )
        let cPointerVarOfTType = types.make(.classType(ClassType(
            classSymbol: cPointerVarOfSymbol,
            args: [.invariant(listCPointerTParamType)],
            nullability: .nonNull
        )))
        let listCPointerToCValuesReturnType = types.make(.classType(ClassType(
            classSymbol: cValuesSymbol,
            args: [.invariant(cPointerVarOfTType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "toCValues",
            packageFQName: cinteropPkg,
            receiverType: listCPointerReceiverType,
            parameters: [],
            returnType: listCPointerToCValuesReturnType,
            typeParameterSymbols: [listCPointerTParamSymbol],
            typeParameterUpperBoundsList: [[cPointedType]],
            symbols: symbols,
            interner: interner
        )
        // STDLIB-CINTEROP-FN-039: typeOf<T>(): KType — inline reified function in kotlinx.cinterop.
        // Mirrors kotlin.typeOf<T>() for call sites that already import from this package.
        let cinteropTypeOfKTypeName = interner.intern("KType")
        let kotlinReflectInteropPkg = ensurePackage(
            path: ["kotlin", "reflect"],
            symbols: symbols,
            interner: interner
        )
        if let cinteropTypeOfKTypeSymbol = symbols.lookup(
            fqName: kotlinReflectInteropPkg + [cinteropTypeOfKTypeName]
        ) {
            let cinteropKTypeType = types.make(.classType(ClassType(
                classSymbol: cinteropTypeOfKTypeSymbol,
                args: [],
                nullability: .nonNull
            )))
            let cinteropTypeOfFQName = cinteropPkg + [interner.intern("typeOf")]
            if symbols.lookupAll(fqName: cinteropTypeOfFQName).isEmpty {
                let tParamName = interner.intern("T")
                let tParamSymbol = symbols.define(
                    kind: .typeParameter,
                    name: tParamName,
                    fqName: cinteropTypeOfFQName + [tParamName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic, .reifiedTypeParameter]
                )
                registerSyntheticNativeTopLevelFunction(
                    named: "typeOf",
                    packageFQName: cinteropPkg,
                    receiverType: nil,
                    parameters: [],
                    returnType: cinteropKTypeType,
                    typeParameterSymbols: [tParamSymbol],
                    typeParameterUpperBoundsList: [[]],
                    reifiedTypeParameterIndices: [0],
                    flags: [.synthetic, .inlineFunction],
                    symbols: symbols,
                    interner: interner
                )
            }
        }
        // STDLIB-CINTEROP-FN-047: inline fun <reified T : CVariable> zeroValue(): CValue<T>
        let zeroValueFunctionName = interner.intern("zeroValue")
        let zeroValueFunctionFQName = cinteropPkg + [zeroValueFunctionName]
        let zeroValueTypeParameterName = interner.intern("T")
        let zeroValueTypeParameterFQName = zeroValueFunctionFQName + [zeroValueTypeParameterName]
        let zeroValueTypeParameterSymbol: SymbolID = if let existing = symbols.lookup(
            fqName: zeroValueTypeParameterFQName
        ) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: zeroValueTypeParameterName,
                fqName: zeroValueTypeParameterFQName,
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.insertFlags([.synthetic, .reifiedTypeParameter], for: zeroValueTypeParameterSymbol)
        symbols.setTypeParameterUpperBounds([cVariableType], for: zeroValueTypeParameterSymbol)
        let zeroValueTypeParameterType = types.make(.typeParam(TypeParamType(
            symbol: zeroValueTypeParameterSymbol,
            nullability: .nonNull
        )))
        let zeroValueReturnType = types.make(.classType(ClassType(
            classSymbol: cValueSymbol,
            args: [.invariant(zeroValueTypeParameterType)],
            nullability: .nonNull
        )))
        registerSyntheticNativeTopLevelFunction(
            named: "zeroValue",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [],
            returnType: zeroValueReturnType,
            typeParameterSymbols: [zeroValueTypeParameterSymbol],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            symbols: symbols,
            interner: interner
        )

        // fun writeBits(ptr: NativePtr, offset: Long, size: Int, value: Long) — STDLIB-CINTEROP-FN-046
        registerSyntheticNativeTopLevelFunction(
            named: "writeBits",
            packageFQName: cinteropPkg,
            receiverType: nil,
            parameters: [
                (name: "ptr", type: nativePtrType),
                (name: "offset", type: types.longType),
                (name: "size", type: types.intType),
                (name: "value", type: types.longType),
            ],
            returnType: types.unitType,
            externalLinkName: "kk_cinterop_writeBits",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticCInteropVector128Stubs(
            cinteropPkg: cinteropPkg,
            cinteropPkgSymbol: cinteropPkgSymbol,
            symbols: symbols,
            types: types,
            interner: interner
        )
        registerSyntheticCInteropInternalStubs(
            symbols: symbols,
            types: types,
            interner: interner
        )
    }

    private func registerSyntheticCInteropInternalStubs(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let internalPkg = ensurePackage(
            path: ["kotlinx", "cinterop", "internal"],
            symbols: symbols,
            interner: interner
        )
        let internalPkgSymbol = symbols.lookup(fqName: internalPkg)

        // STDLIB-CINTEROP-INTERNAL-TYPE-002: CEnumEntryAlias
        // @Target(AnnotationTarget.CLASS)
        // @Retention(AnnotationRetention.BINARY)
        // annotation class CEnumEntryAlias(val entryName: String)
        let cEnumEntryAliasSymbol = ensureAnnotationClassSymbol(
            named: "CEnumEntryAlias",
            in: internalPkg,
            symbols: symbols,
            interner: interner
        )
        if let internalPkgSymbol {
            symbols.setParentSymbol(internalPkgSymbol, for: cEnumEntryAliasSymbol)
        }
        appendStandardAnnotationMetadata(
            to: cEnumEntryAliasSymbol,
            targets: ["AnnotationTarget.CLASS"],
            retention: "AnnotationRetention.BINARY",
            symbols: symbols
        )
        let cEnumEntryAliasType = types.make(.classType(ClassType(
            classSymbol: cEnumEntryAliasSymbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(cEnumEntryAliasType, for: cEnumEntryAliasSymbol)
        registerSyntheticNativeBitSetConstructor(
            ownerSymbol: cEnumEntryAliasSymbol,
            ownerType: cEnumEntryAliasType,
            parameters: [(name: "entryName", type: types.stringType)],
            defaultValues: [false],
            symbols: symbols,
            interner: interner
        )
    }

    private func registerSyntheticCInteropVector128Stubs(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let vector128Symbol = ensureClassSymbol(
            named: "Vector128",
            in: cinteropPkg,
            symbols: symbols,
            interner: interner
        )
        if let cinteropPkgSymbol {
            symbols.setParentSymbol(cinteropPkgSymbol, for: vector128Symbol)
        }
        let vector128Type = types.make(.classType(ClassType(
            classSymbol: vector128Symbol,
            args: [],
            nullability: .nonNull
        )))
        symbols.setPropertyType(vector128Type, for: vector128Symbol)
        appendMetadataAnnotations(
            [MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi")],
            to: vector128Symbol,
            symbols: symbols
        )

        let elementAccessors: [(name: String, returnType: TypeID)] = [
            ("getByteAt", types.intType),
            ("getIntAt", types.intType),
            ("getLongAt", types.longType),
            ("getFloatAt", types.floatType),
            ("getDoubleAt", types.doubleType),
            ("getUByteAt", types.ubyteType),
            ("getUIntAt", types.uintType),
            ("getULongAt", types.ulongType),
        ]
        for accessor in elementAccessors {
            registerSyntheticNativeBitSetMemberFunction(
                named: accessor.name,
                ownerSymbol: vector128Symbol,
                receiverType: vector128Type,
                parameters: [(name: "index", type: types.intType)],
                returnType: accessor.returnType,
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticNativeBitSetMemberFunction(
            named: "equals",
            ownerSymbol: vector128Symbol,
            receiverType: vector128Type,
            parameters: [(name: "other", type: types.makeNullable(types.anyType))],
            returnType: types.booleanType,
            flags: [.synthetic, .operatorFunction, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "hashCode",
            ownerSymbol: vector128Symbol,
            receiverType: vector128Type,
            parameters: [],
            returnType: types.intType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeBitSetMemberFunction(
            named: "toString",
            ownerSymbol: vector128Symbol,
            receiverType: vector128Type,
            parameters: [],
            returnType: types.stringType,
            flags: [.synthetic, .overrideMember],
            symbols: symbols,
            interner: interner
        )

        let experimentalForeignApiAnnotations = [
            MetadataAnnotationRecord(annotationFQName: "kotlinx.cinterop.ExperimentalForeignApi"),
        ]
        for parameterType in [types.floatType, types.intType] {
            registerSyntheticNativeTopLevelFunction(
                named: "vectorOf",
                packageFQName: cinteropPkg,
                receiverType: nil,
                parameters: [
                    (name: "f0", type: parameterType),
                    (name: "f1", type: parameterType),
                    (name: "f2", type: parameterType),
                    (name: "f3", type: parameterType),
                ],
                returnType: vector128Type,
                annotations: experimentalForeignApiAnnotations,
                symbols: symbols,
                interner: interner
            )
        }
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
