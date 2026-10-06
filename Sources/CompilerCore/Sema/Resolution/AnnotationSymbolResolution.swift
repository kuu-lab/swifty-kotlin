/// Resolves declaration annotations using their source file imports and package.
func resolveAnnotationSymbol(
    named rawName: String,
    in file: ASTFile,
    symbols: SymbolTable,
    interner: StringInterner
) -> SymbolID? {
    let parts = rawName.split(separator: ".").map(String.init)

    if parts.count > 1 {
        let fqName = parts.map { interner.intern($0) }
        if let symbol = symbols.lookup(fqName: fqName),
           symbols.symbol(symbol)?.kind == .annotationClass
        {
            return symbol
        }
    }

    let shortName = interner.intern(parts.last ?? rawName)
    let samePackageFQName = file.packageFQName + [shortName]
    if let symbol = symbols.lookup(fqName: samePackageFQName),
       symbols.symbol(symbol)?.kind == .annotationClass
    {
        return symbol
    }

    for importDecl in file.imports {
        if let alias = importDecl.alias, alias == shortName {
            if let symbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }

        if importDecl.path.last == shortName {
            if let symbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }

        // Non-wildcard imports whose path names a declaration (a class may
        // share a synthetic package record's FQ name) do not expose the
        // declaration's neighbours as bare annotation names (KUU-1205).
        if symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
            if let child = symbols.children(ofFQName: importDecl.path).compactMap({ symbols.symbol($0) }).first(where: { $0.kind == .annotationClass && $0.name == shortName }) {
                return child.id
            }
        }
    }

    return symbols.lookupByShortName(shortName).first(where: { symbols.symbol($0)?.kind == .annotationClass })
}
