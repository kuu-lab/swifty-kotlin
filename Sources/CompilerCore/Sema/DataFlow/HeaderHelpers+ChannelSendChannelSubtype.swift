extension DataFlowSemaPhase {
    /// The runtime Channel handle implements the bundled SendChannel bridge surface.
    /// Attach this edge after source headers have supplied the interface symbol.
    func registerChannelSendChannelSubtype(
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) {
        let package = ["kotlinx", "coroutines", "channels"].map(interner.intern)
        // KUU-4072: `Channel` is an interface upstream; accept the synthetic
        // shell in either nominal kind so the no-stdlib path still gets the
        // SendChannel edge (the bundled source declaration carries it
        // directly when stdlib source is present).
        guard let channel = symbols.lookupAll(fqName: package + [interner.intern("Channel")]).first(where: {
            let kind = symbols.symbol($0)?.kind
            return (kind == .class || kind == .interface) && symbols.symbol($0)?.flags.contains(.synthetic) == true
        }),
        let sendChannel = symbols.lookupAll(fqName: package + [interner.intern("SendChannel")]).first(where: {
            symbols.symbol($0)?.kind == .interface
        }) else { return }

        let parameter: SymbolID
        if let existing = types.nominalTypeParameterSymbols(for: channel).first {
            parameter = existing
        } else {
            let name = interner.intern("T")
            parameter = symbols.define(
                kind: .typeParameter, name: name,
                fqName: package + [interner.intern("Channel"), name],
                declSite: nil, visibility: .private, flags: [.synthetic]
            )
            symbols.setParentSymbol(channel, for: parameter)
            types.setNominalTypeParameterSymbols([parameter], for: channel)
            types.setNominalTypeParameterVariances([.invariant], for: channel)
        }
        let elementType = types.make(.typeParam(TypeParamType(symbol: parameter, nullability: .nonNull)))
        let arguments: [TypeArg] = [.invariant(elementType)]
        let supertypes = symbols.directSupertypes(for: channel)
        if !supertypes.contains(sendChannel) {
            symbols.setDirectSupertypes(supertypes + [sendChannel], for: channel)
        }
        let nominalSupertypes = types.directNominalSupertypes(for: channel)
        if !nominalSupertypes.contains(sendChannel) {
            types.setNominalDirectSupertypes(nominalSupertypes + [sendChannel], for: channel)
        }
        symbols.setSupertypeTypeArgs(arguments, for: channel, supertype: sendChannel)
        types.setNominalSupertypeTypeArgs(arguments, for: channel, supertype: sendChannel)
    }
}
