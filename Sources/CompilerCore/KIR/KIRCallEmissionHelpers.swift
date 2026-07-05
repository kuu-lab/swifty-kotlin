@discardableResult
func emitNonThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    resultType: TypeID?,
    arena: KIRArena,
    into instructions: inout [KIRInstruction]
) -> KIRExprID {
    let result = arena.appendTemporary(type: resultType)
    emitNonThrowingCall(
        callee: callee,
        arg: arg,
        result: result,
        into: &instructions
    )
    return result
}

func emitNonThrowingCall(
    callee: InternedString,
    arg: KIRExprID,
    result: KIRExprID,
    into instructions: inout [KIRInstruction]
) {
    instructions.append(.call(
        symbol: nil,
        callee: callee,
        arguments: [arg],
        result: result,
        canThrow: false,
        thrownResult: nil
    ))
}
