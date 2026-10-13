
extension ControlFlowLowerer {
    func lowerWhileExpr(
        _ id: ExprID,
        conditionExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString? = nil,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(continueLabel))

        let conditionID = driver.lowerExpr(
            conditionExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseID, target: breakLabel))

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()
        instructions.append(.jump(continueLabel))
        instructions.append(.label(breakLabel))

        let resultType = sema.bindings.exprTypes[id] ?? sema.types.unitType
        let unit = arena.appendExpr(.unit, type: resultType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerDoWhileExpr(
        _ id: ExprID,
        bodyExpr: ExprID,
        conditionExpr: ExprID,
        label: InternedString? = nil,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let bodyLabel = driver.ctx.makeLoopLabel()
        let continueLabel = driver.ctx.makeLoopLabel()
        let breakLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(bodyLabel))

        driver.ctx.pushLoopControl(continueLabel: continueLabel, breakLabel: breakLabel, name: label)
        _ = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        _ = driver.ctx.popLoopControl()

        instructions.append(.label(continueLabel))
        let conditionID = driver.lowerExpr(
            conditionExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseID, target: breakLabel))
        instructions.append(.jump(bodyLabel))
        instructions.append(.label(breakLabel))

        let resultType = sema.bindings.exprTypes[id] ?? sema.types.unitType
        let unit = arena.appendExpr(.unit, type: resultType)
        instructions.append(.constValue(result: unit, value: .unit))
        return unit
    }

    func lowerIfExpr(
        _ exprID: ExprID,
        condition: ExprID,
        thenExpr: ExprID,
        elseExpr: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let conditionID = driver.lowerExpr(
            condition,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let elseLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendTemporary(type: boundType ?? sema.types.errorType)
        let falseVal = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseVal, value: .boolLiteral(false)))
        instructions.append(.jumpIfEqual(lhs: conditionID, rhs: falseVal, target: elseLabel))
        let thenID = driver.lowerExpr(
            thenExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let thenTerminated = isTerminatedExpr(thenID, arena: arena, sema: sema)
        if !thenTerminated {
            instructions.append(.copy(from: thenID, to: result))
            instructions.append(.jump(endLabel))
        }
        instructions.append(.label(elseLabel))
        var elseTerminated = false
        if let elseExpr {
            let elseID = driver.lowerExpr(
                elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            elseTerminated = isTerminatedExpr(elseID, arena: arena, sema: sema)
            if !elseTerminated {
                instructions.append(.copy(from: elseID, to: result))
            }
        } else {
            let unitVal = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unitVal, value: .unit))
            instructions.append(.copy(from: unitVal, to: result))
        }
        instructions.append(.label(endLabel))
        // If both branches terminate, propagate Nothing type to the result
        if thenTerminated, elseTerminated {
            arena.setExprType(sema.types.nothingType, for: result)
        }
        return result
    }
}
