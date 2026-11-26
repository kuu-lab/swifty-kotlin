func registerSyntheticAnnotationClass(
    named name: String,
    packageFQName: [InternedString],
    packageSymbol: SymbolID,
    symbols: SymbolTable,
    interner: StringInterner
) {
    let className = interner.intern(name)
    let classFQName = packageFQName + [className]
    let classSymbol: SymbolID
    if let existing = symbols.lookup(fqName: classFQName) {
        classSymbol = existing
    } else {
        classSymbol = symbols.define(
            kind: .annotationClass,
            name: className,
            fqName: classFQName,
            declSite: nil,
            visibility: .public,
            flags: [.synthetic]
        )
    }
    if packageSymbol != .invalid {
        symbols.setParentSymbol(packageSymbol, for: classSymbol)
    }
}
