func makeReflectionArgumentList(
    _ elements: [KIRExprID], sema: SemaModule, arena: KIRArena, interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    let count = arena.appendExpr(.intLiteral(Int64(elements.count)), type: sema.types.intType)
    instructions.append(.constValue(result: count, value: .intLiteral(Int64(elements.count))))
    let array = arena.appendTemporary(type: sema.types.anyType)
    instructions.append(.call(symbol: nil, callee: interner.intern("kk_array_new"), arguments: [count],
                              result: array, canThrow: false, thrownResult: nil))
    for (index, element) in elements.enumerated() {
        let offset = arena.appendExpr(.intLiteral(Int64(index)), type: sema.types.intType)
        instructions.append(.constValue(result: offset, value: .intLiteral(Int64(index))))
        instructions.append(.call(symbol: nil, callee: interner.intern("kk_array_set"), arguments: [array, offset, element],
                                  result: nil, canThrow: false, thrownResult: nil))
    }
    let result = arena.appendTemporary(type: sema.types.anyType)
    instructions.append(.call(symbol: nil, callee: interner.intern("__kk_list_of"), arguments: [array, count],
                              result: result, canThrow: false, thrownResult: nil))
    return result
}
