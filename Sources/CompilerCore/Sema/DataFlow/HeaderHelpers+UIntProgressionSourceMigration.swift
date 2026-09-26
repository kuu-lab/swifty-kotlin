extension DataFlowSemaPhase {
    private static let bundledUIntProgressionSourcePath =
        "__bundled_kotlin/ranges/UIntProgression/UIntProgression.kt"

    /// KSP-1313: Adopt the synthetic Companion created by the progression bootstrap.
    func reusableSyntheticUIntProgressionSourceCompanionSymbol(
        fqName: [InternedString],
        sourceFileID: FileID,
        ownerSymbol: SymbolID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard ctx.sourceManager.path(of: sourceFileID) == Self.bundledUIntProgressionSourcePath
        else {
            return nil
        }
        guard fqName == ["kotlin", "ranges", "UIntProgression", "Companion"].map(interner.intern),
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
