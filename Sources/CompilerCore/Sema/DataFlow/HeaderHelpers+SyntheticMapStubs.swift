import RuntimeABI

/// Synthetic stdlib stubs split from the KSP-697 collection residual registry:
/// Map<K,V>, Map.Entry<K,V>, and MutableMap<K,V> interface shells and their
/// remaining runtime-backed residuals (KSP-703 moved the higher-order members
/// and isEmpty/get/remove/clear to bundled Kotlin source).
///
/// Split out to isolate merge conflicts between parallel stdlib PRs adding new
/// entries to this package.
extension DataFlowSemaPhase {

    func registerSyntheticMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) -> (mapSymbol: SymbolID, keyTypeParamSymbol: SymbolID, valueTypeParamSymbol: SymbolID) {
        let mapName = interner.intern("Map")
        let mapFQName = kotlinCollectionsPkg + [mapName]
        let mapSymbol: SymbolID = if let existing = symbols.lookup(fqName: mapFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mapName,
                fqName: mapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: mapFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let valueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: mapFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        types.setNominalTypeParameterSymbols([keyParamSymbol, valueParamSymbol], for: mapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: mapSymbol)

        // KSP-703: `get` is source-backed via @KsSymbolName directly on
        // Map/Map.kt's interface declaration, matching Set.kt's KSP-704
        // precedent for contains/isEmpty/iterator. As with that precedent, a
        // `--no-stdlib` compile no longer gets a `get` member on this
        // fallback shell (bundled Map.kt is what carries the annotation); the
        // same trade-off already applies to Set under KSP-704.

        return (mapSymbol, keyParamSymbol, valueParamSymbol)
    }

    /// Register `kotlin.collections.AbstractMap<K, V>` surface (STDLIB-COL-ABSTRACT-004).
    func registerSyntheticAbstractMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID
    ) -> SymbolID {
        let abstractMapName = interner.intern("AbstractMap")
        let abstractMapFQName = kotlinCollectionsPkg + [abstractMapName]
        let abstractMapSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMapFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMapName,
                fqName: abstractMapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyParamFQName = abstractMapFQName + [keyName]
        let valueParamFQName = abstractMapFQName + [valueName]
        let keyParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: keyParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: keyName,
                fqName: keyParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let valueParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: valueParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: valueParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueParamSymbol, nullability: .nonNull)))

        types.setNominalTypeParameterSymbols([keyParamSymbol, valueParamSymbol], for: abstractMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: abstractMapSymbol)

        let abstractMapType = types.make(.classType(ClassType(
            classSymbol: abstractMapSymbol,
            args: [.invariant(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMapType, for: abstractMapSymbol)
        symbols.setDirectSupertypes([mapInterfaceSymbol], for: abstractMapSymbol)
        types.setNominalDirectSupertypes([mapInterfaceSymbol], for: abstractMapSymbol)
        symbols.setSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMapSymbol,
            supertype: mapInterfaceSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMapSymbol,
            supertype: mapInterfaceSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractMapFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMapSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMapType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: initSymbol
            )
        }

        return abstractMapSymbol
    }

    func registerMapHigherOrderMembers(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        collectionInterfaceSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]

        // Keep the legacy Map vtable slot reserved when the source-backed
        // no-argument count extension replaces the synthetic member. Runtime
        // dispatch for Map.size uses the slot after the two existing Map
        // entries, so removing the synthetic count symbol must not shift that
        // ABI slot even though the source declaration is not a Map member.
        let sourceBackedMapCount = bundledIndex.contains(
            ownerFQName: mapFQName,
            name: interner.intern("count"),
            arity: 0
        )
        if sourceBackedMapCount {
            let existingHint = symbols.nominalLayoutHint(for: mapInterfaceSymbol)
            symbols.setNominalLayoutHint(
                NominalLayoutHint(
                    declaredFieldCount: existingHint?.declaredFieldCount,
                    declaredInstanceSizeWords: existingHint?.declaredInstanceSizeWords,
                    declaredVtableSize: max(existingHint?.declaredVtableSize ?? 0, 2),
                    declaredItableSize: existingHint?.declaredItableSize
                ),
                for: mapInterfaceSymbol
            )
        }

        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        let entryType = registerSyntheticMapEntryStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapInterfaceSymbol,
            keyTypeParamSymbol: keyTypeParamSymbol,
            valueTypeParamSymbol: valueTypeParamSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )
        // MutableMap is registered before Map.Entry, so its nested entry shell
        // cannot link its inherited Map.Entry surface during first registration.
        // Complete that relationship now, after Map.Entry exists, so key/value
        // lookup follows the Kotlin declaration rather than a duplicate member.
        let mutableMapFQName = kotlinCollectionsPkg + [interner.intern("MutableMap")]
        if let mutableEntrySymbol = symbols.lookup(
            fqName: mutableMapFQName + [interner.intern("MutableEntry")]
        ),
           let mutableEntryKeySymbol = symbols.lookup(
               fqName: mutableMapFQName
                   + [interner.intern("MutableEntry"), interner.intern("K")]
           ),
           let mutableEntryValueSymbol = symbols.lookup(
               fqName: mutableMapFQName
                   + [interner.intern("MutableEntry"), interner.intern("V")]
           ),
           let mapEntrySymbol = symbols.lookup(fqName: mapFQName + [interner.intern("Entry")])
        {
            let mutableEntryKeyType = types.make(.typeParam(TypeParamType(
                symbol: mutableEntryKeySymbol,
                nullability: .nonNull
            )))
            let mutableEntryValueType = types.make(.typeParam(TypeParamType(
                symbol: mutableEntryValueSymbol,
                nullability: .nonNull
            )))
            let mutableEntrySupertypeArgs: [TypeArg] = [
                .out(mutableEntryKeyType),
                .out(mutableEntryValueType),
            ]
            symbols.setDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            types.setNominalDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            symbols.setSupertypeTypeArgs(
                mutableEntrySupertypeArgs,
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
            types.setNominalSupertypeTypeArgs(
                mutableEntrySupertypeArgs,
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
        }
        let setSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Set")])
            ?? symbols.lookupByShortName(interner.intern("Set")).first

        // Keep runtime-backed placeholders for Map's four abstract properties
        // (size/keys/values/entries) so the bundled Map declaration can claim
        // the existing symbols while preserving their ABI links. The source
        // declaration intentionally remains abstract; these links are used
        // for runtime map boxes when a call is made through a Map-typed
        // receiver. isEmpty/get moved to @KsSymbolName bridges directly on
        // Map/Map.kt (KSP-703): the annotation pipeline only attaches link
        // names to .function/.constructor symbols, not .property, so these
        // four cannot follow.
        func registerPropertyMember(
            name: String,
            propertyType: TypeID,
            externalLinkName: String
        ) {
            let memberName = interner.intern(name)
            let memberFQName = mapFQName + [memberName]
            if let existing = symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                guard let symbol = symbols.symbol(symbolID) else { return false }
                return symbol.kind == .property
                    && symbols.parentSymbol(for: symbolID) == mapInterfaceSymbol
            }) {
                symbols.setPropertyType(propertyType, for: existing)
                symbols.setExternalLinkName(externalLinkName, for: existing)
                return
            }
            let memberSymbol = symbols.define(
                kind: .property,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapInterfaceSymbol, for: memberSymbol)
            symbols.setPropertyType(propertyType, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        }

        if let setSymbol {
            let entriesType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(entryType)],
                nullability: .nonNull
            )))
            let keysType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(keyType)],
                nullability: .nonNull
            )))
            registerPropertyMember(
                name: "entries",
                propertyType: entriesType,
                externalLinkName: "__kk_map_entries"
            )
            registerPropertyMember(
                name: "keys",
                propertyType: keysType,
                externalLinkName: "__kk_map_keys"
            )
        }
        let valuesType = types.make(.classType(ClassType(
            classSymbol: collectionInterfaceSymbol,
            args: [.out(valueType)],
            nullability: .nonNull
        )))
        registerPropertyMember(
            name: "size",
            propertyType: types.intType,
            externalLinkName: "kk_map_size"
        )
        registerPropertyMember(
            name: "values",
            propertyType: valuesType,
            externalLinkName: "__kk_map_values"
        )

        // RF-STUB-001/KSP-703: forEach/map/mapNotNull/mapValues/mapKeys/
        // mapKeysTo/mapValuesTo/filter/filterNot/filterKeys/filterValues/
        // count/any/all/none/plus/minus/flatMap/maxByOrNull/minByOrNull are
        // all source-backed in MapHOF.kt/MapLookupAndTransform.kt. Their
        // former synthetic registrations here were unreachable — each was
        // guarded by an unconditional `bundledIndex.contains(...)` early
        // return — and have been removed, matching RF-LOWER-CALL-012's
        // analogous cleanup of the now-dead Lowering-side rewrite branches
        // for the same names (`CollectionLiteralLoweringPass+CallRewrite*`).
        // isEmpty/get moved to @KsSymbolName bridges on Map/Map.kt above.
    }

    private func registerSyntheticMapEntryStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex,
        skipStats: SyntheticStubSkipStatsCollector?
    ) -> TypeID {
        let entryName = interner.intern("Entry")
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        let entryFQName = mapFQName + [entryName]
        let entrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: entryFQName) {
            entrySymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mapInterfaceSymbol, for: symbol)
            entrySymbol = symbol
        }

        let keyType = types.make(.typeParam(TypeParamType(symbol: keyTypeParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueTypeParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([keyTypeParamSymbol, valueTypeParamSymbol], for: entrySymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: entrySymbol)
        let receiverType = types.make(.classType(ClassType(
            classSymbol: entrySymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        // KSP-961/KSP-703: component1/component2 are source-backed extensions
        // on Map.Entry in Entry.kt (guarded by `bundledIndex.contains`, so the
        // synthetic registration was unreachable once that bundled source
        // existed) — removed. key/value stay: no bundled Map.Entry interface
        // declaration exists yet, so these runtime-backed accessors remain
        // the only source of the interface members.
        func registerMember(
            name: String,
            returnType: TypeID,
            externalLinkName: String,
            flags: SymbolFlags = [.synthetic]
        ) {
            let memberName = interner.intern(name)
            let memberFQName = entryFQName + [memberName]
            guard symbols.lookup(fqName: memberFQName) == nil else { return }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: flags
            )
            symbols.setParentSymbol(entrySymbol, for: memberSymbol)
            symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: [],
                    returnType: returnType,
                    typeParameterSymbols: [keyTypeParamSymbol, valueTypeParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        registerMember(name: "key", returnType: keyType, externalLinkName: "__kk_pair_first")
        registerMember(name: "value", returnType: valueType, externalLinkName: "__kk_pair_second")

        return receiverType
    }

    func registerSyntheticMutableMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        keyTypeParamSymbol _: SymbolID,
        valueTypeParamSymbol _: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) {
        let mutableMapName = interner.intern("MutableMap")
        let mutableMapFQName = kotlinCollectionsPkg + [mutableMapName]
        let mutableMapSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableMapFQName) {
            existing
        } else {
            symbols.define(
                kind: .interface,
                name: mutableMapName,
                fqName: mutableMapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setDirectSupertypes([mapInterfaceSymbol], for: mutableMapSymbol)
        types.setNominalDirectSupertypes([mapInterfaceSymbol], for: mutableMapSymbol)

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let mutableKeyParamSymbol = symbols.define(
            kind: .typeParameter,
            name: keyName,
            fqName: mutableMapFQName + [keyName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let mutableValueParamSymbol = symbols.define(
            kind: .typeParameter,
            name: valueName,
            fqName: mutableMapFQName + [valueName],
            declSite: nil,
            visibility: .private,
            flags: []
        )
        let keyType = types.make(.typeParam(TypeParamType(symbol: mutableKeyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: mutableValueParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols([mutableKeyParamSymbol, mutableValueParamSymbol], for: mutableMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: mutableMapSymbol)
        // Map's own K is invariant (only V is `out`), so the MutableMap -> Map
        // supertype edge must project K as invariant too. Projecting it `.out`
        // made `isProjectionSubtype` reject any Map<K, V> view of a MutableMap
        // (composedProjection passes an invariant declaration's use-site
        // projection through unchanged, so `.out(K)` never satisfies an
        // `.invariant(K)` target) -- masked everywhere else because existing
        // MutableMap-to-Map widenings route through AbstractMap instead.
        symbols.setSupertypeTypeArgs([.invariant(keyType), .out(valueType)], for: mutableMapSymbol, supertype: mapInterfaceSymbol)
        types.setNominalSupertypeTypeArgs([.invariant(keyType), .out(valueType)], for: mutableMapSymbol, supertype: mapInterfaceSymbol)

        // The source-backed AbstractMutableMap declaration names the official
        // nested MutableMap.MutableEntry type. Keep this nominal entry shell in
        // the shared fallback path until MutableMap itself becomes source-backed.
        let mutableEntryName = interner.intern("MutableEntry")
        let mutableEntryFQName = mutableMapFQName + [mutableEntryName]
        let mutableEntrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: mutableEntryFQName) {
            mutableEntrySymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: mutableEntryName,
                fqName: mutableEntryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableMapSymbol, for: symbol)
            mutableEntrySymbol = symbol
        }
        types.setNominalTypeParameterSymbols([mutableKeyParamSymbol, mutableValueParamSymbol], for: mutableEntrySymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: mutableEntrySymbol)
        if let mapEntrySymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Map"), interner.intern("Entry")]
        ) {
            symbols.setDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            types.setNominalDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            symbols.setSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
            types.setNominalSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
        }

        // Keep the official MutableMap.entries property available to the
        // source-backed AbstractMutableMap declaration. The runtime-backed
        // collection behavior remains on the existing shared map bridges.
        let mutableSetSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
        )
        let mutableEntryType = types.make(.classType(ClassType(
            classSymbol: mutableEntrySymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        let mutableEntriesType: TypeID
        if let mutableSetSymbol {
            mutableEntriesType = types.make(.classType(ClassType(
                classSymbol: mutableSetSymbol,
                args: [.invariant(mutableEntryType)],
                nullability: .nonNull
            )))
        } else {
            mutableEntriesType = types.anyType
        }
        let entriesName = interner.intern("entries")
        let entriesFQName = mutableMapFQName + [entriesName]
        let entriesPropertySymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: entriesFQName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
        }) {
            entriesPropertySymbol = existing
        } else {
            entriesPropertySymbol = symbols.define(
                kind: .property,
                name: entriesName,
                fqName: entriesFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableMapSymbol, for: entriesPropertySymbol)
        }
        symbols.setPropertyType(mutableEntriesType, for: entriesPropertySymbol)
        symbols.setExternalLinkName("__kk_map_entries", for: entriesPropertySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))

        let mapParamType = types.make(.classType(ClassType(
            classSymbol: mapInterfaceSymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        _ = registerSyntheticMutableMapEntryStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapInterfaceSymbol,
            mutableMapSymbol: mutableMapSymbol,
            keyTypeParamSymbol: mutableKeyParamSymbol,
            valueTypeParamSymbol: mutableValueParamSymbol,
            bundledIndex: bundledIndex,
            skipStats: skipStats
        )

        // KSP-703: remove/clear moved to @KsSymbolName bridges directly on
        // MutableMap.kt (see that file's header comment for why put/putAll
        // stay here instead). `set` and the higher-order MutableMap APIs are
        // source-backed in MapLookupAndTransform.kt.
        let members: [(name: String, params: [TypeID], ret: TypeID, external: String, flags: SymbolFlags)] = [
            ("put", [keyType, valueType], types.makeNullable(valueType), "__kk_mutable_map_put", [.synthetic, .throwingFunction]),
            ("putAll", [mapParamType], types.unitType, "__kk_mutable_map_putAll", [.synthetic]),
        ]

        for member in members {
            let memberName = interner.intern(member.name)
            let memberFQName = mutableMapFQName + [memberName]
            guard symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                guard let signature = symbols.functionSignature(for: symbolID) else { return false }
                return signature.parameterTypes == member.params &&
                    signature.returnType == member.ret
            }) == nil else {
                continue
            }
            let memberSymbol = symbols.define(
                kind: .function,
                name: memberName,
                fqName: memberFQName,
                declSite: nil,
                visibility: .public,
                flags: member.flags
            )
            symbols.setParentSymbol(mutableMapSymbol, for: memberSymbol)
            symbols.setExternalLinkName(member.external, for: memberSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: receiverType,
                    parameterTypes: member.params,
                    returnType: member.ret,
                    typeParameterSymbols: [mutableKeyParamSymbol, mutableValueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: memberSymbol
            )
        }

        _ = registerSyntheticAbstractMutableMapStub(
            symbols: symbols,
            types: types,
            interner: interner,
            kotlinCollectionsPkg: kotlinCollectionsPkg,
            mapInterfaceSymbol: mapInterfaceSymbol,
            mutableMapSymbol: mutableMapSymbol
        )
    }

    private func registerSyntheticMutableMapEntryStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        mutableMapSymbol: SymbolID,
        keyTypeParamSymbol: SymbolID,
        valueTypeParamSymbol: SymbolID,
        bundledIndex: BundledDeclarationIndex = .empty,
        skipStats: SyntheticStubSkipStatsCollector? = nil
    ) -> TypeID {
        let mutableEntryName = interner.intern("MutableEntry")
        let mutableMapFQName = kotlinCollectionsPkg + [interner.intern("MutableMap")]
        let mutableEntryFQName = mutableMapFQName + [mutableEntryName]
        let mutableEntrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: mutableEntryFQName) {
            mutableEntrySymbol = existing
        } else {
            let symbol = symbols.define(
                kind: .interface,
                name: mutableEntryName,
                fqName: mutableEntryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(mutableMapSymbol, for: symbol)
            mutableEntrySymbol = symbol
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let mutableKeyParamFQName = mutableEntryFQName + [keyName]
        let mutableValueParamFQName = mutableEntryFQName + [valueName]
        let mutableEntryKeyParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableKeyParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: keyName,
                fqName: mutableKeyParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let mutableEntryValueParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: mutableValueParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: mutableValueParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: mutableEntryKeyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: mutableEntryValueParamSymbol, nullability: .nonNull)))
        types.setNominalTypeParameterSymbols(
            [mutableEntryKeyParamSymbol, mutableEntryValueParamSymbol],
            for: mutableEntrySymbol
        )
        types.setNominalTypeParameterVariances([.out, .out], for: mutableEntrySymbol)

        let receiverType = types.make(.classType(ClassType(
            classSymbol: mutableEntrySymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))
        if let mapEntrySymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Map"), interner.intern("Entry")]
        ) {
            symbols.setDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            types.setNominalDirectSupertypes([mapEntrySymbol], for: mutableEntrySymbol)
            symbols.setSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
            types.setNominalSupertypeTypeArgs(
                [.out(keyType), .out(valueType)],
                for: mutableEntrySymbol,
                supertype: mapEntrySymbol
            )
        }

        // KSP-1076/KSP-703: setValue is a source-backed extension in
        // MutableEntry.kt (`shouldSkipSyntheticStub` always short-circuited
        // this registration once that bundled source existed) — removed.

        _ = mapInterfaceSymbol
        _ = keyTypeParamSymbol
        _ = valueTypeParamSymbol
        return receiverType
    }

    /// Register the fallback `kotlin.collections.AbstractMutableMap<K, V>` surface
    /// (STDLIB-COL-ABSTRACT-007). The bundled declaration in
    /// `Stdlib/kotlin/collections/AbstractMutableMap.kt` owns the normal source-backed
    /// path; this shell remains available for non-bundled metadata contexts.
    func registerSyntheticAbstractMutableMapStub(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString],
        mapInterfaceSymbol: SymbolID,
        mutableMapSymbol: SymbolID
    ) -> SymbolID {
        let abstractMutableMapName = interner.intern("AbstractMutableMap")
        let abstractMutableMapFQName = kotlinCollectionsPkg + [abstractMutableMapName]
        let abstractMutableMapSymbol: SymbolID = if let existing = symbols.lookup(fqName: abstractMutableMapFQName) {
            existing
        } else {
            symbols.define(
                kind: .class,
                name: abstractMutableMapName,
                fqName: abstractMutableMapFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic, .abstractType]
            )
        }

        let keyName = interner.intern("K")
        let valueName = interner.intern("V")
        let keyParamFQName = abstractMutableMapFQName + [keyName]
        let valueParamFQName = abstractMutableMapFQName + [valueName]
        let keyParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: keyParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: keyName,
                fqName: keyParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let valueParamSymbol: SymbolID = if let existing = symbols.lookup(fqName: valueParamFQName) {
            existing
        } else {
            symbols.define(
                kind: .typeParameter,
                name: valueName,
                fqName: valueParamFQName,
                declSite: nil,
                visibility: .private,
                flags: []
            )
        }
        let keyType = types.make(.typeParam(TypeParamType(symbol: keyParamSymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: valueParamSymbol, nullability: .nonNull)))

        types.setNominalTypeParameterSymbols([keyParamSymbol, valueParamSymbol], for: abstractMutableMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: abstractMutableMapSymbol)

        let abstractMutableMapType = types.make(.classType(ClassType(
            classSymbol: abstractMutableMapSymbol,
            args: [.invariant(keyType), .invariant(valueType)],
            nullability: .nonNull
        )))
        symbols.setPropertyType(abstractMutableMapType, for: abstractMutableMapSymbol)

        let abstractMapSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("AbstractMap")])
        let readonlySupertype = abstractMapSymbol ?? mapInterfaceSymbol
        symbols.setDirectSupertypes([readonlySupertype, mutableMapSymbol], for: abstractMutableMapSymbol)
        types.setNominalDirectSupertypes([readonlySupertype, mutableMapSymbol], for: abstractMutableMapSymbol)
        symbols.setSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMutableMapSymbol,
            supertype: readonlySupertype
        )
        types.setNominalSupertypeTypeArgs(
            [.invariant(keyType), .out(valueType)],
            for: abstractMutableMapSymbol,
            supertype: readonlySupertype
        )
        symbols.setSupertypeTypeArgs(
            [.invariant(keyType), .invariant(valueType)],
            for: abstractMutableMapSymbol,
            supertype: mutableMapSymbol
        )
        types.setNominalSupertypeTypeArgs(
            [.invariant(keyType), .invariant(valueType)],
            for: abstractMutableMapSymbol,
            supertype: mutableMapSymbol
        )

        let initName = interner.intern("<init>")
        let initFQName = abstractMutableMapFQName + [initName]
        if symbols.lookup(fqName: initFQName) == nil {
            let initSymbol = symbols.define(
                kind: .constructor,
                name: initName,
                fqName: initFQName,
                declSite: nil,
                visibility: .protected,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(abstractMutableMapSymbol, for: initSymbol)
            symbols.setFunctionSignature(
                FunctionSignature(
                    receiverType: nil,
                    parameterTypes: [],
                    returnType: abstractMutableMapType,
                    valueParameterSymbols: [],
                    valueParameterHasDefaultValues: [],
                    valueParameterIsVararg: [],
                    typeParameterSymbols: [keyParamSymbol, valueParamSymbol],
                    classTypeParameterCount: 2
                ),
                for: initSymbol
            )
        }

        return abstractMutableMapSymbol
    }
}
