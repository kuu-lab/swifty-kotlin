extension BundledDeclarationIndex {
    /// Resolves the nominal owner symbol for a bundled extension receiver.
    ///
    /// `KClass<T>` has a dedicated type representation, so it does not carry
    /// the interface symbol in the type itself. Map it back to the registered
    /// synthetic interface before attaching source-backed extensions.
    static func receiverOwnerSymbol(
        for receiverType: TypeID,
        types: TypeSystem
    ) -> SymbolID? {
        let nonNullType = types.makeNonNullable(receiverType)
        switch types.kind(of: nonNullType) {
        case let .classType(classType):
            return classType.classSymbol
        case .kClassType:
            return types.kClassInterfaceSymbol
        case let .intersection(parts):
            for part in parts {
                if let owner = receiverOwnerSymbol(for: part, types: types) {
                    return owner
                }
            }
            return nil
        default:
            return nil
        }
    }
}
