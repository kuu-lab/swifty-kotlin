extension DataFlowSemaPhase {
    /// Bundled progression sources whose companion object may already exist
    /// as a synthetic symbol, keyed by source path.
    private static let bundledProgressionSourceTypeNames: [String: String] = [
        "__bundled_kotlin/ranges/IntProgression/IntProgression.kt": "IntProgression",
        "__bundled_kotlin/ranges/LongProgression/LongProgression.kt": "LongProgression",
        "__bundled_kotlin/ranges/UIntProgression/Stdlib.kt": "UIntProgression",
        "__bundled_kotlin/ranges/CharProgression/CharProgression.kt": "CharProgression",
    ]

    func reusableSyntheticProgressionSourceCompanionSymbol(
        fqName: [InternedString],
        sourceFileID: FileID,
        ownerSymbol: SymbolID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard let typeName = Self.bundledProgressionSourceTypeNames[ctx.sourceManager.path(of: sourceFileID)]
        else {
            return nil
        }
        guard fqName == ["kotlin", "ranges", typeName, "Companion"].map(interner.intern),
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
