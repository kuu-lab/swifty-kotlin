extension DataFlowSemaPhase {
    func registerCInteropMemScopedStub(
        cinteropPkg: [InternedString],
        memScopeType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let memScopedName = interner.intern("memScoped")
        let memScopedFQName = cinteropPkg + [memScopedName]
        if symbols.deferWorkUntilImportedMemberMaterializes(at: memScopedFQName, work: { [self] in
            registerCInteropMemScopedStub(
                cinteropPkg: cinteropPkg,
                memScopeType: memScopeType,
                symbols: symbols,
                types: types,
                interner: interner
            )
        }) {
            return
        }
        if symbols.lookupAll(fqName: memScopedFQName).contains(where: { symbolID in
            guard let sig = symbols.functionSignature(for: symbolID) else { return false }
            return sig.receiverType == nil && sig.parameterTypes.count == 1 && sig.typeParameterSymbols.count == 1
        }) {
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
    }

    func registerCInteropPlacementScopeMembers(
        cinteropPkg: [InternedString],
        cinteropPkgSymbol: SymbolID?,
        cVariableType: TypeID,
        cPointerSymbol: SymbolID,
        cPointerStarType: TypeID,
        nativePlacementSymbol: SymbolID,
        nativePlacementType: TypeID,
        nativeFreeablePlacementSymbol: SymbolID,
        nativeFreeablePlacementType: TypeID,
        deferScopeSymbol: SymbolID,
        deferScopeType: TypeID,
        autofreeScopeSymbol: SymbolID,
        autofreeScopeType: TypeID,
        arenaSymbol: SymbolID,
        arenaType: TypeID,
        memScopeSymbol: SymbolID,
        memScopeType: TypeID,
        nativePtrType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let allocTName = interner.intern("T")
        let allocFunctionFQName = cinteropPkg + [interner.intern("NativePlacement"), interner.intern("alloc")]
        let placementAllocT: SymbolID = if let existing = symbols.lookup(fqName: allocFunctionFQName + [allocTName]) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: allocTName,
                fqName: allocFunctionFQName + [allocTName],
                declSite: nil,
                visibility: .private,
                flags: [.synthetic, .reifiedTypeParameter]
            )
        }
        symbols.setTypeParameterUpperBounds([cVariableType], for: placementAllocT)
        let placementAllocTType = types.make(.typeParam(TypeParamType(
            symbol: placementAllocT,
            nullability: .nonNull
        )))
        registerSyntheticNativeMemberFunction(
            named: "alloc",
            ownerSymbol: nativePlacementSymbol,
            receiverType: nativePlacementType,
            parameters: [],
            returnType: placementAllocTType,
            typeParameterSymbols: [placementAllocT],
            typeParameterUpperBoundsList: [[cVariableType]],
            reifiedTypeParameterIndices: [0],
            flags: [.synthetic, .inlineFunction],
            externalLinkName: "kk_arena_alloc_var",
            symbols: symbols,
            interner: interner
        )
        // Kotlin/Native accepts both Int and Long counts. Each overload owns
        // its reified parameter so an Int variable preserves the element token.
        for lengthType in [types.longType, types.intType] {
            let allocArrayTName = interner.intern("T")
            let allocArrayFunctionFQName = cinteropPkg + [interner.intern("NativePlacement"), interner.intern("allocArray")]
                + (lengthType == types.intType ? [interner.intern("$intLength")] : [])
            let placementAllocArrayT: SymbolID = if let existing = symbols.lookup(fqName: allocArrayFunctionFQName + [allocArrayTName]) {
                existing
            } else {
                symbols.define(
                    kind: .typeParameter,
                    name: allocArrayTName,
                    fqName: allocArrayFunctionFQName + [allocArrayTName],
                    declSite: nil,
                    visibility: .private,
                    flags: [.synthetic, .reifiedTypeParameter]
                )
            }
            symbols.setTypeParameterUpperBounds([cVariableType], for: placementAllocArrayT)
            let placementAllocArrayTType = types.make(.typeParam(TypeParamType(
                symbol: placementAllocArrayT,
                nullability: .nonNull
            )))
            let allocArrayReturnType = types.make(.classType(ClassType(
                classSymbol: cPointerSymbol,
                args: [.invariant(placementAllocArrayTType)],
                nullability: .nonNull
            )))
            registerSyntheticNativeMemberFunction(
                named: "allocArray",
                ownerSymbol: nativePlacementSymbol,
                receiverType: nativePlacementType,
                parameters: [(name: "length", type: lengthType)],
                returnType: allocArrayReturnType,
                typeParameterSymbols: [placementAllocArrayT],
                typeParameterUpperBoundsList: [[cVariableType]],
                reifiedTypeParameterIndices: [0],
                flags: [.synthetic, .inlineFunction],
                externalLinkName: "kk_arena_alloc_array",
                symbols: symbols,
                interner: interner
            )
        }
        registerSyntheticNativeMemberFunction(
            named: "allocRaw",
            ownerSymbol: nativePlacementSymbol,
            receiverType: nativePlacementType,
            parameters: [
                (name: "size", type: types.longType),
                (name: "align", type: types.intType),
            ],
            returnType: nativePtrType,
            externalLinkName: "kk_arena_alloc_raw",
            symbols: symbols,
            interner: interner
        )
        // NOTE: upstream also declares `alloc(size: Long, align: Int)` on
        // NativePlacement returning COpaquePointer. Omitted here — the bridge
        // returns a NativePtr box, and `allocRaw` covers the raw path.

        registerSyntheticNativeMemberFunction(
            named: "free",
            ownerSymbol: nativeFreeablePlacementSymbol,
            receiverType: nativeFreeablePlacementType,
            parameters: [(name: "ptr", type: types.makeNullable(cPointerStarType))],
            returnType: types.unitType,
            externalLinkName: "kk_native_placement_free",
            symbols: symbols,
            interner: interner
        )
        registerSyntheticNativeMemberFunction(
            named: "free",
            ownerSymbol: nativeFreeablePlacementSymbol,
            receiverType: nativeFreeablePlacementType,
            parameters: [(name: "ptr", type: nativePtrType)],
            returnType: types.unitType,
            externalLinkName: "kk_native_placement_free",
            symbols: symbols,
            interner: interner
        )

        // A throwing deferred block propagates out of clear().
        registerSyntheticNativeMemberFunction(
            named: "clear",
            ownerSymbol: autofreeScopeSymbol,
            receiverType: autofreeScopeType,
            parameters: [],
            returnType: types.unitType,
            externalLinkName: "kk_arena_clear",
            canThrow: true,
            symbols: symbols,
            interner: interner
        )
        // Deferred blocks run LIFO on clear().
        let deferBlockType = types.make(.functionType(FunctionType(
            params: [],
            returnType: types.unitType,
            isSuspend: false,
            nullability: .nonNull
        )))
        registerSyntheticNativeMemberFunction(
            named: "defer",
            ownerSymbol: deferScopeSymbol,
            receiverType: deferScopeType,
            parameters: [(name: "block", type: deferBlockType)],
            returnType: types.unitType,
            externalLinkName: "kk_defer_scope_defer",
            symbols: symbols,
            interner: interner
        )

        registerNativeConcurrentConstructor(
            ownerSymbol: arenaSymbol,
            ownerType: arenaType,
            externalLinkName: "kk_arena_new",
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )
        registerNativeConcurrentConstructor(
            ownerSymbol: memScopeSymbol,
            ownerType: memScopeType,
            externalLinkName: "kk_memscope_new",
            parameters: [],
            defaultValues: [],
            symbols: symbols,
            interner: interner
        )

        let nativeHeapPropertyName = interner.intern("nativeHeap")
        let nativeHeapPropertyFQName = cinteropPkg + [nativeHeapPropertyName]
        if symbols.lookupAll(fqName: nativeHeapPropertyFQName).contains(where: { symbols.symbol($0)?.kind == .property }) {
        } else {
            let nativeHeapPropertySymbol = symbols.define(
                kind: .property,
                name: nativeHeapPropertyName,
                fqName: nativeHeapPropertyFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            if let cinteropPkgSymbol {
                symbols.setParentSymbol(cinteropPkgSymbol, for: nativeHeapPropertySymbol)
            }
            symbols.setPropertyType(nativeFreeablePlacementType, for: nativeHeapPropertySymbol)
            symbols.setExternalLinkName("kk_native_heap_get", for: nativeHeapPropertySymbol)
        }
    }
}
