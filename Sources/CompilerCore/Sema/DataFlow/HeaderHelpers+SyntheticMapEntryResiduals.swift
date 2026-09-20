// KSP-703: Map.Entry and MutableMap.MutableEntry remain nominal residuals.
// The current bundled-header pass cannot resolve nested source interfaces while
// collecting the enclosing Map declarations, so only these shells stay here.

extension DataFlowSemaPhase {
    func registerSyntheticMapEntryResiduals(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner,
        kotlinCollectionsPkg: [InternedString]
    ) {
        let mapName = interner.intern("Map")
        let mapFQName = kotlinCollectionsPkg + [mapName]
        guard let mapSymbol = symbols.lookup(fqName: mapFQName) else { return }

        let mapKeySymbol = ensureSyntheticMapEntryTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mapFQName,
            name: "K"
        )
        let mapValueSymbol = ensureSyntheticMapEntryTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mapFQName,
            name: "V"
        )
        types.setNominalTypeParameterSymbols([mapKeySymbol, mapValueSymbol], for: mapSymbol)
        types.setNominalTypeParameterVariances([.invariant, .out], for: mapSymbol)

        let entryName = interner.intern("Entry")
        let entryFQName = mapFQName + [entryName]
        let entrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: entryFQName) {
            entrySymbol = existing
        } else {
            entrySymbol = symbols.define(
                kind: .interface,
                name: entryName,
                fqName: entryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(mapSymbol, for: entrySymbol)
        types.setNominalTypeParameterSymbols([mapKeySymbol, mapValueSymbol], for: entrySymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: entrySymbol)

        let keyType = types.make(.typeParam(TypeParamType(symbol: mapKeySymbol, nullability: .nonNull)))
        let valueType = types.make(.typeParam(TypeParamType(symbol: mapValueSymbol, nullability: .nonNull)))
        let entryReceiverType = types.make(.classType(ClassType(
            classSymbol: entrySymbol,
            args: [.out(keyType), .out(valueType)],
            nullability: .nonNull
        )))

        defineSyntheticMapEntryAccessor(
            symbols: symbols,
            interner: interner,
            entryFQName: entryFQName,
            entrySymbol: entrySymbol,
            receiverType: entryReceiverType,
            name: "key",
            returnType: keyType,
            externalLinkName: "__kk_pair_first",
            typeParameterSymbols: [mapKeySymbol, mapValueSymbol]
        )
        defineSyntheticMapEntryAccessor(
            symbols: symbols,
            interner: interner,
            entryFQName: entryFQName,
            entrySymbol: entrySymbol,
            receiverType: entryReceiverType,
            name: "value",
            returnType: valueType,
            externalLinkName: "__kk_pair_second",
            typeParameterSymbols: [mapKeySymbol, mapValueSymbol]
        )

        let mutableMapName = interner.intern("MutableMap")
        let mutableMapFQName = kotlinCollectionsPkg + [mutableMapName]
        guard let mutableMapSymbol = symbols.lookup(fqName: mutableMapFQName) else { return }

        let mutableEntryName = interner.intern("MutableEntry")
        let mutableEntryFQName = mutableMapFQName + [mutableEntryName]
        let mutableEntrySymbol: SymbolID
        if let existing = symbols.lookup(fqName: mutableEntryFQName) {
            mutableEntrySymbol = existing
        } else {
            mutableEntrySymbol = symbols.define(
                kind: .interface,
                name: mutableEntryName,
                fqName: mutableEntryFQName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
        symbols.setParentSymbol(mutableMapSymbol, for: mutableEntrySymbol)

        let mutableKeySymbol = ensureSyntheticMapEntryTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mutableEntryFQName,
            name: "K"
        )
        let mutableValueSymbol = ensureSyntheticMapEntryTypeParameter(
            symbols: symbols,
            interner: interner,
            ownerFQName: mutableEntryFQName,
            name: "V"
        )
        types.setNominalTypeParameterSymbols([mutableKeySymbol, mutableValueSymbol], for: mutableEntrySymbol)
        types.setNominalTypeParameterVariances([.out, .out], for: mutableEntrySymbol)

        let mutableKeyType = types.make(.typeParam(TypeParamType(symbol: mutableKeySymbol, nullability: .nonNull)))
        let mutableValueType = types.make(.typeParam(TypeParamType(symbol: mutableValueSymbol, nullability: .nonNull)))
        let entryTypeArgs: [TypeArg] = [.out(mutableKeyType), .out(mutableValueType)]
        symbols.setDirectSupertypes([entrySymbol], for: mutableEntrySymbol)
        types.setNominalDirectSupertypes([entrySymbol], for: mutableEntrySymbol)
        symbols.setSupertypeTypeArgs(entryTypeArgs, for: mutableEntrySymbol, supertype: entrySymbol)
        types.setNominalSupertypeTypeArgs(entryTypeArgs, for: mutableEntrySymbol, supertype: entrySymbol)
    }

    private func ensureSyntheticMapEntryTypeParameter(
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

    private func defineSyntheticMapEntryAccessor(
        symbols: SymbolTable,
        interner: StringInterner,
        entryFQName: [InternedString],
        entrySymbol: SymbolID,
        receiverType: TypeID,
        name: String,
        returnType: TypeID,
        externalLinkName: String,
        typeParameterSymbols: [SymbolID]
    ) {
        let nameID = interner.intern(name)
        let fqName = entryFQName + [nameID]
        guard symbols.lookup(fqName: fqName) == nil else { return }
        let memberSymbol = symbols.define(
            kind: .function,
            name: nameID,
            fqName: fqName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
        symbols.setParentSymbol(entrySymbol, for: memberSymbol)
        symbols.setExternalLinkName(externalLinkName, for: memberSymbol)
        symbols.setFunctionSignature(
            FunctionSignature(
                receiverType: receiverType,
                parameterTypes: [],
                returnType: returnType,
                typeParameterSymbols: typeParameterSymbols,
                classTypeParameterCount: typeParameterSymbols.count
            ),
            for: memberSymbol
        )
    }
}
