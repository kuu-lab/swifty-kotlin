extension SymbolTable {
    func enumOwnerSymbol(for entrySymbol: SemanticSymbol) -> SymbolID? {
        guard entrySymbol.kind == .field,
              entrySymbol.fqName.count >= 2
        else {
            return nil
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbol(symbolID)?.kind == .enumClass
        })
    }
}
