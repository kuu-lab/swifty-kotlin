extension DataFlowSemaPhase {
    func registerSyntheticStringExtensionFunction(
        named name: String,
        externalLinkName: String,
        receiverType: TypeID,
        parameters: [(name: String, type: TypeID, hasDefault: Bool, isVararg: Bool)],
        returnType: TypeID,
        annotations: [MetadataAnnotationRecord] = [],
        flags: SymbolFlags = [.synthetic],
        packageFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        registerSyntheticFunctionStub(
            named: name,
            ownerFQName: packageFQName,
            parentSymbol: symbols.lookup(fqName: packageFQName),
            receiverType: receiverType,
            parameters: parameters,
            returnType: returnType,
            externalLinkName: externalLinkName,
            annotations: annotations,
            flags: flags,
            symbols: symbols,
            interner: interner
        )
    }
}
