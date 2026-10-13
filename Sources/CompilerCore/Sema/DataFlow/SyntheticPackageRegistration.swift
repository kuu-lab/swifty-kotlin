func ensureSyntheticPackageHierarchy(
    fqName path: [InternedString],
    symbols: SymbolTable
) -> [InternedString] {
    guard !path.isEmpty else { return path }
    var fqName: [InternedString] = []
    for part in path {
        fqName.append(part)
        if symbols.lookup(fqName: fqName) == nil {
            _ = symbols.define(
                kind: .package,
                name: part,
                fqName: fqName,
                declSite: nil,
                visibility: .public,
                flags: [.synthetic]
            )
        }
    }
    return fqName
}
