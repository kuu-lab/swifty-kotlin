
extension ControlFlowLowerer {
    func lowerWhenExpr(
        _ exprID: ExprID,
        subject: ExprID?,
        branches: [WhenBranch],
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
        var subjectID: KIRExprID?
        if let subject {
            subjectID = driver.lowerExpr(
                subject,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            // The subject variable symbol is bound to the whenExpr ID (not the
            // subject expression ID), because `bindIdentifier` in sema uses the
            // when expression's own ExprID.
            if let loweredSubject = subjectID,
               let subjectSymbol = sema.bindings.identifierSymbols[exprID]
            {
                if ast.arena.whenSubjectTypeRef(for: exprID) != nil,
                   let declaredType = sema.symbols.propertyType(for: subjectSymbol)
                {
                    // Copy into declared storage so ABI lowering applies widening/boxing.
                    let slot = arena.appendTemporary(type: declaredType)
                    instructions.append(.copy(from: loweredSubject, to: slot))
                    subjectID = slot
                    driver.ctx.setLocalDeclaredType(declaredType, for: subjectSymbol)
                    driver.ctx.setLocalValue(slot, for: subjectSymbol)
                    if let callableInfo = driver.ctx.callableValueInfo(for: loweredSubject) {
                        driver.ctx.callableValueInfoByExprID[slot] = callableInfo
                    }
                } else {
                    driver.ctx.setLocalValue(loweredSubject, for: subjectSymbol)
                }
            }
        }
        let endLabel = driver.ctx.makeLoopLabel()
        let result = arena.appendTemporary(type: boundType ?? sema.types.errorType)

        var nextBranchLabels: [Int32] = []
        for _ in branches {
            nextBranchLabels.append(driver.ctx.makeLoopLabel())
        }

        let falseID = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: falseID, value: .boolLiteral(false)))

