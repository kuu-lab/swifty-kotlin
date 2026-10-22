
extension DataFlowSemaPhase {
    func appendSyntheticMetadataAnnotations(
        _ records: [MetadataAnnotationRecord],
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
        // KUU-2673: reading annotations of an imported shell decodes it;
        // re-run once it materializes instead.
        if symbols.deferUntilAfterImportedShellMaterializes(symbol, work: { [self] in
            appendSyntheticMetadataAnnotations(records, to: symbol, symbols: symbols)
        }) {
            return
        }
        let current = symbols.annotations(for: symbol)
        let missing = records.filter { !current.contains($0) }
        guard !missing.isEmpty else {
            return
        }
        symbols.setAnnotations(current + missing, for: symbol)
    }
}
