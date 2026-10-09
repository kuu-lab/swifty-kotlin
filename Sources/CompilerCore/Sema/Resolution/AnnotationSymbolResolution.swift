/// Resolves declaration annotations using their source file imports and package.
func resolveAnnotationSymbol(
    named rawName: String,
    in file: ASTFile,
    symbols: SymbolTable,
    interner: StringInterner,
    enclosingSymbol: SymbolID? = nil,
    allowGlobalShortNameFallback: Bool = true
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

    if parts.count == 1 {
        var owner = enclosingSymbol
        var visited: Set<SymbolID> = []
        while let current = owner, visited.insert(current).inserted,
              let info = symbols.symbol(current), info.kind != .package {
            if let annotation = symbols.lookupAll(fqName: info.fqName + [shortName]).first(where: {
                symbols.symbol($0)?.kind == .annotationClass
            }) { return annotation }
            owner = symbols.parentSymbol(for: current)
        }
    }

    // Kotlin ranks explicit (single-type and alias) imports above same-package
    // declarations in the classifier namespace, so they are checked first
    // (KUU-1423).
    for importDecl in file.imports where !importDecl.isWildcard {
        if let alias = importDecl.alias, alias == shortName {
            if let symbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }
        if importDecl.alias == nil, importDecl.path.last == shortName {
            if let symbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }
    }

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

        if importDecl.alias == nil, importDecl.path.last == shortName {
            if let symbol = symbols.lookup(fqName: importDecl.path),
               symbols.symbol(symbol)?.kind == .annotationClass
            {
                return symbol
            }
        }

        // Non-wildcard imports whose path names a declaration (a class may
        // share a synthetic package record's FQ name) do not expose the
        // declaration's neighbours as bare annotation names (KUU-1205).
        if importDecl.alias == nil, symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
            if let child = symbols.children(ofFQName: importDecl.path).compactMap({ symbols.symbol($0) }).first(where: { $0.kind == .annotationClass && $0.name == shortName }) {
                return child.id
            }
        }
    }

    guard allowGlobalShortNameFallback else { return nil }
    return symbols.lookupByShortName(shortName).first(where: { symbols.symbol($0)?.kind == .annotationClass })
}
