/// Returns the existing symbol for `pkg.name` if one was already registered,
/// otherwise defines a fresh synthetic `kind: .object` symbol there and
/// returns it.
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
