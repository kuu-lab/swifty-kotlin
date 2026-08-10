
extension CallLowerer {
    func lowerRepeatCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard args.count == 2,
              isBundledRepeatCall(exprID, sema: sema, interner: interner)
        else {
            return nil
        }

        let intType = sema.types.intType
        let boolType = sema.types.booleanType
        let unitType = sema.types.unitType
        let lessThanCallee = interner.intern("kk_op_lt")
        let addCallee = interner.intern("kk_op_add")
        let unboxIntCallee = ABILoweringPass.primitiveUnboxingCallee(for: .int, interner: interner)

        let countExpr = driver.lowerExpr(
            args[0].expr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let indexExpr = arena.appendTemporary(type: intType)
        let oneExpr = arena.appendExpr(.intLiteral(1), type: intType)
        let falseExpr = arena.appendExpr(.boolLiteral(false), type: boolType)
        instructions.append(.constValue(result: indexExpr, value: .intLiteral(0)))
        instructions.append(.constValue(result: oneExpr, value: .intLiteral(1)))
        instructions.append(.constValue(result: falseExpr, value: .boolLiteral(false)))

        let conditionLabel = driver.ctx.makeLoopLabel()
        let exitLabel = driver.ctx.makeLoopLabel()
        instructions.append(.label(conditionLabel))

        let conditionExpr = arena.appendTemporary(type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: lessThanCallee,
            arguments: [indexExpr, countExpr],
            result: conditionExpr,
            canThrow: true,
            thrownResult: nil
        ))
        instructions.append(.jumpIfEqual(lhs: conditionExpr, rhs: falseExpr, target: exitLabel))

        if let actionExprNode = ast.arena.expr(args[1].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            // Inline repeat's lambda body so suspend calls inside the loop body
            // stay in the enclosing suspend function and can be coroutine-lowered.
            let lambdaParamSymbol = driver.lambdaLowerer.syntheticLambdaParamSymbol(
                lambdaExprID: args[1].expr,
                paramIndex: 0
            )
            let previousLocalValue = driver.ctx.localValue(for: lambdaParamSymbol)
            driver.ctx.setLocalValue(indexExpr, for: lambdaParamSymbol)
            _ = driver.lowerExpr(
                bodyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let previousLocalValue {
                driver.ctx.setLocalValue(previousLocalValue, for: lambdaParamSymbol)
            } else {
                driver.ctx.clearLocalValue(for: lambdaParamSymbol)
            }
        } else {
            let actionExpr = driver.lowerExpr(
                args[1].expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let actionResult = arena.appendTemporary(type: unitType)
                instructions.append(.call(
                    symbol: callableInfo.symbol,
                    callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments + [indexExpr],
                    result: actionResult,
                    canThrow: false,
                    thrownResult: nil
                ))
            }
        }

        let nextIndexBoxedExpr = arena.appendTemporary(type: intType)
        instructions.append(.call(
            symbol: nil,
            callee: addCallee,
            arguments: [indexExpr, oneExpr],
            result: nextIndexBoxedExpr,
            canThrow: true,
            thrownResult: nil
        ))
        let nextIndexExpr = emitNonThrowingCall(
            callee: unboxIntCallee,
            arg: nextIndexBoxedExpr,
            resultType: intType,
            arena: arena,
            into: &instructions
        )
        instructions.append(.copy(from: nextIndexExpr, to: indexExpr))
        instructions.append(.jump(conditionLabel))
        instructions.append(.label(exitLabel))

        let unitExpr = arena.appendExpr(.unit, type: unitType)
        instructions.append(.constValue(result: unitExpr, value: .unit))
        return unitExpr
    }

    /// KSP-604: `repeat` is declared in bundled Kotlin (`Stdlib/kotlin/Standard.kt`),
    /// so the call is identified by the resolved callee symbol instead of a name or a
    /// synthetic-stub marker. A user-defined `repeat` resolves elsewhere and is lowered
    /// as a normal call.
    private func isBundledRepeatCall(
        _ exprID: ExprID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let chosenCallee = sema.bindings.callBinding(for: exprID)?.chosenCallee,
              let repeatSymbol = sema.symbols.lookup(fqName: [
                  interner.intern("kotlin"),
                  interner.intern("repeat"),
              ])
        else {
            return false
        }
        return chosenCallee == repeatSymbol
    }

    func lowerMeasureTimeMillisCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureTimeMillis,
              args.count == 1
        else {
            return nil
        }

        let longType = sema.types.longType
        let currentTimeCallee = interner.intern("kk_system_currentTimeMillis")
        let subCallee = interner.intern("kk_op_sub")

