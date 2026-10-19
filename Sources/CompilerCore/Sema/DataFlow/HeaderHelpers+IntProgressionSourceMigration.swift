extension DataFlowSemaPhase {
    private static let bundledIntProgressionSourcePath =
        "__bundled_kotlin/ranges/IntProgression/IntProgression.kt"

    func reusableSyntheticIntProgressionSourceCompanionSymbol(
        fqName: [InternedString],
        sourceFileID: FileID,
        ownerSymbol: SymbolID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard ctx.sourceManager.path(of: sourceFileID) == Self.bundledIntProgressionSourcePath
        else {
            return nil
        }
        guard fqName == ["kotlin", "ranges", "IntProgression", "Companion"].map(interner.intern),
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
