/// One-line rows for member stubs that share an owner, symbol table and
/// interner. Each row forwards to its family's own registration wrapper, so
/// that wrapper's dedup and overwrite rules apply unchanged; rows run in
/// source order, which keeps SymbolID assignment identical.
struct SyntheticMemberRows {
    let register: (_ name: String, _ externalLinkName: String, _ parameters: [(name: String, type: TypeID)], _ returnType: TypeID) -> Void

    func fn(_ name: String, _ externalLinkName: String, _ parameters: [(name: String, type: TypeID)] = [], ret returnType: TypeID) {
        register(name, externalLinkName, parameters, returnType)
    }
}
