
extension ControlFlowLowerer {
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
        let boundType = sema.bindings.exprTypes[exprID]
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let exceptionSlot = arena.appendTemporary(type: sema.types.nullableAnyType)
        let exceptionTypeSlot = arena.appendTemporary(type: intType)
        let nullExceptionValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
        let zeroTypeToken = arena.appendExpr(.intLiteral(0), type: intType)
        instructions.append(.constValue(result: nullExceptionValue, value: .null))
        instructions.append(.constValue(result: zeroTypeToken, value: .intLiteral(0)))
        instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
        instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

        let tryResult = arena.appendTemporary(type: boundType ?? sema.types.errorType)

        let catchDispatchLabel = driver.ctx.makeLoopLabel()
        let finallyLabel = driver.ctx.makeLoopLabel()
        let rethrowLabel = driver.ctx.makeLoopLabel()
        let endLabel = driver.ctx.makeLoopLabel()

        let nonLocalReturnLabel = finallyExpr.map { _ in driver.ctx.makeLoopLabel() }
        let nonLocalReturnValue = arena.appendTemporary(type: nil)
        let returningNonLocally = arena.appendTemporary(type: boolType)
        let notReturning = arena.appendExpr(.boolLiteral(false), type: boolType)
        if let nonLocalReturnLabel {
            instructions.append(.constValue(result: notReturning, value: .boolLiteral(false)))
            instructions.append(.copy(from: notReturning, to: returningNonLocally))
            instructions.append(.beginNonLocalReturnScope(value: nonLocalReturnValue, target: nonLocalReturnLabel))
        }

        let catchBindings = catchClauses.map { resolveCatchClauseBinding($0, ast: ast, sema: sema, interner: interner) }
        let catchCheckLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let catchMissLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let catchBodyLabels = catchClauses.map { _ in driver.ctx.makeLoopLabel() }
        let unmatchedCatchLabel = driver.ctx.makeLoopLabel()

        // CODE-001: Push finally block so that return/break/continue inside the
        // try body or catch bodies will inline the finally code before transferring.
        // The block is popped explicitly before lowering the finally body itself
        // (see the pop site below) so that the finally body does not see itself
        // on the stack.
        if let finallyExpr {
            driver.ctx.pushFinallyBlock(finallyExpr)
        }

        var bodyInstructions: [KIRInstruction] = []
        let bodyResultID = driver.lowerExpr(
            bodyExpr,
            ast: ast,
            sema: sema,
            arena: arena,
            interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &bodyInstructions
        )

        // CODE-001: Wrap the body's throw-routing output in a finally-guard
        // region so that, if this try is itself nested inside an outer
        // try/catch body, the outer's own appendThrowAwareInstructions pass
        // does not re-wrap calls that are already routed to this try's
        // exceptionSlot. Without this, the outer pass would insert its own
        // jumpIfNotNull immediately after such a call — racing ahead of this
        // try's own follow-up (catch dispatch / finally) and skipping it
        // whenever the exception is actually thrown.
        instructions.append(.beginFinallyGuard)
        appendThrowAwareInstructions(
            bodyInstructions,
            exceptionSlot: exceptionSlot,
            exceptionTypeSlot: exceptionTypeSlot,
            thrownTarget: catchDispatchLabel,
            sema: sema,
            interner: interner,
            arena: arena,
            instructions: &instructions
        )
        instructions.append(.endFinallyGuard)

        let bodyTerminated = isTerminatedExpr(bodyResultID, arena: arena, sema: sema)
        if !bodyTerminated {
            instructions.append(.copy(from: bodyResultID, to: tryResult))
            instructions.append(.jump(finallyLabel))
        }

        instructions.append(.label(catchDispatchLabel))
        if catchClauses.isEmpty {
            instructions.append(.jump(finallyLabel))
        } else if catchClauses.count == 1 {
            let clause = catchClauses[0]
            let binding = catchBindings[0]

            let noMatchLabel = driver.ctx.makeLoopLabel()
            if !isCatchAllType(binding.parameterType, sema: sema, interner: interner) {
                let falseValue = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: falseValue, value: .boolLiteral(false)))

