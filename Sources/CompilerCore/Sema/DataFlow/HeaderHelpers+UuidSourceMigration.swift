extension DataFlowSemaPhase {
    private static var bundledUuidSourcePath: String {
        "__bundled_kotlin/uuid/Uuid.kt"
    }

    func reusableSyntheticUuidSourceCompanionSymbol(
        fqName: [InternedString],
        sourceFileID: FileID,
        ownerSymbol: SymbolID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard isBundledUuidSource(sourceFileID, ctx: ctx),
              matchesFQName(fqName, ["kotlin", "uuid", "Uuid", "Companion"], interner: interner),
              let companionSymbol = symbols.companionObjectSymbol(for: ownerSymbol),
              let companion = symbols.symbol(companionSymbol),
              companion.kind == .object,
              companion.flags.contains(.synthetic),
              companion.fqName == fqName
        else {
            return nil
        }
        return companionSymbol
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
}
