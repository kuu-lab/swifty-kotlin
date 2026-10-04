/// If the symbol being read is a lateinit property, wrap the load with a
/// `kk_lateinit_get_or_throw` call so an `UninitializedPropertyAccessException`
/// is raised when the underlying storage is still the sentinel.
///
/// Shared between `ExprLowerer` (for stored-property reads) and
/// `CallLowerer` (for member-access reads). Both callers used the same
/// implementation; this file is the single source of truth.
func wrapLateinitReadIfNeeded(
    _ valueExpr: KIRExprID,
    symbol: SymbolID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    guard let symbolInfo = sema.symbols.symbol(symbol),
          symbolInfo.flags.contains(.lateinitProperty)
    else {
        return valueExpr
    }
    let propertyNameExpr = arena.appendExpr(
        .stringLiteral(symbolInfo.name),
        type: sema.types.stringType
    )
    instructions.append(.constValue(result: propertyNameExpr, value: .stringLiteral(symbolInfo.name)))
    let result = arena.appendTemporary(type: arena.exprType(valueExpr) ?? sema.types.anyType
    )
    // `thrownResult: nil` routes the exception through the ordinary
    // propagation path (enclosing `try` or the caller). A dedicated thrown
    // temporary would store the exception into a slot nothing inspects, so
    // reads outside a `try` silently yielded the sentinel as `null`.
    instructions.append(.call(
        symbol: nil,
        callee: interner.intern("kk_lateinit_get_or_throw"),
        arguments: [valueExpr, propertyNameExpr],
        result: result,
        canThrow: true,
        thrownResult: nil
    ))
    return result
}
