extension DataFlowSemaPhase {
    private static var bundledUuidSourcePath: String {
        "__bundled_kotlin/uuid/Uuid.kt"
    }

    func adoptedSyntheticUuidSourceDeclarationSymbol(
        kind: SymbolKind,
        fqName: [InternedString],
        sourceFileID: FileID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard ctx.sourceManager.path(of: sourceFileID) == Self.bundledUuidSourcePath,
              kind == .class,
              matchesFQName(fqName, ["kotlin", "uuid", "Uuid"], interner: interner)
        else {
            return nil
        }

        return symbols.lookupAll(fqName: fqName).first { symbolID in
            guard let symbol = symbols.symbol(symbolID) else { return false }
            return symbol.kind == .class && symbol.flags.contains(.synthetic)
        }
    }

    func attachUuidSourceMigrationBridgeIfNeeded(
        to symbolID: SymbolID,
        fqName: [InternedString],
        sourceFileID: FileID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard isBundledUuidSource(sourceFileID, ctx: ctx),
              let symbol = symbols.symbol(symbolID),
              symbol.kind == .function,
              !symbol.flags.contains(.synthetic),
              let externalLinkName = uuidSourceMigrationLinkName(for: fqName, interner: interner)
        else {
            return
        }

        symbols.setExternalLinkName(externalLinkName, for: symbolID)
        attachUuidSourceMigrationExperimentalAnnotation(to: symbolID, symbols: symbols)
    }

    func attachUuidSourceMigrationClassAnnotationIfNeeded(
        to symbolID: SymbolID,
        fqName: [InternedString],
        sourceFileID: FileID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) {
        guard isBundledUuidSource(sourceFileID, ctx: ctx),
              matchesFQName(fqName, ["kotlin", "uuid", "Uuid"], interner: interner)
        else {
            return
        }
        attachUuidSourceMigrationExperimentalAnnotation(to: symbolID, symbols: symbols)
    }

    private func uuidSourceMigrationLinkName(
        for fqName: [InternedString],
        interner: StringInterner
    ) -> String? {
        if matchesFQName(fqName, ["kotlin", "uuid", "Uuid", "Companion", "random"], interner: interner) {
            return "kk_uuid_random"
        }
        if matchesFQName(fqName, ["kotlin", "uuid", "Uuid", "Companion", "parse"], interner: interner) {
            return "kk_uuid_parse"
        }
        if matchesFQName(fqName, ["kotlin", "uuid", "Uuid", "toString"], interner: interner) {
            return "kk_uuid_toString"
        }
        if matchesFQName(fqName, ["kotlin", "uuid", "Uuid", "toLongs"], interner: interner) {
            return "kk_uuid_toLongs"
        }
        if matchesFQName(fqName, ["kotlin", "uuid", "Uuid", "toByteArray"], interner: interner) {
            return "kk_uuid_toByteArray"
        }
        return nil
    }

    private func matchesFQName(
        _ fqName: [InternedString],
        _ components: [String],
        interner: StringInterner
    ) -> Bool {
        fqName == components.map { interner.intern($0) }
    }

    private func isBundledUuidSource(_ sourceFileID: FileID, ctx: CompilationContext) -> Bool {
        ctx.sourceManager.path(of: sourceFileID) == Self.bundledUuidSourcePath
    }

    private func attachUuidSourceMigrationExperimentalAnnotation(
        to symbolID: SymbolID,
        symbols: SymbolTable
    ) {
        let record = MetadataAnnotationRecord(annotationFQName: "kotlin.uuid.ExperimentalUuidApi")
        var annotations = symbols.annotations(for: symbolID)
        if !annotations.contains(record) {
            annotations.append(record)
            symbols.setAnnotations(annotations, for: symbolID)
        }
    }
}
