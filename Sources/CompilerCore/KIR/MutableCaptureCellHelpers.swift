
func deferredLocalCaptureCellSeedValue(
    for type: TypeID,
    sema: SemaModule,
    arena: KIRArena,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    let kind: KIRExprKind = switch sema.types.kind(of: type) {
    case .unit:
        .unit
    case .primitive(.boolean, _):
        .boolLiteral(false)
    case .primitive(.float, _):
        .floatLiteral(0)
    case .primitive(.double, _):
        .doubleLiteral(0)
    case .primitive, .nothing(.nonNull):
        .intLiteral(0)
    case .nullableUnit, .platformUnit, .nothing(.nullable), .nothing(.platformType), .stringStruct, .classType, .functionType, .typeParam, .any, .intersection, .kClassType:
        .null
    case .error:
        .intLiteral(0)
    }
    let exprID = arena.appendExpr(kind, type: type)
    instructions.append(.constValue(result: exprID, value: kind))
    return exprID
}

@discardableResult
func emitMutableCaptureCellInitialization(
    driver: KIRLoweringDriver,
    symbol: SymbolID,
    currentValue: KIRExprID,
    sema: SemaModule,
    arena: KIRArena,
    interner: StringInterner,
    instructions: inout [KIRInstruction]
) -> KIRExprID {
    let countExpr = arena.appendExpr(.intLiteral(1), type: sema.types.intType)
    instructions.append(.constValue(result: countExpr, value: .intLiteral(1)))

    let cellExpr = arena.appendTemporary(type: sema.types.anyType)
    emitNonThrowingCall(
        callee: interner.intern("kk_array_new"),
        arg: countExpr,
        result: cellExpr,
        into: &instructions
    )

    let zeroExpr = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
    instructions.append(.constValue(result: zeroExpr, value: .intLiteral(0)))

    let setResult = arena.appendTemporary(type: sema.types.anyType)
    instructions.append(.call(
        callee: interner.intern("kk_array_set"),
        arguments: [cellExpr, zeroExpr, currentValue],
        result: setResult,
        canThrow: false
    ))

    driver.ctx.setMutableCaptureCell(cellExpr, for: symbol)
    return cellExpr
}
