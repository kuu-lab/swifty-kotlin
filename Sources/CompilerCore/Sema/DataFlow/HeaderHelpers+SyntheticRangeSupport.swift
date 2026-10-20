/// Shared iterator type construction for synthetic collection registrations.
extension DataFlowSemaPhase {
    func syntheticIteratorType(
        elementType: TypeID,
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        let iteratorFQName: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator"),
        ]
        guard let iteratorSymbol = symbols.lookup(fqName: iteratorFQName) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.out(elementType)],
            nullability: .nonNull
        )))
    }
}
