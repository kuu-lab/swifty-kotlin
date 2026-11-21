
extension DataFlowSemaPhase {
    func appendSyntheticMetadataAnnotations(
        _ records: [MetadataAnnotationRecord],
        to symbol: SymbolID,
        symbols: SymbolTable
    ) {
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
