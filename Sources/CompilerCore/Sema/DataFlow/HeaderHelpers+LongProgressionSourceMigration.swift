extension DataFlowSemaPhase {
    private static let bundledLongProgressionSourcePath =
        "__bundled_kotlin/ranges/LongProgression/LongProgression.kt"

    func reusableSyntheticLongProgressionSourceCompanionSymbol(
        fqName: [InternedString],
        sourceFileID: FileID,
        ownerSymbol: SymbolID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard ctx.sourceManager.path(of: sourceFileID) == Self.bundledLongProgressionSourcePath
        else {
            return nil
        }
        guard fqName == ["kotlin", "ranges", "LongProgression", "Companion"].map(interner.intern),
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
