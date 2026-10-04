func resolveClassTypeSymbol(
    _ type: TypeID,
    sema: SemaModule
) -> (classType: ClassType, symbol: SemanticSymbol)? {
    let nonNullType = sema.types.makeNonNullable(type)
    guard case let .classType(classType) = sema.types.kind(of: nonNullType),
          let symbol = sema.symbols.symbol(classType.classSymbol)
    else {
        return nil
    }
    return (classType, symbol)
}

func resolveClassType(
    _ type: TypeID,
    sema: SemaModule
) -> ClassType? {
    let nonNullType = sema.types.makeNonNullable(type)
    guard case let .classType(classType) = sema.types.kind(of: nonNullType) else {
        return nil
    }
    return classType
}
