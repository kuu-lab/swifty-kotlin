/// Shared helpers for synthetic range registrations that remain while range
/// progression and unsigned range shells are migrated independently.
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

    func syntheticNominalType(
        named name: String,
        in packageFQName: [InternedString],
        symbols: SymbolTable,
        types: TypeSystem,
        interner: StringInterner
    ) -> TypeID {
        guard let symbol = symbols.lookup(fqName: packageFQName + [interner.intern(name)]) else {
            return types.anyType
        }
        return types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

}
