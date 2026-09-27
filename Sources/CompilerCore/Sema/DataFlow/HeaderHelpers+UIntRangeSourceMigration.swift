extension DataFlowSemaPhase {
    private static let bundledUIntRangeSourcePath =
        "__bundled_kotlin/ranges/UIntRange/Stdlib.kt"

    /// KSP-1314: Adopt the synthetic Companion created by the unsigned-range
    /// stub when the bundled UIntRange declaration is collected.
    func reusableSyntheticUIntRangeSourceCompanionSymbol(
        fqName: [InternedString],
        sourceFileID: FileID,
        ownerSymbol: SymbolID,
        ctx: CompilationContext,
        symbols: SymbolTable,
        interner: StringInterner
    ) -> SymbolID? {
        guard ctx.sourceManager.path(of: sourceFileID) == Self.bundledUIntRangeSourcePath
        else {
            return nil
        }
        guard fqName == ["kotlin", "ranges", "UIntRange", "Companion"].map(interner.intern),
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
