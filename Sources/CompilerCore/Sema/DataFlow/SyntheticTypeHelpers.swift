import Foundation

/// Build a non-nullable class type for a synthetic symbol that has no
/// generic arguments. Equivalent to writing
/// `types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))`
/// but shorter at the dozens of call sites that need this idiom.
func nominalType(_ symbol: SymbolID, types: TypeSystem) -> TypeID {
    types.make(.classType(ClassType(
        classSymbol: symbol,
        args: [],
        nullability: .nonNull
    )))
}
