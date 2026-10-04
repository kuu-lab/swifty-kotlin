extension DataFlowSemaPhase {
    private static let bundledCharProgressionSourcePath =
        "__bundled_kotlin/ranges/CharProgression/CharProgression.kt"

    /// Reuse the existing runtime-backed Companion for the source declaration.
    func reusableSyntheticCharProgressionSourceCompanionSymbol(
        fqName: [InternedString],
        sourceFileID: FileID,
        ownerSymbol: SymbolID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard ctx.sourceManager.path(of: sourceFileID) == Self.bundledCharProgressionSourcePath
        else {
            return nil
        }
        guard fqName == ["kotlin", "ranges", "CharProgression", "Companion"].map(interner.intern),
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
}
