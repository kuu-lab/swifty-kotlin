func ensureSyntheticObjectSymbol(
    named name: String,
    in pkg: [InternedString],
    symbols: SymbolTable,
    interner: StringInterner
) -> SymbolID {
    let internedName = interner.intern(name)
    let fqName = pkg + [internedName]
    if let existing = symbols.lookup(fqName: fqName) {
        return existing
    }
    return symbols.define(
        kind: .object,
        name: internedName,
        fqName: fqName,
        declSite: nil,
        visibility: .public,
        flags: [.synthetic]
    )
}
