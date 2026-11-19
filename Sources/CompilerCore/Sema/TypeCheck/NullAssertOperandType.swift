/// The non-null declared type a `!!` operand asserts when flow has narrowed
/// the reference to `Nothing?` (a definitely-null value). kotlinc keeps the
/// `!!` expression itself `Nothing`-typed but resolves operators and member
/// accesses on a direct `!!` receiver against this asserted type (KUU-4593).
/// Returns nil when the operand is not a resolvable stable reference or
/// carries no declared type, in which case the operand stays `Nothing`.
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
