
extension ControlFlowLowerer {
    struct TryCatchClause {
        let parameterType: TypeID
        let bindsParameter: Bool
        let lowerBody: (KIRExprID?, inout [KIRInstruction]) -> KIRExprID
    }

    func lowerTryExpr(
        _ exprID: ExprID,
        bodyExpr: ExprID,
        catchClauses: [CatchClause],
        finallyExpr: ExprID?,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        func lower(_ expr: ExprID, into instructions: inout [KIRInstruction]) -> KIRExprID {
            driver.lowerExpr(
                expr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }

        let catches = catchClauses.map { clause in
            let binding = resolveCatchClauseBinding(clause, ast: ast, sema: sema, interner: interner)
            return TryCatchClause(
                parameterType: binding.parameterType,
                bindsParameter: clause.paramName != nil && binding.parameterSymbol != .invalid
            ) { parameter, instructions in
                let previousValue = self.driver.ctx.localValue(for: binding.parameterSymbol)
                if let parameter {
                    self.driver.ctx.setLocalValue(parameter, for: binding.parameterSymbol)
                }
                defer {
                    if parameter != nil {
                        if let previousValue {
                            self.driver.ctx.setLocalValue(previousValue, for: binding.parameterSymbol)
                        } else {
                            self.driver.ctx.clearLocalValue(for: binding.parameterSymbol)
                        }
                    }
                }
                return lower(clause.body, into: &instructions)
            }
        }

        let finallyDepth = driver.ctx.finallyBlockStack.count
        if let finallyExpr {
            driver.ctx.pushFinallyBlock(finallyExpr)
        }
        defer {
            if finallyExpr != nil {
                driver.ctx.popFinallyBlock()
            }
        }
        let lowerFinally: ((inout [KIRInstruction]) -> Void)? = finallyExpr.map { expr in
            { instructions in
                self.driver.ctx.withFinallyStackDepth(finallyDepth) {
                    _ = lower(expr, into: &instructions)
                }
            }
        }
        return lowerTry(
            resultType: sema.bindings.exprTypes[exprID] ?? sema.types.errorType,
            lowerBody: { lower(bodyExpr, into: &$0) },
            catches: catches,
            lowerFinally: lowerFinally,
            sema: sema, arena: arena, interner: interner,
            instructions: &instructions
        )
    }

    func lowerTry(
        resultType: TypeID,
        lowerBody: (inout [KIRInstruction]) -> KIRExprID,
        catches: [TryCatchClause],
        lowerFinally: ((inout [KIRInstruction]) -> Void)?,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
        let exceptionTypeSlot = arena.appendTemporary(type: intType)
        let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: nullExceptionValue, value: .null))
        instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
        instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
        instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

        let tryResult = arena.appendTemporary(type: resultType)
        let catchDispatchLabel = driver.ctx.makeLoopLabel()
        let finallyLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        let nonLocalReturnLabel = lowerFinally.map { _ in driver.ctx.makeLoopLabel() }
        let nonLocalReturnValue = arena.appendTemporary(type: nil)
        let returningNonLocally = arena.appendTemporary(type: boolType)
        let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
        if let nonLocalReturnLabel {
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
            instructions.append(.copy(from: falseValue, to: returningNonLocally))
            instructions.append(.beginNonLocalReturnScope(value: nonLocalReturnValue, target: nonLocalReturnLabel))
        }

        // Guard routed instructions so an enclosing try cannot intercept a
        // call before this try has handled its exception and run its finally.
        func appendProtected(
            _ lowered: [KIRInstruction],
            thrownTarget: Int32,
            into instructions: inout [KIRInstruction]
        ) {
            instructions.append(.beginFinallyGuard)
            appendThrowAwareInstructions(
                lowered,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: thrownTarget,
                sema: sema, interner: interner, arena: arena,
                instructions: &instructions
            )
            instructions.append(.endFinallyGuard)
        }

        driver.ctx.pushExceptionHandler(
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: catchDispatchLabel
        )
        var bodyInstructions: [KIRInstruction] = []
        let bodyResult = lowerBody(&bodyInstructions)
        appendProtected(bodyInstructions, thrownTarget: catchDispatchLabel, into: &instructions)
        if !isTerminatedExpr(bodyResult, arena: arena, sema: sema) {
            instructions.append(.copy(from: bodyResult, to: tryResult))
            instructions.append(.jump(finallyLabel))
        }

