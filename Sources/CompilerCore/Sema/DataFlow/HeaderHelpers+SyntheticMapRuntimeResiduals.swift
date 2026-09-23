// KSP-703: runtime map boxes bypass itable registration. Keep only the
// direct ABI-backed properties and mutation members needed by those boxes.

extension DataFlowSemaPhase {
    func registerSyntheticMapRuntimeResiduals(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let mapFQName = kotlinCollectionsPkg + [interner.intern("Map")]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else { return }

        let mapKeySymbol = ensureSyntheticMapRuntimeTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mapFQName,
            name: "K"
        )
        let mapValueSymbol = ensureSyntheticMapRuntimeTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mapFQName,
            name: "V"
        )
        types.setNominalTypeParameterSymbols([mapKeySymbol, mapValueSymbol], for: mapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: mapSymbol)

        let keyType = types.make(.typeParam(TypeParamType(symbol: mapKeySymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: mapValueSymbol, nullability: .nonNull)))
        let entrySymbol = symbols.lookup(
            fqName: mapFQName + [interner.intern("Entry")]
        )
        let setSymbol = symbols.lookup(fqName: kotlinCollectionsPkg + [interner.intern("Set")])
        let collectionSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("Collection")]
        )

        if let setSymbol, let entrySymbol {
            let entryType = types.make(.classType(ClassType(
                classSymbol: entrySymbol,
                args: [.out(keyType), .out(valueType)],
                nullability: .nonNull
            )))
            let entriesType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(entryType)],
                nullability: .nonNull
            )))
            registerSyntheticMapProperty(
                symbols: symbols,
                types: types,
                interner: interner,
                owner: mapSymbol,
                ownerFQName: mapFQName,
                name: "entries",
                propertyType: entriesType,
                externalLinkName: "__kk_map_entries"
            )
        }
        if let setSymbol {
            let keysType = types.make(.classType(ClassType(
                classSymbol: setSymbol,
                args: [.out(keyType)],
                nullability: .nonNull
            )))
            registerSyntheticMapProperty(
                symbols: symbols,
                types: types,
                interner: interner,
                owner: mapSymbol,
                ownerFQName: mapFQName,
                name: "keys",
                propertyType: keysType,
                externalLinkName: "__kk_map_keys"
            )
        }
        if let collectionSymbol {
            let valuesType = types.make(.classType(ClassType(
                classSymbol: collectionSymbol,
                args: [.out(valueType)],
                nullability: .nonNull
            )))
            registerSyntheticMapProperty(
                symbols: symbols,
                types: types,
                interner: interner,
                owner: mapSymbol,
                ownerFQName: mapFQName,
                name: "values",
                propertyType: valuesType,
                externalLinkName: "__kk_map_values"
            )
        }
        registerSyntheticMapProperty(
            symbols: symbols,
            types: types,
            interner: interner,
            owner: mapSymbol,
            ownerFQName: mapFQName,
            name: "size",
            propertyType: types.intType,
            externalLinkName: "__kk_map_size"
        )

        let mutableMapFQName = kotlinCollectionsPkg + [interner.intern("MutableMap")]
        guard let mutableMapSymbol = symbols.lookup(fqName: mutableMapFQName) else { return }
        let mutableKeySymbol = ensureSyntheticMapRuntimeTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mutableMapFQName,
            name: "K"
        )
        let mutableValueSymbol = ensureSyntheticMapRuntimeTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mutableMapFQName,
            name: "V"
        )
        types.setNominalTypeParameterSymbols([mutableKeySymbol, mutableValueSymbol], for: mutableMapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .invariant], for: mutableMapSymbol)
        let mutableKeyType = types.make(.typeParam(TypeParamType(symbol: mutableKeySymbol, nullability: .nonNull)))
        let mutableValueType = types.make(.typeParam(TypeParamType(symbol: mutableValueSymbol, nullability: .nonNull)))
        let mutableMapSupertypeArgs: [TypeArg] = [
            .invariant(mutableKeyType),
            .out(mutableValueType),
        ]
        symbols.setDirectSupertypes([mapSymbol], for: mutableMapSymbol)
        types.setNominalDirectSupertypes([mapSymbol], for: mutableMapSymbol)
        symbols.setSupertypeTypeArgs(
            mutableMapSupertypeArgs,
            for: mutableMapSymbol,
            supertype: mapSymbol
        )
        types.setNominalSupertypeTypeArgs(
            mutableMapSupertypeArgs,
            for: mutableMapSymbol,
            supertype: mapSymbol
        )
        let mutableReceiverType = types.make(.classType(ClassType(
            classSymbol: mutableMapSymbol,
            args: [.invariant(mutableKeyType), .invariant(mutableValueType)],
            nullability: .nonNull
        )))
        let mapParameterType = types.make(.classType(ClassType(
            classSymbol: mapSymbol,
            args: [.out(mutableKeyType), .out(mutableValueType)],
            nullability: .nonNull
        )))

        if let mutableSetSymbol = symbols.lookup(
            fqName: kotlinCollectionsPkg + [interner.intern("MutableSet")]
        ),
           let mutableEntrySymbol = symbols.lookup(
               fqName: mutableMapFQName + [interner.intern("MutableEntry")]
           )
        {
            let mutableEntryType = types.make(.classType(ClassType(
                classSymbol: mutableEntrySymbol,
                args: [.invariant(mutableKeyType), .invariant(mutableValueType)],
                nullability: .nonNull
            )))
            let entriesType = types.make(.classType(ClassType(
                classSymbol: mutableSetSymbol,
                args: [.invariant(mutableEntryType)],
                nullability: .nonNull
            )))
            registerSyntheticMapProperty(
                symbols: symbols,
                types: types,
                interner: interner,
                owner: mutableMapSymbol,
                ownerFQName: mutableMapFQName,
                name: "entries",
                propertyType: entriesType,
                externalLinkName: "__kk_map_entries"
            )
        }

        registerSyntheticMapFunction(
            symbols: symbols,
            interner: interner,
            owner: mutableMapSymbol,
            ownerFQName: mutableMapFQName,
            name: "put",
            receiverType: mutableReceiverType,
            parameterTypes: [mutableKeyType, mutableValueType],
            returnType: types.makeNullable(mutableValueType),
            externalLinkName: "__kk_mutable_map_put",
            flags: [.synthetic, .throwingFunction],
            typeParameterSymbols: [mutableKeySymbol, mutableValueSymbol]
        )
        registerSyntheticMapFunction(
            symbols: symbols,
            interner: interner,
            owner: mutableMapSymbol,
            ownerFQName: mutableMapFQName,
            name: "putAll",
            receiverType: mutableReceiverType,
            parameterTypes: [mapParameterType],
            returnType: types.unitType,
            externalLinkName: "__kk_mutable_map_putAll",
            flags: [.synthetic, .throwingFunction],
            typeParameterSymbols: [mutableKeySymbol, mutableValueSymbol]
        )
    }

    private func ensureSyntheticMapRuntimeTypeParameter(
        symbols: SymbolTable,
        interner: StringInterner,
        ownerFQName: [InternedString],
        name: String
    ) -> SymbolID {
        let nameID = interner.intern(name)
        let fqName = ownerFQName + [nameID]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }
        return symbols.define(
            kind: .typeParameter,
            name: nameID,
            fqName: fqName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
    }

    private func registerSyntheticMapProperty(
        symbols: SymbolTable,
        types _: TypeSystem,
        interner: StringInterner,
        owner: SymbolID,
        ownerFQName: [InternedString],
        name: String,
        propertyType: TypeID,
        externalLinkName: String
    ) {
        let nameID = interner.intern(name)
        let fqName = ownerFQName + [nameID]
        let propertySymbol: SymbolID
        if let existing = symbols.lookupAll(fqName: fqName).first(where: { symbolID in
            symbols.symbol(symbolID)?.kind == .property
                && symbols.parentSymbol(for: symbolID) == owner
        }) {
            propertySymbol = existing
        } else {
            propertySymbol = symbols.define(
                kind: .property,
                name: nameID,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
            symbols.setParentSymbol(owner, for: propertySymbol)
        }
        symbols.setPropertyType(propertyType, for: propertySymbol)
        symbols.setExternalLinkName(externalLinkName, for: propertySymbol)
    }

    private func registerSyntheticMapFunction(
        symbols: SymbolTable,
        interner: StringInterner,
        owner: SymbolID,
        ownerFQName: [InternedString],
        name: String,
        receiverType: TypeID,
        parameterTypes: [TypeID],
        returnType: TypeID,
        externalLinkName: String,
        flags: SymbolFlags,
        typeParameterSymbols: [SymbolID]
    ) {
        let nameID = interner.intern(name)
        let fqName = ownerFQName + [nameID]
        if let existing = symbols.lookupAll(fqName: fqName).first(where: { symbolID in
            guard let signature = symbols.functionSignature(for: symbolID) else { return false }
            return symbols.parentSymbol(for: symbolID) == owner
                && signature.parameterTypes == parameterTypes
        }) {
            symbols.setExternalLinkName(externalLinkName, for: existing)
            return
        }
        let memberSymbol = symbols.define(
            kind: .function,
            name: nameID,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: flags
        )
        symbols.setParentSymbol(owner, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: parameterTypes,
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: typeParameterSymbols.count
            ),
            for: memberSymbol
        )
    }
}