        // Vacuously true when branches is empty (only else exists).
        var allBranchesTerminated = true
        for (index, branch) in branches.enumerated() {
            if branch.conditions.count > 1 {
                let deduplicatedConditions = deduplicateWhenConditions(
                    branch.conditions, ast: ast, sema: sema, interner: interner
                )
                let bodyLabel: Int32 = driver.ctx.makeLoopLabel()
                // Hoist the true constant outside the loop so it's reused for all non-last conditions.
                let hoistedTrueID = arena.appendExpr(.boolLiteral(true), type: boolType)
                instructions.append(.constValue(result: hoistedTrueID, value: .boolLiteral(true)))

                for (condIdx, conditionExprID) in deduplicatedConditions.enumerated() {
                    let matchesID = lowerWhenConditionMatch(
                        conditionExprID: conditionExprID,
                        subjectExprID: subject,
                        loweredSubjectID: subjectID,
                        falseID: falseID,
                        ast: ast,
                        sema: sema,
                        arena: arena,
                        interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    let isLastCondition = condIdx == deduplicatedConditions.count - 1
                    if isLastCondition {
                        instructions.append(.jumpIfEqual(lhs: matchesID, rhs: falseID, target: nextBranchLabels[index]))
                    } else {
                        instructions.append(.jumpIfEqual(lhs: matchesID, rhs: hoistedTrueID, target: bodyLabel))
                    }
                }

                instructions.append(.label(bodyLabel))
            } else if !branch.conditions.isEmpty {
                let conditionExprID = branch.conditions[0]
                let matchesID = lowerWhenConditionMatch(
                    conditionExprID: conditionExprID,
                    subjectExprID: subject,
                    loweredSubjectID: subjectID,
                    falseID: falseID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                instructions.append(.jumpIfEqual(lhs: matchesID, rhs: falseID, target: nextBranchLabels[index]))
            }

            if let guardExprID = branch.guard_ {
                let guardID = driver.lowerExpr(
                    guardExprID,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                instructions.append(.jumpIfEqual(lhs: guardID, rhs: falseID, target: nextBranchLabels[index]))
            }

            let bodyID = driver.lowerExpr(
                branch.body,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let branchTerminated = isTerminatedExpr(bodyID, arena: arena, sema: sema)
            if !branchTerminated {
                let branchValueID = materializeConditionalCallableValue(
                    sourceExprID: branch.body,
                    value: bodyID,
                    expectedType: boundType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.copy(from: branchValueID, to: result))
                instructions.append(.jump(endLabel))
                allBranchesTerminated = false
            }
            instructions.append(.label(nextBranchLabels[index]))
        }

        var elseTerminated = false
        if let elseExpr {
            let fallbackID = driver.lowerExpr(
                elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            elseTerminated = isTerminatedExpr(fallbackID, arena: arena, sema: sema)
            if !elseTerminated {
                let fallbackValueID = materializeConditionalCallableValue(
                    sourceExprID: elseExpr,
                    value: fallbackID,
                    expectedType: boundType,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    instructions: &instructions
                )
                instructions.append(.copy(from: fallbackValueID, to: result))
            }
        } else {
            let unitVal = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unitVal, value: .unit))
            instructions.append(.copy(from: unitVal, to: result))
        }
        instructions.append(.label(endLabel))
        if allBranchesTerminated, elseTerminated {
            arena.setExprType(sema.types.nothingType, for: result)
        }
        return result
    }

    private func lowerWhenConditionMatch(
        conditionExprID: ExprID,
        subjectExprID: ExprID?,
        loweredSubjectID: KIRExprID?,
        falseID: KIRExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        if let loweredSubjectID,
           let conditionExpr = ast.arena.expr(conditionExprID),
           case let .isCheck(checkedExprID, _, negated, _) = conditionExpr,
           isSameWhenSubjectExpression(checkedExprID, subjectExprID: subjectExprID, sema: sema)
        {
            let intType = sema.types.make(.primitive(.int, .nonNull))
            let typeTokenLiteral: Int64 = if let targetType = sema.bindings.isCheckTargetType(for: conditionExprID) {
                RuntimeTypeCheckToken.encode(
                    type: driver.exprLowerer.runtimeIsCheckTargetType(
                        subjectType: sema.bindings.exprType(for: checkedExprID),
                        targetType: targetType,
                        sema: sema
                    ),
                    sema: sema,
                    interner: interner
                )
            } else {
                RuntimeTypeCheckToken.unknownBase
            }
            let typeToken = arena.appendExpr(.intLiteral(typeTokenLiteral), type: intType)
            instructions.append(.constValue(result: typeToken, value: .intLiteral(typeTokenLiteral)))

            let isResult = arena.appendTemporary(type: boolType)
            instructions.append(.call(
                symbol: nil,
                callee: interner.intern("kk_op_is"),
                arguments: [loweredSubjectID, typeToken],
                result: isResult,
                canThrow: false,
                thrownResult: nil
            ))
            guard negated else {
                return isResult
            }
            let negatedResult = arena.appendTemporary(type: boolType)
            instructions.append(.binary(op: .equal, lhs: isResult, rhs: falseID, result: negatedResult))
            return negatedResult
        }

        // `in a..b -> ...` / `!in a..b -> ...`: unlike a plain value condition
        // (which desugars to `subject == condition`), `in`/`!in` already
        // stands alone as a complete Boolean test against the subject
        // (`.inExpr`/`.notInExpr` embed the subject as their own `lhs`), so
        // its lowered value is the match result directly. Route through
        // `lowerContainsCheck` with the subject's already-lowered value
        // (`loweredSubjectID`) rather than re-lowering the whole condition —
        // that would re-lower `lhsExpr` (the subject) from scratch and
        // re-evaluate a side-effecting subject once per `in`/`!in` branch.
        if let loweredSubjectID,
           let conditionExpr = ast.arena.expr(conditionExprID)
        {
            let inCondition: (lhsExpr: ExprID, rhsExpr: ExprID, negated: Bool)? = switch conditionExpr {
            case let .inExpr(lhsExpr, rhsExpr, _): (lhsExpr, rhsExpr, false)
            case let .notInExpr(lhsExpr, rhsExpr, _): (lhsExpr, rhsExpr, true)
            default: nil
            }
            if let inCondition,
               isSameWhenSubjectExpression(inCondition.lhsExpr, subjectExprID: subjectExprID, sema: sema)
            {
                return driver.exprLowerer.lowerContainsCheck(
                    exprID: conditionExprID,
                    lhsID: loweredSubjectID,
                    lhsExpr: inCondition.lhsExpr,
                    rhsExpr: inCondition.rhsExpr,
                    negated: inCondition.negated,
                    boundType: boolType,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
        }

        let conditionValueID = driver.lowerExpr(
            conditionExprID,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )

        if let loweredSubjectID {
            let matchesID = arena.appendTemporary(type: boolType)
            // `when (e0) { Direction.NORTH -> ... }` desugars to `==`
            // comparisons here, not through lowerBinaryExpr, so it applies
            // the same erased-form normalization (KUU-3027): an
            // `Any`/nullable subject holds the enum's boxed-or-sentinel
            // form, a same-class entry condition compares as a bare ordinal,
            // and a mismatched enum condition is boxed into its canonical
            // entry box so `when (x: Any) { E.A -> }` still matches. A `null`
            // condition leaves both sides untouched, so the subject's own
            // slot meets the null sentinel directly (KUU-2957).
            let (normalizedSubjectID, normalizedConditionID) = normalizeEnumEqualityOperands(
                lhsID: loweredSubjectID,
                lhsType: subjectExprID.flatMap { sema.bindings.exprTypes[$0] },
                rhsID: conditionValueID,
                rhsType: sema.bindings.exprTypes[conditionExprID],
                sema: sema, arena: arena, interner: interner,
                into: &instructions
            )
            instructions.append(.binary(
                op: .equal,
                lhs: normalizedSubjectID,
                rhs: normalizedConditionID,
                result: matchesID
            ))
            return matchesID
        }

        return conditionValueID
    }

    private func isSameWhenSubjectExpression(
        _ checkedExprID: ExprID,
        subjectExprID: ExprID?,
        sema: SemaModule
    ) -> Bool {
        guard let subjectExprID else {
            return false
        }
        if checkedExprID == subjectExprID {
            return true
        }
        guard let checkedSymbolID = sema.bindings.identifierSymbols[checkedExprID],
              let subjectSymbolID = sema.bindings.identifierSymbols[subjectExprID]
        else {
            return false
        }
        return checkedSymbolID == subjectSymbolID
    }
}
