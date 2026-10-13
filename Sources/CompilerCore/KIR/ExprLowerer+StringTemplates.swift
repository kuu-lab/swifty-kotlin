/// String-template lowering used by `ExprLowerer.lowerExpr`: part
/// lowering, Any-to-String conversion, and flat concatenation.
///
/// Split out from `ExprLowerer+ControlFlowAndBlocks.swift`.
extension ExprLowerer {
    func lowerStringTemplateExpr(
        parts: [StringTemplatePart],
        exprID: ExprID,
        stringType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        var partIDs: [KIRExprID] = []
        for part in parts {
            switch part {
            case let .literal(interned):
                let partID = arena.appendExpr(.stringLiteral(interned), type: stringType)
                instructions.append(.constValue(result: partID, value: .stringLiteral(interned)))
                partIDs.append(partID)
            case let .expression(exprID):
                let lowered = lowerExpr(
                    exprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                // Bodies Sema never visits (a stdlib delegate's callback
                // lambda, for instance) have no bound expression type; the
                // lowered KIR type is the only description of the value and
                // must still drive the string conversion.
                let exprType = sema.bindings.exprTypes[exprID] ?? arena.exprType(lowered)
                if let exprType, exprType != stringType {
                    // See CallLowerer.emitAnyToStringWithNullGuard for why nullable
                    // Float?/Double?/ULong? need an explicit null guard before
                    // kk_any_to_string (their null-sentinel bit pattern coincides
                    // with a legitimate in-range value for those tags).
                    let converted = driver.callLowerer.emitAnyToStringWithNullGuard(
                        valueID: lowered,
                        valueType: exprType,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        instructions: &instructions
                    )
                    partIDs.append(converted)
                } else {
                    partIDs.append(lowered)
                }
            }
        }
        if partIDs.isEmpty {
            let emptyStr = interner.intern("")
            let id = arena.appendExpr(.stringLiteral(emptyStr), type: stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(emptyStr)))
            return id
        }
        var accumulated = partIDs[0]
        for i in 1 ..< partIDs.count {
            let concatResult = arena.appendTemporary(type: stringType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("__kk_string_concat_flat"),
                arguments: [accumulated, partIDs[i]],
                result: concatResult,
                canThrow: false,
                thrownResult: nil
            ))
            accumulated = concatResult
        }
        return accumulated
    }
}
