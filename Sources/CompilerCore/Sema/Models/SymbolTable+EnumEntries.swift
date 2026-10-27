extension SymbolTable {
    func enumOwnerSymbol(for entrySymbol: SemanticSymbol) -> SymbolID? {
        guard entrySymbol.kind == .field,
              delegateProperty(forStorageSymbol: entrySymbol.id) == nil,
              entrySymbol.fqName.count >= 2
        else {
            return nil
        }
        // A class-delegation storage field (`enum class E : I by expr`)
        // is a `.field` child of the enum just like an entry is, but it
        // holds the delegate object — not an ordinal — and must not be
        // enumerated by values()/entries or ordinal synthesis.
        func isClassDelegationField(_ owner: SymbolID) -> Bool {
            delegatedInterfaces(forClass: owner).contains {
                classDelegationField(forClass: owner, interface: $0) == entrySymbol.id
            }
        }
        if let parent = parentSymbolIfKnown(for: entrySymbol.id) {
            guard let owner = symbol(parent),
                  owner.kind == .enumClass,
                  Array(entrySymbol.fqName.dropLast()) == owner.fqName,
                  !isClassDelegationField(parent)
            else {
                return nil
            }
            return parent
        }
        let ownerFQName = Array(entrySymbol.fqName.dropLast())
        return lookupAll(fqName: ownerFQName).first(where: { symbolID in
            symbol(symbolID)?.kind == .enumClass && !isClassDelegationField(symbolID)
        })
    }
}
