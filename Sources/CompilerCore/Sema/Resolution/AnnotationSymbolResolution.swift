/// Resolves declaration annotations using their source file imports and package.
func resolveAnnotationSymbol(
    named rawName: String,
    in file: ASTFile,
    symbols: SymbolTable,
    interner: StringInterner,
    types: TypeSystem? = nil,
    enclosingFQName: [InternedString] = []
) -> SymbolID? {
    let parts = rawName.split(separator: ".").map(String.init)

    func annotationClass(at path: [InternedString]) -> SymbolID? {
        guard var symbol = symbols.lookup(fqName: path) else { return nil }
        var visited: Set<SymbolID> = []
        while symbols.symbol(symbol)?.kind == .typeAlias {
            guard visited.insert(symbol).inserted, let types,
                  let underlying = symbols.typeAliasUnderlyingType(for: symbol),
                  case let .classType(classType) = types.kind(of: underlying) else { return nil }
            symbol = classType.classSymbol
        }
        return symbols.symbol(symbol)?.kind == .annotationClass ? symbol : nil
    }

    if parts.count > 1 {
        let fqName = parts.map { interner.intern($0) }
        var owner = enclosingFQName
        while owner.count > file.packageFQName.count {
            if let symbol = annotationClass(at: owner + fqName) { return symbol }
            owner.removeLast()
        }
        let root = fqName[0]
        for imported in file.imports where !imported.isWildcard {
            if (imported.alias ?? imported.path.last) == root,
               let symbol = annotationClass(at: imported.path + fqName.dropFirst()) {
                return symbol
            }
        }
        if let symbol = annotationClass(at: file.packageFQName + fqName) { return symbol }
        for imported in file.imports where imported.isWildcard {
            if let symbol = annotationClass(at: imported.path + fqName) { return symbol }
        }
        if let symbol = annotationClass(at: fqName) { return symbol }
        // A qualified annotation name must not fall back to an unrelated
        // annotation with the same last component.
        return nil
    }

    let shortName = interner.intern(parts.last ?? rawName)

    // Classifier members in lexical class scopes precede file imports.
    var owner = enclosingFQName
    while owner.count > file.packageFQName.count {
        if let symbol = annotationClass(at: owner + [shortName]) { return symbol }
        owner.removeLast()
    }

    // Kotlin ranks explicit (single-type and alias) imports above same-package
    // declarations in the classifier namespace, so they are checked first
    // (KUU-1423).
    for importDecl in file.imports where !importDecl.isWildcard {
        if let alias = importDecl.alias, alias == shortName {
            if let symbol = annotationClass(at: importDecl.path) {
                return symbol
            }
        }
        if importDecl.alias == nil, importDecl.path.last == shortName {
            if let symbol = annotationClass(at: importDecl.path) {
                return symbol
            }
        }
    }

    let samePackageFQName = file.packageFQName + [shortName]
    if let symbol = annotationClass(at: samePackageFQName) { return symbol }

    for importDecl in file.imports {
        if let alias = importDecl.alias, alias == shortName {
            if let symbol = annotationClass(at: importDecl.path) {
                return symbol
            }
        }

        if importDecl.alias == nil, importDecl.path.last == shortName {
            if let symbol = annotationClass(at: importDecl.path) {
                return symbol
            }
        }

        // Non-wildcard imports whose path names a declaration (a class may
        // share a synthetic package record's FQ name) do not expose the
        // declaration's neighbours as bare annotation names (KUU-1205).
        if symbols.importPathContributesMembers(importDecl.path, isWildcard: importDecl.isWildcard) {
            if let child = annotationClass(at: importDecl.path + [shortName]) { return child }
        }
    }

    return symbols.lookupByShortName(shortName).first(where: { symbols.symbol($0)?.kind == .annotationClass })
}
