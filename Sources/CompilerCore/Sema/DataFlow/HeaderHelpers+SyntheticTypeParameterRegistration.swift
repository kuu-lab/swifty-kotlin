extension DataFlowSemaPhase {
    func ensureSyntheticTypeParameterSymbol(
        named name: String,
        in ownerFQName: [InternedString],
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID {
        let internedName = interner.intern(name)
        let fqName = ownerFQName + [internedName]
        if let existing = symbols.lookup(fqName: fqName) {
            return existing
        }

        return symbols.define(
            kind: .typeParameter,
            name: internedName,
            fqName: fqName,
            declSite: nil,
            visibility: .private,
            flags: []
        )
    }
}
