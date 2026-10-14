extension CallTypeChecker {
    /// Unsigned random APIs are package extensions outside Kotlin's default imports.
    /// Global short-name recovery must preserve the importing file's alias and scope.
    func isUnsignedRandomExtensionVisible(
        _ symbol: SemanticSymbol,
        named calleeName: InternedString,
        ctx: TypeInferenceContext
    ) -> Bool {
        let interner = ctx.interner
        let package = ["kotlin", "random"].map(interner.intern)
        guard Array(symbol.fqName.dropLast()) == package,
              ["nextUInt", "nextULong"].map(interner.intern).contains(symbol.name)
        else { return true }
        guard let file = ctx.currentASTFile else { return false }
        if file.packageFQName == package { return true }
        return file.imports.contains { importDecl in
            if importDecl.path == package, importDecl.alias == nil { return true }
            return !importDecl.isWildcard && importDecl.path == symbol.fqName
                && (importDecl.alias ?? symbol.name) == calleeName
        }
    }
}
