extension DataFlowSemaPhase {
    private static let bundledLongProgressionSourcePath =
        "__bundled_kotlin/ranges/LongProgression/Stdlib.kt"

    /// KSP-1305: Adopt the synthetic Companion created by the progression
    /// bootstrap when the bundled LongProgression declaration is collected.
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
