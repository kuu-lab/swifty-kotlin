extension SymbolTable {
    func enumOwnerSymbol(for entrySymbol: SemanticSymbol) -> SymbolID? {
        guard entrySymbol.kind == .field,
              delegateProperty(forStorageSymbol: entrySymbol.id) == nil,
              entrySymbol.fqName.count >= 2
        else {
            return nil
        }
        if let parent = parentSymbolIfKnown(for: entrySymbol.id) {
            guard let owner = symbol(parent),
                  owner.kind == .enumClass,
                  Array(entrySymbol.fqName.dropLast()) == owner.fqName
            else {
                return nil
            }
            return parent
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbol(symbolID)?.kind == .enumClass
        })
    }
}
