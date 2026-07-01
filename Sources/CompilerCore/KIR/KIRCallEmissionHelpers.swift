@discardableResult
func emitNonThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    resultType: TypeID?,
    arena: KIRArena,
    into instructions: inout [KIRInstruction]
) -> KIRExprID {
    let result = arena.appendExpr(
        .temporary(Int32(arena.expressions.count)),
        type: resultType
    )
    instructions.append(.call(
        symbol: nil,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: false,
        thrownResult: nil
    ))
    return result
}
