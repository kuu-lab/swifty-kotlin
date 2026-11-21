
func nominalType(_ symbol: SymbolID, types: TypeSystem) -> TypeID {
    types.make(.classType(ClassType(
        classSymbol: symbol,
        args: [],
        nullability: .nonNull
    )))
}