        let startTimeExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: currentTimeCallee, arguments: [],
            result: startTimeExpr, canThrow: false, thrownResult: nil
        ))

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let unitType = sema.types.unitType
                let actionResult = arena.appendTemporary(type: unitType)
                let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType
                )
                instructions.append(.call(
                    symbol: callableInfo.symbol, callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments,
                    result: actionResult, canThrow: true, thrownResult: thrownResult
                ))
                // Propagate exceptions thrown by callable references instead
                // of continuing to measure an incomplete block.
                let rethrowLabel = driver.ctx.makeLoopLabel()
                let continueLabel = driver.ctx.makeLoopLabel()
                instructions.append(.jumpIfNotNull(value: thrownResult, target: rethrowLabel))
                instructions.append(.jump(continueLabel))
                instructions.append(.label(rethrowLabel))
                instructions.append(.rethrow(value: thrownResult))
                instructions.append(.label(continueLabel))
            } else {
                // The sema phase guarantees the argument is a callable (lambda or
                // callable reference) when .measureTimeMillis is marked. A nil
                // callableValueInfo here indicates an internal invariant violation.
                assertionFailure("lowerMeasureTimeMillisCallExpr: callableValueInfo is nil for block argument — sema/KIR invariant violated")
            }
        }

        let endTimeExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: currentTimeCallee, arguments: [],
            result: endTimeExpr, canThrow: false, thrownResult: nil
        ))

        let resultExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: subCallee, arguments: [endTimeExpr, startTimeExpr],
            result: resultExpr, canThrow: false, thrownResult: nil
        ))

        return resultExpr
    }

    func lowerMeasureNanoTimeCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureNanoTime,
              args.count == 1
        else {
            return nil
        }

        let longType = sema.types.longType
        let nanoTimeCallee = interner.intern("kk_system_nanoTime")
        let subCallee = interner.intern("kk_op_sub")

        let startTimeExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: nanoTimeCallee, arguments: [],
            result: startTimeExpr, canThrow: false, thrownResult: nil
        ))

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let unitType = sema.types.unitType
                let actionResult = arena.appendTemporary(type: unitType)
                let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType
                )
                instructions.append(.call(
                    symbol: callableInfo.symbol, callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments,
                    result: actionResult, canThrow: true, thrownResult: thrownResult
                ))
            } else {
                // The sema phase guarantees the argument is a callable (lambda or
                // callable reference) when .measureNanoTime is marked. A nil
                // callableValueInfo here indicates an internal invariant violation.
                assertionFailure("lowerMeasureNanoTimeCallExpr: callableValueInfo is nil for block argument — sema/KIR invariant violated")
            }
        }

        let endTimeExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: nanoTimeCallee, arguments: [],
            result: endTimeExpr, canThrow: false, thrownResult: nil
        ))

        let resultExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: subCallee, arguments: [endTimeExpr, startTimeExpr],
            result: resultExpr, canThrow: false, thrownResult: nil
        ))

        return resultExpr
    }

    func lowerMeasureTimeMicrosCallExpr(
        _ exprID: ExprID,
        args: [CallArgument],
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID? {
        guard sema.bindings.stdlibSpecialCallKind(for: exprID) == .measureTimeMicros,
              args.count == 1
        else {
            return nil
        }

        let longType = sema.types.longType
        let microTimeCallee = interner.intern("kk_system_getTimeMicros")
        let subCallee = interner.intern("kk_op_sub")

        let startTimeExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: microTimeCallee, arguments: [],
            result: startTimeExpr, canThrow: false, thrownResult: nil
        ))

        if let actionExprNode = ast.arena.expr(args[0].expr),
           case let .lambdaLiteral(_, bodyExpr, _, _) = actionExprNode
        {
            _ = driver.lowerExpr(
                bodyExpr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        } else {
            let actionExpr = driver.lowerExpr(
                args[0].expr, ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            if let callableInfo = driver.ctx.callableValueInfo(for: actionExpr) {
                let unitType = sema.types.unitType
                let actionResult = arena.appendTemporary(type: unitType)
                let thrownResult = arena.appendTemporary(type: sema.types.nullableAnyType
                )
                instructions.append(.call(
                    symbol: callableInfo.symbol, callee: callableInfo.callee,
                    arguments: callableInfo.captureArguments,
                    result: actionResult, canThrow: true, thrownResult: thrownResult
                ))
            } else {
                // The sema phase guarantees the argument is a callable (lambda or
                // callable reference) when .measureTimeMicros is marked. A nil
                // callableValueInfo here indicates an internal invariant violation.
                assertionFailure("lowerMeasureTimeMicrosCallExpr: callableValueInfo is nil for block argument — sema/KIR invariant violated")
            }
        }

        let endTimeExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: microTimeCallee, arguments: [],
            result: endTimeExpr, canThrow: false, thrownResult: nil
        ))

        let resultExpr = arena.appendTemporary(type: longType)
        instructions.append(.call(
            symbol: nil, callee: subCallee, arguments: [endTimeExpr, startTimeExpr],
            result: resultExpr, canThrow: false, thrownResult: nil
        ))

        return resultExpr
    }
}