                let matchResult = arena.appendTemporary(type: boolType)
                if isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner) {
                    // Cancellation check only needs falseValue for the jump;
                    // trueValue/sharedUnknownToken are not used.
                    emitNonThrowingCall(
                        callee: interner.intern("kk_throwable_is_cancellation"),
                        arg: exceptionSlot,
                        result: matchResult,
                        into: &instructions
                    )
                } else {
                    // Only emit trueValue/sharedUnknownToken when actually needed
                    // by emitExceptionTypeCheck (avoids dead constValue instructions).
                    let trueValue = arena.appendExpr(.boolLiteral(true), type: boolType)
                    let sharedUnknownToken = arena.appendExpr(.intLiteral(0), type: intType)
                    instructions.append(.constValue(result: trueValue, value: .boolLiteral(true)))
                    instructions.append(.constValue(result: sharedUnknownToken, value: .intLiteral(0)))

                    emitExceptionTypeCheck(
                        catchType: binding.parameterType,
                        exceptionSlot: exceptionSlot,
                        exceptionTypeSlot: exceptionTypeSlot,
                        matchResult: matchResult,
                        unknownTypeToken: sharedUnknownToken,
                        trueValue: trueValue,
                        boolType: boolType,
                        intType: intType,
                        sema: sema,
                        interner: interner,
                        arena: arena,
                        instructions: &instructions
                    )
                }
                instructions.append(.jumpIfEqual(lhs: matchResult, rhs: falseValue, target: noMatchLabel))
            }

            var previousCatchParamValue: KIRExprID?
            if clause.paramName != nil, binding.parameterSymbol != .invalid {
                let paramID = arena.appendTemporary(type: binding.parameterType)
                instructions.append(.copy(from: exceptionSlot, to: paramID))
                previousCatchParamValue = driver.ctx.localValue(for: binding.parameterSymbol)
                driver.ctx.setLocalValue(paramID, for: binding.parameterSymbol)
            }
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

            var catchBodyInstructions: [KIRInstruction] = []
            let catchBodyResult = driver.lowerExpr(
                clause.body,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &catchBodyInstructions
            )
            // CODE-001: see the matching guard around the body's own
            // appendThrowAwareInstructions call above — a nested try inside
            // this catch body would otherwise have its exception routing
            // re-wrapped (and its own finally skipped) by an outer try.
            instructions.append(.beginFinallyGuard)
            appendThrowAwareInstructions(
                catchBodyInstructions,
                exceptionSlot: exceptionSlot,
                exceptionTypeSlot: exceptionTypeSlot,
                thrownTarget: finallyLabel,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )
            instructions.append(.endFinallyGuard)

            if clause.paramName != nil, binding.parameterSymbol != .invalid {
                if let previousCatchParamValue {
                    driver.ctx.setLocalValue(previousCatchParamValue, for: binding.parameterSymbol)
                } else {
                    driver.ctx.clearLocalValue(for: binding.parameterSymbol)
                }
            }

            let catchTerminated = isTerminatedExpr(catchBodyResult, arena: arena, sema: sema)
            if !catchTerminated {
                instructions.append(.copy(from: catchBodyResult, to: tryResult))
            }
            instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
            instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))
            instructions.append(.jump(finallyLabel))

            instructions.append(.label(noMatchLabel))
            instructions.append(.jump(finallyLabel))
        } else {
            // Emit shared falseValue for any non-catch-all clause (used by
            // both cancellation checks and runtime type checks for the jump).
            let hasTypedCatch = catchBindings.contains { binding in
                !isCatchAllType(binding.parameterType, sema: sema, interner: interner)
            }
            // Only emit trueValue/sharedUnknownToken when at least one clause
            // actually needs emitExceptionTypeCheck (i.e., non-catch-all AND
            // non-cancellation-exception). This avoids dead constValue
            // instructions when all typed clauses are cancellation checks.
            let needsRuntimeTypeCheck = catchBindings.contains { binding in
                !isCatchAllType(binding.parameterType, sema: sema, interner: interner)
                    && !isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner)
            }
            var falseValue: KIRExprID?
            var trueValue: KIRExprID?
            var sharedUnknownToken: KIRExprID?
            if hasTypedCatch {
                let fv = arena.appendExpr(.boolLiteral(false), type: boolType)
                instructions.append(.constValue(result: fv, value: .boolLiteral(false)))
                falseValue = fv
            }
            if needsRuntimeTypeCheck {
                let tv = arena.appendExpr(.boolLiteral(true), type: boolType)
                let ut = arena.appendExpr(.intLiteral(0), type: intType)
                instructions.append(.constValue(result: tv, value: .boolLiteral(true)))
                instructions.append(.constValue(result: ut, value: .intLiteral(0)))
                trueValue = tv
                sharedUnknownToken = ut
            }
            instructions.append(.jump(catchCheckLabels[0]))

            for index in catchClauses.indices {
                let clause = catchClauses[index]
                let binding = catchBindings[index]
                instructions.append(.label(catchCheckLabels[index]))

                if !isCatchAllType(binding.parameterType, sema: sema, interner: interner) {
                    // Safe to force-unwrap: hasTypedCatch guarantees falseValue is set
                    let fv = falseValue!
                    let matchResult = arena.appendTemporary(type: boolType)
                    if isCancellationExceptionType(binding.parameterType, sema: sema, interner: interner) {
                        // Cancellation check only needs falseValue for the jump;
                        // trueValue/sharedUnknownToken are not used.
                        emitNonThrowingCall(
                            callee: interner.intern("kk_throwable_is_cancellation"),
                            arg: exceptionSlot,
                            result: matchResult,
                            into: &instructions
                        )
                    } else {
                        // Safe to force-unwrap: needsRuntimeTypeCheck guarantees these are set
                        let tv = trueValue!
                        let ut = sharedUnknownToken!
                        emitExceptionTypeCheck(
                            catchType: binding.parameterType,
                            exceptionSlot: exceptionSlot,
                            exceptionTypeSlot: exceptionTypeSlot,
                            matchResult: matchResult,
                            unknownTypeToken: ut,
                            trueValue: tv,
                            boolType: boolType,
                            intType: intType,
                            sema: sema,
                            interner: interner,
                            arena: arena,
                            instructions: &instructions
                        )
                    }
                    instructions.append(.jumpIfEqual(lhs: matchResult, rhs: fv, target: catchMissLabels[index]))
                }
                instructions.append(.jump(catchBodyLabels[index]))
                instructions.append(.label(catchBodyLabels[index]))

                var previousCatchParamValue: KIRExprID?
                if clause.paramName != nil, binding.parameterSymbol != .invalid {
                    let paramID = arena.appendTemporary(type: binding.parameterType)
                    instructions.append(.copy(from: exceptionSlot, to: paramID))
                    previousCatchParamValue = driver.ctx.localValue(for: binding.parameterSymbol)
                    driver.ctx.setLocalValue(paramID, for: binding.parameterSymbol)
                }
                instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
                instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))

                var catchBodyInstructions: [KIRInstruction] = []
                let catchBodyResult = driver.lowerExpr(
                    clause.body,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &catchBodyInstructions
                )
                // CODE-001: see the matching guard around the body's own
                // appendThrowAwareInstructions call above — a nested try
                // inside this catch body would otherwise have its exception
                // routing re-wrapped (and its own finally skipped) by an
                // outer try.
                instructions.append(.beginFinallyGuard)
                appendThrowAwareInstructions(
                    catchBodyInstructions,
                    exceptionSlot: exceptionSlot,
                    exceptionTypeSlot: exceptionTypeSlot,
                    thrownTarget: finallyLabel,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
                instructions.append(.endFinallyGuard)

                if clause.paramName != nil, binding.parameterSymbol != .invalid {
                    if let previousCatchParamValue {
                        driver.ctx.setLocalValue(previousCatchParamValue, for: binding.parameterSymbol)
                    } else {
                        driver.ctx.clearLocalValue(for: binding.parameterSymbol)
                    }
                }

                let catchTerminated = isTerminatedExpr(catchBodyResult, arena: arena, sema: sema)
                if !catchTerminated {
                    instructions.append(.copy(from: catchBodyResult, to: tryResult))
                }
                instructions.append(.copy(from: nullExceptionValue, to: exceptionSlot))
                instructions.append(.copy(from: zeroTypeToken, to: exceptionTypeSlot))
                instructions.append(.jump(finallyLabel))

                instructions.append(.label(catchMissLabels[index]))
                if index + 1 < catchClauses.count {
                    instructions.append(.jump(catchCheckLabels[index + 1]))
                } else {
                    instructions.append(.jump(unmatchedCatchLabel))
                }
            }

            instructions.append(.label(unmatchedCatchLabel))
            instructions.append(.jump(finallyLabel))
        }

        // CODE-001: Pop the finally block before lowering the finally label itself,
        // so that the finally body lowering does not see itself on the stack.
        if finallyExpr != nil {
            driver.ctx.popFinallyBlock()
        }

        if let nonLocalReturnLabel {
            instructions.append(.endNonLocalReturnScope)
            instructions.append(.label(nonLocalReturnLabel))
            instructions.append(.constValue(result: returningNonLocally, value: .boolLiteral(true)))
            instructions.append(.jump(finallyLabel))
        }

        instructions.append(.label(finallyLabel))
        if let finallyExpr {
            var finallyInstructions: [KIRInstruction] = []
            _ = driver.lowerExpr(
                finallyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &finallyInstructions
            )

            let hasThrowableCall = finallyInstructions.contains { (instr: KIRInstruction) -> Bool in
                switch instr {
                case .call,
                     .virtualCall,
                     .nullAssert,
                     .rethrow:
                    return true
                default:
                    return false
                }
            }

            if hasThrowableCall {
                // Allocate separate slots for exceptions thrown *inside* the
                // finally body.  Using the outer exceptionSlot would destroy
                // the pending exception when a finally call succeeds (writes
                // null to the slot), silently swallowing the in-flight error.
                let finallyExSlot = arena.appendTemporary(type: sema.types.nullableAnyType
                )
                let finallyExTypeSlot = arena.appendTemporary(type: intType
                )
                let finallyNullValue = arena.appendExpr(.null, type: sema.types.nullableAnyType)
                let finallyZeroValue = arena.appendExpr(.intLiteral(0), type: intType)

                // Wrap with guard sentinels so that an outer
                // appendThrowAwareInstructions pass does not double-wrap the
                // already-routed exception handling inside this finally block.
                instructions.append(.beginFinallyGuard)

                instructions.append(.constValue(result: finallyNullValue, value: .null))
                instructions.append(.constValue(result: finallyZeroValue, value: .intLiteral(0)))
                instructions.append(.copy(from: finallyNullValue, to: finallyExSlot))
                instructions.append(.copy(from: finallyZeroValue, to: finallyExTypeSlot))

                let finallyRethrowLabel = driver.ctx.makeLoopLabel()
                let finallyAfterLabel = driver.ctx.makeLoopLabel()

                appendThrowAwareInstructions(
                    finallyInstructions,
                    exceptionSlot: finallyExSlot,
                    exceptionTypeSlot: finallyExTypeSlot,
                    thrownTarget: finallyRethrowLabel,
                    sema: sema,
                    interner: interner,
                    arena: arena,
                    instructions: &instructions
                )
                instructions.append(.jump(finallyAfterLabel))
                instructions.append(.endFinallyGuard)

                // Finally body itself threw — rethrow that exception (replaces
                // the original in-flight exception per Kotlin semantics).
                instructions.append(.label(finallyRethrowLabel))
                instructions.append(.rethrow(value: finallyExSlot))

                instructions.append(.label(finallyAfterLabel))
            } else {
                // No throwable calls — append the finally body directly.
                instructions.append(contentsOf: finallyInstructions)
            }
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
            instructions.append(.jumpIfEqual(lhs: returningNonLocally, rhs: notReturning, target: afterReturnLabel))
            instructions.append(.resumeNonLocalReturn(nonLocalReturnValue))
            instructions.append(.label(afterReturnLabel))
        }
        if boundType == sema.types.nothingType {
            let terminated = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: terminated, value: .unit))
            return terminated
        }
        return tryResult
    }

    /// Emits instructions to check whether a caught exception matches a specific catch clause type.
    ///
    /// This first performs a fast integer comparison against the encoded catch type token.
    /// When the exact token comparison misses, it falls back to `kk_op_is`, because a
    /// known thrown subtype token can still match a catch clause for one of its supertypes.
    /// The runtime fallback also handles UNKNOWN (0) tokens from external/runtime calls.
    ///
    /// Generated control flow:
    /// ```
    ///   typeMatches = (exceptionTypeSlot == catchTypeToken)
    ///   if typeMatches -> matchResult = true
    ///   typeUnknown = (exceptionTypeSlot == 0)
    ///   matchResult = kk_op_is(exceptionSlot, catchTypeToken)  // subtype/unknown fallback
    /// ```
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

        // Fast path: exact token match (exception type is known and matches)
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

        // Runtime fallback: handles UNKNOWN tokens and known subtype/supertype matches.
        let runtimeResult = arena.appendTemporary(type: boolType)
        instructions.append(.call(
            symbol: nil,
            callee: interner.intern("kk_op_is"),
            arguments: [exceptionSlot, tokenExpr],
            result: runtimeResult,
            canThrow: false,
            thrownResult: nil
        ))
        instructions.append(.copy(from: runtimeResult, to: matchResult))
        instructions.append(.jump(doneLabel))

        // Exact match: set matchResult = true
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
        for instruction in loweredInstructions {
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
            // Inside a finally guard region: pass through verbatim.
            if finallyGuardDepth > 0 {
                instructions.append(instruction)
                continue
            }
            switch instruction {
            case let .nullAssert(operand, result):
                // `OperatorLoweringPass` runs after this source-level control-flow
                // lowering. Lower the assertion here as well so its thrown value
                // is routed to the enclosing try/catch exception slot.
                let notNullResult = arena.appendTemporary(type: arena.exprType(result))
                instructions.append(.call(
                    symbol: nil,
                    callee: interner.intern("kk_op_notnull"),
                    arguments: [operand],
                    result: notNullResult,
                    canThrow: true,
                    thrownResult: exceptionSlot
                ))
                let resultType = arena.exprType(result)
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
                    instructions.append(.call(
                        symbol: nil,
                        callee: unboxCallee,
                        arguments: [notNullResult],
                        result: result,
                        canThrow: false,
                        thrownResult: nil
                    ))
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