        instructions.append(.label(catchDispatchLabel))
        let catchKinds = catches.map { clause in
            (
                catchAll: isCatchAllType(clause.parameterType, sema: sema, interner: interner),
                cancellation: isCancellationExceptionType(clause.parameterType, sema: sema, interner: interner)
            )
        }
        if nonLocalReturnLabel == nil, catchKinds.contains(where: { !$0.catchAll }) {
            instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))
        }
        let trueValue = arena.appendExpr(.boolLiteral(true), type: boolType)
        if catchKinds.contains(where: { !$0.catchAll && !$0.cancellation }) {
            instructions.append(.constValue(result: trueValue, value: .boolLiteral(true)))
        }

        for (clause, kind) in zip(catches, catchKinds) {
            let nextCatchLabel = driver.ctx.makeLoopLabel()
            if !kind.catchAll {
                let matchResult = arena.appendTemporary(type: boolType)
                if kind.cancellation {
                    emitNonThrowingCall(
                        callee: interner.intern("kk_throwable_is_cancellation"),
                        arg: exceptionSlot,
                        result: matchResult,
                        into: &instructions
                    )
                } else {
                    emitExceptionTypeCheck(
                        catchType: clause.parameterType,
                        exceptionSlot: exceptionSlot,
                        exceptionTypeSlot: exceptionTypeSlot,
                        matchResult: matchResult,
                        unknownTypeToken: zeroTypeToken,
                        trueValue: trueValue,
                        boolType: boolType,
                        intType: intType,
                        sema: sema, interner: interner, arena: arena,
                        instructions: &instructions
                    )
                }
                instructions.append(.jumpIfEqual(lhs: matchResult, rhs: falseValue, target: nextCatchLabel))
            }

            let parameter = clause.bindsParameter ? arena.appendTemporary(type: clause.parameterType) : nil
            if let parameter {
                instructions.append(.copy(from: exceptionSlot, to: parameter))
            }
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

            var catchInstructions: [KIRInstruction] = []
            let catchResult = driver.ctx.withExceptionHandlerTarget(finallyLabel) {
                clause.lowerBody(parameter, &catchInstructions)
            }
            appendProtected(catchInstructions, thrownTarget: finallyLabel, into: &instructions)
            if !isTerminatedExpr(catchResult, arena: arena, sema: sema) {
                instructions.append(.copy(from: catchResult, to: tryResult))
            }
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))
            instructions.append(.jump(finallyLabel))
            instructions.append(.label(nextCatchLabel))
        }
        instructions.append(.jump(finallyLabel))
        driver.ctx.popExceptionHandler()

        if let nonLocalReturnLabel {
            instructions.append(.endNonLocalReturnScope)
            instructions.append(.label(nonLocalReturnLabel))
            instructions.append(.constValue(result: returningNonLocally, value: .boolLiteral(true)))
            instructions.append(.jump(finallyLabel))
        }

        instructions.append(.label(finallyLabel))
        if let lowerFinally {
            var finallyInstructions: [KIRInstruction] = []
            lowerFinally(&finallyInstructions)
            appendFinallyInstructions(
                finallyInstructions, sema: sema, arena: arena, interner: interner,
                into: &instructions
            )
        }
        instructions.append(.jumpIfNotNull(value: exceptionSlot, target: rethrowLabel))
        instructions.append(.jump(endLabel))

        instructions.append(.label(rethrowLabel))
        let cancellationCheckResult = arena.appendTemporary(type: boolType)
        emitNonThrowingCall(
            callee: interner.intern("kk_throwable_is_cancellation"),
            arg: exceptionSlot,
            result: cancellationCheckResult,
            into: &instructions
        )
        instructions.append(.rethrow(value: exceptionSlot))

        instructions.append(.label(endLabel))
        if nonLocalReturnLabel != nil {
            let afterReturnLabel = driver.ctx.makeLoopLabel()
            instructions.append(.jumpIfEqual(lhs: returningNonLocally, rhs: falseValue, target: afterReturnLabel))
            instructions.append(.resumeNonLocalReturn(nonLocalReturnValue))
            instructions.append(.label(afterReturnLabel))
        }
        if resultType == sema.types.nothingType {
            let terminated = arena.appendExpr(.unit, type: resultType)
            instructions.append(.constValue(result: terminated, value: .unit))
            return terminated
        }
        return tryResult
    }

    func appendFinallyInstructions(
        _ lowered: [KIRInstruction],
        outerHandler: KIRLoweringContext.ExceptionHandler? = nil,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        into instructions: inout [KIRInstruction]
    ) {
        guard lowered.contains(where: { instruction in
            switch instruction {
            case .call, .virtualCall, .nullAssert, .rethrow: true
            default: false
            }
        }) else {
            instructions.append(contentsOf: lowered)
            return
        }

        // A successful call in finally must preserve any pending exception.
        let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
        let typeSlot = arena.appendTemporary(type: sema.types.intType)
        let nullValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        let zeroValue = arena.appendExpr(.intLiteral(0), type: sema.types.intType)
        let rethrowLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        instructions.append(.beginFinallyGuard)
        instructions.append(.constValue(result: nullValue, value: .null))
        instructions.append(.constValue(result: zeroValue, value: .intLiteral(0)))
        instructions.append(.copy(from: nullValue, to: exceptionSlot))
        instructions.append(.copy(from: zeroValue, to: typeSlot))
        appendThrowAwareInstructions(
            lowered,
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: typeSlot,
            thrownTarget: rethrowLabel,
            sema: sema, interner: interner, arena: arena,
            instructions: &instructions
        )
        instructions.append(.jump(endLabel))
        instructions.append(.endFinallyGuard)

        // A throw from finally replaces the pending exception or control transfer.
        instructions.append(.label(rethrowLabel))
        if let outerHandler {
            instructions.append(.copy(from: exceptionSlot, to: outerHandler.exceptionSlot))
            instructions.append(.copy(from: zeroValue, to: outerHandler.exceptionTypeSlot))
            instructions.append(.jump(outerHandler.thrownTarget))
        } else {
            instructions.append(.rethrow(value: exceptionSlot))
        }
        instructions.append(.label(endLabel))
    }

    /// This first performs a fast integer comparison against the encoded catch type token.
    /// When the exact token comparison misses, it falls back to `kk_op_is`, because a
    /// known thrown subtype token can still match a catch clause for one of its supertypes.
    /// The runtime fallback also handles UNKNOWN (0) tokens from external/runtime calls.
    ///
    /// Shared boolean/int constants (`unknownTypeToken`, `trueValue`, `falseValue`) are
    /// created once per try/catch block by the caller and passed in to avoid emitting
    /// duplicate `constValue` instructions for each catch clause.
    private func emitExceptionTypeCheck(
        catchType: TypeID,
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        matchResult: KIRExprID,
        unknownTypeToken: KIRExprID,
        trueValue: KIRExprID,
        boolType: TypeID,
        intType: TypeID,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) {
        // Per-catch: only the encoded type token is unique to each clause.
        let encodedToken = RuntimeTypeCheckToken.encode(type: catchType, sema: sema, interner: interner)
        let tokenExpr = arena.appendExpr(.intLiteral(encodedToken), type: intType)
        let typeMatches = arena.appendTemporary(type: boolType)
        let typeUnknown = arena.appendTemporary(type: boolType)

        let exactMatchLabel = driver.ctx.makeLoopLabel()
        let doneLabel = driver.ctx.makeLoopLabel()

        instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))

        instructions.append(.binary(
            op: .equal,
            lhs: exceptionTypeSlot,
            rhs: tokenExpr,
            result: typeMatches
        ))
        instructions.append(.jumpIfEqual(lhs: typeMatches, rhs: trueValue, target: exactMatchLabel))

        // Keep the UNKNOWN comparison explicit for KIR diagnostics and to make
        // external/runtime-call fallback visible in dumps.
        instructions.append(.binary(
            op: .equal,
            lhs: exceptionTypeSlot,
            rhs: unknownTypeToken,
            result: typeUnknown
        ))

        let runtimeResult = arena.appendTemporary(type: boolType)
        instructions.append(.call(callee: interner.intern("kk_op_is"), arguments: [exceptionSlot, tokenExpr], result: runtimeResult, canThrow: false))
        instructions.append(.copy(from: runtimeResult, to: matchResult))
        instructions.append(.jump(doneLabel))

        instructions.append(.label(exactMatchLabel))
        instructions.append(.copy(from: trueValue, to: matchResult))
        instructions.append(.jump(doneLabel))

        instructions.append(.label(doneLabel))
    }

    func appendThrowAwareInstructions(
        _ loweredInstructions: [KIRInstruction],
        exceptionSlot: KIRExprID,
        exceptionTypeSlot: KIRExprID,
        thrownTarget: Int32,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        // Track nested finally-guard depth so that instructions inside
        // an already-wrapped finally region are passed through verbatim,
        // preventing double-wrapping (CODE-001).
        var finallyGuardDepth = 0
        var finallyCleanupDepth = 0
        for instruction in loweredInstructions {
            if case .beginFinallyCleanup = instruction {
                finallyCleanupDepth += 1
                instructions.append(instruction)
                continue
            }
            if case .endFinallyCleanup = instruction {
                finallyCleanupDepth -= 1
                instructions.append(instruction)
                continue
            }
            if case .beginFinallyGuard = instruction {
                finallyGuardDepth += 1
                instructions.append(instruction)
                continue
            }
            if case .endFinallyGuard = instruction {
                finallyGuardDepth -= 1
                instructions.append(instruction)
                continue
            }
            if finallyCleanupDepth > 0, case .rethrow = instruction {
                // An inlined finally already ran as part of leaving its try
                // scope. Let its exception reach the handler selected by the
                // inline-finally lowering instead of a handler being unwound.
                instructions.append(instruction)
                continue
            }
            if finallyGuardDepth > 0 {
                if case let .rethrow(value) = instruction {
                    // A rethrow leaves the guarded local handler. Let the
                    // enclosing try/catch claim it instead of letting the
                    // guard hide it from every outer routing pass.
                    instructions.append(.copy(from: value, to: exceptionSlot))
                    let rethrowType = arena.exprType(value) ?? sema.types.anyType
                    let tokenValue = RuntimeTypeCheckToken.encode(
                        type: rethrowType,
                        sema: sema,
                        interner: interner
                    )
                    let thrownTypeToken = arena.appendExpr(.intLiteral(tokenValue), type: intType)
                    instructions.append(.constValue(result: thrownTypeToken, value: .intLiteral(tokenValue)))
                    instructions.append(.copy(from: thrownTypeToken, to: exceptionTypeSlot))
                    instructions.append(.jump(thrownTarget))
                } else {
                    instructions.append(instruction)
                }
                continue
            }
            switch instruction {
            case let .nullAssert(operand, result):
                // `OperatorLoweringPass` runs after this source-level control-flow
                // lowering. Lower the assertion here as well so its thrown value
                // is routed to the enclosing try/catch exception slot.
                let resultType = arena.exprType(result)
                if let operandType = arena.exprType(operand),
                   nullAssertProbeCannotBeNull(
                       sema.types.kind(of: operandType),
                       types: sema.types,
                       symbols: sema.symbols
                   )
                {
                    // The operand's non-null unboxed representation cannot
                    // encode a null value: the sentinel bit pattern is a
                    // legitimate payload there (`Long.MIN_VALUE`/`-0.0`, or
                    // `V(null)` for a nullable-underlying value class), never
                    // a null reference — probing it throws on valid values,
                    // so the assertion reduces to a copy (KUU-3899).
                    instructions.append(.copy(from: operand, to: result))
                    continue
                }
                let notNullResult = arena.appendTemporary(type: arena.exprType(result))
                if let message = arena.platformNullAssertMessages[result] {
                    let messageExpr = arena.appendExpr(.stringLiteral(message), type: sema.types.intType)
                    instructions.append(.constValue(result: messageExpr, value: .stringLiteral(message)))
                    instructions.append(.call(
                        callee: interner.intern("kk_op_notnull_msg"),
                        arguments: [operand, messageExpr],
                        result: notNullResult,
                        canThrow: true,
                        thrownResult: exceptionSlot
                    ))
                } else {
                    instructions.append(.call(
                        callee: interner.intern("kk_op_notnull"),
                        arguments: [operand],
                        result: notNullResult,
                        canThrow: true,
                        thrownResult: exceptionSlot
                    ))
                }
                let unboxCallee: InternedString? = if let resultType,
                                                       case .primitive(_, .nonNull) = sema.types.kind(of: resultType)
                {
                    BoxingCalleeTable(interner: interner).unboxCallee(
                        for: resultType,
                        types: sema.types,
                        requireNonNull: false
                    )
                } else {
                    nil
                }
                if let unboxCallee {
                    instructions.append(.call(callee: unboxCallee, arguments: [notNullResult], result: result, canThrow: false))
                } else if let resultType,
                          let operandType = arena.exprType(operand),
                          let valueClass = nullableUnderlyingValueClassSymbol(
                              of: sema.types.kind(of: resultType), types: sema.types, symbols: sema.symbols
                          ) ?? referenceBackedValueClassSymbol(
                              of: sema.types.kind(of: resultType), types: sema.types, symbols: sema.symbols
                          ),
                          valueClassUnboxSourceIsBoxed(
                              sema.types.kind(of: operandType), targetClassSymbol: valueClass
                          )
                {
                    // `v!!` narrows a nullable-underlying / reference-backed
                    // value class's `V?`/erased slot (a nominal box) to the raw
                    // `V` payload — the same `V?` -> `V` boundary the
                    // non-throwing path lowers in OperatorLoweringPass
                    // (KUU-3115/KUU-4086).
                    emitValueClassUnboxCall(
                        value: notNullResult, classSymbol: valueClass, result: result,
                        types: sema.types, symbols: sema.symbols, interner: interner,
                        arena: arena, into: &instructions
                    )
                } else {
                    instructions.append(.copy(from: notNullResult, to: result))
                }
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .call(symbol, callee, arguments, result, _, thrownResult, isSuperCall, qualifiedSuperType)
                where thrownResult == nil:
                instructions.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    canThrow: true,
                    thrownResult: exceptionSlot,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .call(symbol, callee, arguments, result, canThrow, thrownResult?, isSuperCall, qualifiedSuperType):
                instructions.append(.call(
                    symbol: symbol,
                    callee: callee,
                    arguments: arguments,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    isSuperCall: isSuperCall,
                    qualifiedSuperType: qualifiedSuperType
                ))
                if thrownResult != exceptionSlot {
                    instructions.append(.copy(from: thrownResult, to: exceptionSlot))
                }
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .virtualCall(symbol, callee, receiver, arguments, result, _, thrownResult, dispatch)
                where thrownResult == nil:
                instructions.append(.virtualCall(
                    symbol: symbol,
                    callee: callee,
                    receiver: receiver,
                    arguments: arguments,
                    result: result,
                    canThrow: true,
                    thrownResult: exceptionSlot,
                    dispatch: dispatch
                ))
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .virtualCall(symbol, callee, receiver, arguments, result, canThrow, thrownResult?, dispatch):
                instructions.append(.virtualCall(
                    symbol: symbol,
                    callee: callee,
                    receiver: receiver,
                    arguments: arguments,
                    result: result,
                    canThrow: canThrow,
                    thrownResult: thrownResult,
                    dispatch: dispatch
                ))
                if thrownResult != exceptionSlot {
                    instructions.append(.copy(from: thrownResult, to: exceptionSlot))
                }
                let unknownTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: unknownTypeToken, value: .intLiteral(0)))
                instructions.append(.copy(from: unknownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jumpIfNotNull(value: exceptionSlot, target: thrownTarget))
            case let .rethrow(value):
                instructions.append(.copy(from: value, to: exceptionSlot))
                let rethrowType = arena.exprType(value) ?? sema.types.anyType
                let tokenValue = RuntimeTypeCheckToken.encode(type: rethrowType, sema: sema, interner: interner)
                let thrownTypeToken = arena.appendExpr(.intLiteral(tokenValue), type: intType)
                instructions.append(.constValue(result: thrownTypeToken, value: .intLiteral(tokenValue)))
                instructions.append(.copy(from: thrownTypeToken, to: exceptionTypeSlot))
                instructions.append(.jump(thrownTarget))
            default:
                instructions.append(instruction)
            }
        }
    }
}
