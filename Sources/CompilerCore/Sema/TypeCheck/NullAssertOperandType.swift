func nullAssertedOperandType(
    _ operandID: ExprID,
    ctx: TypeInferenceContext,
    locals: LocalBindings
) -> TypeID? {
    let sema = ctx.sema
    guard let operandExpr = ctx.ast.arena.expr(operandID) else { return nil }
    let symbol: SymbolID?
    switch operandExpr {
    case let .nameRef(name, _):
        symbol = locals[name]?.symbol ?? sema.bindings.identifierSymbols[operandID]
    default:
        symbol = nil
    }
    guard let symbol, let declaredType = sema.symbols.propertyType(for: symbol) else {
        return nil
    }
    return sema.types.definitelyNonNullForm(of: declaredType)
}
