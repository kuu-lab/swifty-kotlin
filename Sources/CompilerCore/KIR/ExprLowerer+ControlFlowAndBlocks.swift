extension ExprLowerer {
    func lowerExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        var value = lowerUnconvertedExpr(
            exprID, ast: ast, sema: sema, arena: arena, interner: interner,
            propertyConstantInitializers: propertyConstantInitializers,
            instructions: &instructions
        )
        let sourceType = sema.bindings.exprTypes[exprID]
        let samFunctionType: TypeID? = if let sourceType,
                                         case .functionType = sema.types.kind(of: sourceType) {
            // Preserve source nullability so a null function stays a null SAM.
            sourceType
        } else {
            // Projected and intersection types may only expose their callable
            // shape through the underlying SAM binding.
            sema.bindings.samUnderlyingFunctionType(for: exprID) ?? sourceType
        }
        if sema.bindings.isSamConversion(exprID),
           let type = samFunctionType,
           case let .functionType(function) = sema.types.kind(of: type)
        {
            let loweredValueCanBeFunction: Bool = {
                guard let loweredType = arena.exprType(value) else { return true }
                switch sema.types.kind(of: loweredType) {
                case .functionType, .any, .typeParam:
                    return true
                default:
                    return false
                }
            }()
            // A discarded cast can smartcast an `Any` local without changing
            // the stored KIR value type. Already-wrapped SAM values stay nominal.
            if loweredValueCanBeFunction,
               let wrapper = driver.lambdaLowerer.lowerFunctionValueSamWrapper(
                   exprID, value: value, functionType: function, sema: sema,
                   arena: arena, interner: interner, instructions: &instructions
               )
            {
                return wrapper
            }
        }
        // A function call returning concrete Unit produces the singleton even
        // when a generic implementation returns null through its erased ABI.
        // Property reads can retain a platform Unit value and must stay intact.
        let isPropertyRead = sema.bindings.identifierSymbol(for: exprID)
            .flatMap { sema.symbols.symbol($0)?.kind } == .property
        let isPropertyAccessorCall: Bool = if let callee = sema.bindings.callBinding(for: exprID)?.chosenCallee {
            isPropertyRead
                || sema.symbols.accessorOwnerProperty(for: callee) != nil
                || sema.symbols.propertySymbol(forAccessor: callee) != nil
                || sema.symbols.parentSymbol(for: callee)
                    .flatMap { sema.symbols.symbol($0)?.kind } == .property
        } else { isPropertyRead }
        let isUnitCall: Bool = if sema.bindings.exprTypes[exprID] == sema.types.unitType {
            switch ast.arena.expr(exprID) {
            case .call: true
            case .memberCall, .safeMemberCall:
                !isPropertyAccessorCall
            default: false
            }
        } else { false }
        if isUnitCall || sema.bindings.unitReturnCoercionExprs.contains(exprID) {
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            value = unit
        }
        if nonNullNothingResultType(
            for: exprID,
            expr: ast.arena.expr(exprID),
            sema: sema
        ) != nil, isPotentialNothingValueProducer(ast.arena.expr(exprID))
        {
            // Native calls can still return a register for source-level Nothing.
            // Match JVM lowering by making that impossible normal edge throw.
            let exceptionType: TypeID = if let symbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"), interner.intern("KotlinNothingValueException"),
            ]) {
                sema.types.make(.classType(ClassType(classSymbol: symbol)))
            } else {
                sema.types.anyType
            }
            let exception = arena.appendTemporary(type: exceptionType)
            instructions.append(.call(
                callee: interner.intern("__kk_kotlin_nothing_value_exception_new"),
                arguments: [],
                result: exception,
                canThrow: false
            ))
            instructions.append(.rethrow(value: exception))
        }
        if let targetType = sema.bindings.platformNullAssertionTypes[exprID] {
            let checked = arena.appendTemporary(type: targetType)
            instructions.append(.nullAssert(operand: value, result: checked))
            let sourceType = arena.exprType(value)
            let sourceIsUnit: Bool = if let sourceType {
                switch sema.types.kind(of: sourceType) {
                case .unit, .platformUnit: true
                default: false
                }
            } else {
                false
            }
            let targetNeedsReferenceBox: Bool = switch sema.types.kind(of: targetType) {
            case .any, .classType, .typeParam: true
            default: false
            }
            if sourceIsUnit, targetNeedsReferenceBox, let sourceType {
                // The null assertion widens its result to the target type. Box
                // Unit before that widening erases the builtin representation.
                return boxValueForAnySlot(
                    checked,
                    sourceType: sourceType,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: interner,
                    arena: arena,
                    resultType: targetType,
                    into: &instructions
                )
            }
            return checked
        }
        return value
    }

    private func nonNullNothingResultType(
        for exprID: ExprID,
        expr: Expr?,
        sema: SemaModule
    ) -> TypeID? {
        if let boundType = sema.bindings.exprTypes[exprID] {
            if case .nothing(.nonNull) = sema.types.kind(of: boundType) {
                return boundType
            }
            return nil
        }

        let isDirectCall: Bool = switch expr {
        case .call, .memberCall:
            true
        default:
            false
        }
        guard isDirectCall,
              let binding = sema.bindings.callBinding(for: exprID),
              let signature = sema.symbols.functionSignature(for: binding.chosenCallee),
              signature.typeParameterSymbols.count == binding.substitutedTypeArguments.count,
              !signature.typeParameterSymbols.isEmpty
        else {
            return nil
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let typeVariables = signature.typeParameterSymbols.compactMap { typeVarBySymbol[$0] }
            .sorted { $0.rawValue < $1.rawValue }
        guard typeVariables.count == binding.substitutedTypeArguments.count else {
            return nil
        }
        var substitution: [TypeVarID: TypeID] = [:]
        for (variable, argument) in zip(typeVariables, binding.substitutedTypeArguments) {
            substitution[variable] = argument
        }
        let resultType = sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
        guard case .nothing(.nonNull) = sema.types.kind(of: resultType) else {
            return nil
        }
        return resultType
    }

    private func isPotentialNothingValueProducer(_ expr: Expr?) -> Bool {
        switch expr {
        case .nameRef, .call, .memberCall, .safeMemberCall, .indexedAccess,
             .binary, .unaryExpr, .asCast, .nullAssert:
            true
        default:
            false
        }
    }

    private func lowerUnconvertedExpr(
        _ exprID: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        arena: KIRArena,
        interner: StringInterner,
        propertyConstantInitializers: [SymbolID: KIRExprKind],
        instructions: inout [KIRInstruction]
    ) -> KIRExprID {
        let boundType = sema.bindings.exprTypes[exprID]
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let boolType = sema.types.make(.primitive(.boolean, .nonNull))
        guard let expr = ast.arena.expr(exprID) else {
            let temp = arena.appendTemporary(type: sema.types.errorType)
            instructions.append(.constValue(result: temp, value: .unit))
            return temp
        }
        let stringType = sema.types.stringType

        switch expr {
        case let .intLiteral(value, _):
            let id = arena.appendExpr(.intLiteral(value), type: boundType ?? intType)
            instructions.append(.constValue(result: id, value: .intLiteral(value)))
            return id

        case let .longLiteral(value, _):
            let longType = sema.types.make(.primitive(.long, .nonNull))
            let id = arena.appendExpr(.longLiteral(value), type: boundType ?? longType)
            instructions.append(.constValue(result: id, value: .longLiteral(value)))
            return id

        case let .uintLiteral(value, _):
            let uintType = sema.types.make(.primitive(.uint, .nonNull))
            let id = arena.appendExpr(.uintLiteral(value), type: boundType ?? uintType)
            instructions.append(.constValue(result: id, value: .uintLiteral(value)))
            return id

        case let .ulongLiteral(value, _):
            let ulongType = sema.types.make(.primitive(.ulong, .nonNull))
            let id = arena.appendExpr(.ulongLiteral(value), type: boundType ?? ulongType)
            instructions.append(.constValue(result: id, value: .ulongLiteral(value)))
            return id

        case let .floatLiteral(value, _):
            let floatType = sema.types.make(.primitive(.float, .nonNull))
            let id = arena.appendExpr(.floatLiteral(value), type: boundType ?? floatType)
            instructions.append(.constValue(result: id, value: .floatLiteral(value)))
            return id

        case let .doubleLiteral(value, _):
            let doubleType = sema.types.make(.primitive(.double, .nonNull))
            let id = arena.appendExpr(.doubleLiteral(value), type: boundType ?? doubleType)
            instructions.append(.constValue(result: id, value: .doubleLiteral(value)))
            return id

        case let .charLiteral(value, _):
            let charType = sema.types.make(.primitive(.char, .nonNull))
            let id = arena.appendExpr(.charLiteral(value), type: boundType ?? charType)
            instructions.append(.constValue(result: id, value: .charLiteral(value)))
            return id

        case let .boolLiteral(value, _):
            let id = arena.appendExpr(.boolLiteral(value), type: boundType ?? boolType)
            instructions.append(.constValue(result: id, value: .boolLiteral(value)))
            return id

        case let .stringLiteral(value, _):
            let id = arena.appendExpr(.stringLiteral(value), type: boundType ?? stringType)
            instructions.append(.constValue(result: id, value: .stringLiteral(value)))
            return id

        case let .stringTemplate(parts, _):
            return lowerStringTemplateExpr(
                parts: parts,
                exprID: exprID,
                stringType: stringType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case .nullLiteral:
            let id = arena.appendExpr(.null, type: boundType ?? sema.types.nullableAnyType)
            instructions.append(.constValue(result: id, value: .null))
            return id

        case let .nameRef(name, _):
            return lowerNameRefExpr(
                name: name,
                exprID: exprID,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .forExpr(_, iterableExpr, bodyExpr, label, _):
            return driver.controlFlowLowerer.lowerForExpr(
                exprID,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .whileExpr(conditionExpr, bodyExpr, label, _):
            return driver.controlFlowLowerer.lowerWhileExpr(
                exprID,
                conditionExpr: conditionExpr,
                bodyExpr: bodyExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .doWhileExpr(bodyExpr, conditionExpr, label, _):
            return driver.controlFlowLowerer.lowerDoWhileExpr(
                exprID,
                bodyExpr: bodyExpr,
                conditionExpr: conditionExpr,
                label: label,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .breakExpr(label, _):
            // CODE-001: Inline only finally blocks whose try scope is exited
            // by this break.  If the loop is nested inside a try body,
            // break stays within the try scope and should not trigger finally.
            inlineFinallyBlocksForBreakOrContinue(
                label: label,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let targetLabel: Int32? = if let label {
                driver.ctx.breakLabel(for: label)
            } else {
                driver.ctx.breakLabel(for: nil)
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
            }
            // Keep the sema type so enclosing try/block lowering sees that
            // this jump has no normal successor to route through finally.
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .continueExpr(label, _):
            inlineFinallyBlocksForBreakOrContinue(
                label: label,
                ast: ast, sema: sema, arena: arena, interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let targetLabel: Int32? = if let label {
                driver.ctx.continueLabel(for: label)
            } else {
                driver.ctx.continueLabel(for: nil)
            }
            if let targetLabel {
                instructions.append(.jump(targetLabel))
            }
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .localFunDecl(localFunName, _, localFunValueParams, _, localFunBody, _, _, _, isTailrec):
            return lowerLocalFunDecl(
                name: localFunName,
                valueParams: localFunValueParams,
                body: localFunBody,
                isTailrec: isTailrec,
                exprID: exprID,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .localDecl(_, isMutable, _, initializer, isDelegated, _, _):
            return lowerLocalDecl(
                isMutable: isMutable,
                initializer: initializer,
                isDelegated: isDelegated,
                exprID: exprID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .localAssign(_, valueExpr, _):
            return lowerLocalAssign(
                valueExpr: valueExpr,
                exprID: exprID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .memberAssign(receiverExpr, calleeName, valueExpr, _):
            return driver.callLowerer.lowerMemberAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .safeMemberAssign(receiverExpr, calleeName, valueExpr, _):
            return driver.callLowerer.lowerSafeMemberAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .indexedAccess(receiverExpr, indices, _):
            // `list[i]` dispatches the same erased `get` members as the
            // `.memberCall` spelling, so its result needs the same JVM
            // checkcast on a non-reified generic return (KUU-3668): a
            // heap-polluted `MutableList<E>` element must throw
            // ClassCastException at the typed read, not corrupt the value.
            return checkedErasedGenericCallResult(
                driver.callLowerer.lowerIndexedAccessExpr(
                    exprID,
                    receiverExpr: receiverExpr,
                    indices: indices,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
                exprID: exprID,
                boundType: boundType,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )

        case let .indexedAssign(receiverExpr, indices, valueExpr, _):
            return driver.callLowerer.lowerIndexedAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                indices: indices,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .returnExpr(value, label, _):
            let targetsFunction = sema.bindings.functionReturnLambdaPaths[exprID] != nil
            let returnTargetSymbol = sema.bindings.identifierSymbol(for: exprID)
                ?? (label == nil ? driver.ctx.currentFunctionSymbol : nil)
            let returnsFromConstructor = returnTargetSymbol
                .flatMap { sema.symbols.symbol($0)?.kind == .constructor } ?? false
            let discardsConstructorUnitReturn = returnsFromConstructor
                && value.map { sema.bindings.exprTypes[$0] == sema.types.unitType } == true
            let outerLambdaTarget: KIRReturnTarget? = {
                guard let target = sema.bindings.lambdaReturnTargets[exprID],
                      sema.bindings.lambdaReturnLambdaPaths[exprID]?.isEmpty == false else { return nil }
                return .function(driver.ctx.syntheticLambdaSymbol(for: target))
            }()
            // A labeled return targeting a lambda body inlined into a loop (e.g. `repeat`)
            // ends only that iteration: run the inner `finally` blocks, then jump.
            if !targetsFunction, let label, let iterationEnd = driver.ctx.continueLabel(for: label) {
                if let value {
                    _ = lowerExpr(
                        value,
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                }
                inlineFinallyBlocksForBreakOrContinue(
                    label: label,
                    ast: ast, sema: sema, arena: arena, interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                instructions.append(.jump(iterationEnd))
                let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
                instructions.append(.constValue(result: unit, value: .unit))
                return unit
            }
            let returnValue: KIRExprID?
            if let value {
                let lowered = lowerExpr(
                    value,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if discardsConstructorUnitReturn {
                    // Kotlin treats `return Unit` in a constructor like `return`:
                    // evaluate the expression, then leave without returning Unit
                    // in place of the constructed instance.
                    returnValue = nil
                } else {
                    // A bare variable read resolves to the variable's own storage
                    // register (see `driver.ctx.localValue(for:)` above), not a
                    // copy. If this return is inside a try-with-finally,
                    // `inlineAllEnclosingFinallyBlocks` below runs the finally body
                    // next -- if it reassigns that same variable, `lowered` would
                    // retroactively observe the mutation. Snapshot into a fresh
                    // register first, same as the `val a = b` aliasing guard in the
                    // `.localDecl` case above.
                    if isBareVariableRead(value, ast: ast), !driver.ctx.enclosingFinallyBlocks().isEmpty {
                        let snapshot = arena.appendTemporary(type: arena.exprType(lowered) ?? sema.types.anyType)
                        instructions.append(.copy(from: lowered, to: snapshot))
                        returnValue = snapshot
                    } else {
                        returnValue = lowered
                    }
                }
            } else {
                returnValue = nil
            }

            let effectiveReturnValue = returnValue
                ?? (returnsFromConstructor ? driver.ctx.activeImplicitReceiverExprID() : nil)
            if let returnValue = effectiveReturnValue {
                if let outerLambdaTarget {
                    instructions.append(.nonLocalReturn(returnValue, target: outerLambdaTarget))
                } else if label == nil || targetsFunction, driver.ctx.currentLambdaAllowsNonLocalReturn {
                    instructions.append(.nonLocalReturn(returnValue, target: driver.ctx.nonLocalReturnTarget.map(KIRReturnTarget.function)))
                } else {
                    inlineAllEnclosingFinallyBlocks(
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.returnValue(returnValue))
                }
            } else {
                if let outerLambdaTarget {
                    instructions.append(.nonLocalReturn(nil, target: outerLambdaTarget))
                } else if label == nil || targetsFunction, driver.ctx.currentLambdaAllowsNonLocalReturn {
                    instructions.append(.nonLocalReturn(nil, target: driver.ctx.nonLocalReturnTarget.map(KIRReturnTarget.function)))
                } else {
                    inlineAllEnclosingFinallyBlocks(
                        ast: ast, sema: sema, arena: arena, interner: interner,
                        propertyConstantInitializers: propertyConstantInitializers,
                        instructions: &instructions
                    )
                    instructions.append(.returnUnit)
                }
            }
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return driver.controlFlowLowerer.lowerIfExpr(
                exprID,
                condition: condition,
                thenExpr: thenExpr,
                elseExpr: elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .tryExpr(bodyExpr, catchClauses, finallyExpr, _):
            return driver.controlFlowLowerer.lowerTryExpr(
                exprID,
                bodyExpr: bodyExpr,
                catchClauses: catchClauses,
                finallyExpr: finallyExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .binary(op, lhs, rhs, _):
            return driver.callLowerer.lowerBinaryExpr(
                exprID,
                op: op,
                lhs: lhs,
                rhs: rhs,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .call(calleeExpr, _, args, _):
            return checkedErasedGenericCallResult(
                driver.callLowerer.lowerCallExpr(
                    exprID,
                    calleeExpr: calleeExpr,
                    args: args,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
                exprID: exprID,
                boundType: boundType,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )

        case let .memberCall(receiverExpr, calleeName, _, args, _):
            return checkedErasedGenericCallResult(
                driver.callLowerer.lowerMemberCallExpr(
                    exprID,
                    receiverExpr: receiverExpr,
                    calleeName: calleeName,
                    args: args,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
                exprID: exprID,
                boundType: boundType,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )

        case let .unaryExpr(op, operandExpr, _):
            return lowerUnaryExpr(
                op: op,
                operandExpr: operandExpr,
                exprID: exprID,
                boundType: boundType,
                intType: intType,
                boolType: boolType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .isCheck(exprToCheck, typeRefID, negated, _):
            return lowerIsCheckExpr(
                exprToCheck: exprToCheck,
                typeRefID: typeRefID,
                negated: negated,
                exprID: exprID,
                boundType: boundType,
                boolType: boolType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .asCast(exprToCast, typeRefID, isSafe, _):
            return lowerAsCastExpr(
                exprToCast: exprToCast,
                typeRefID: typeRefID,
                isSafe: isSafe,
                exprID: exprID,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .nullAssert(innerExpr, _):
            let operandID = lowerExpr(
                innerExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            let result = arena.appendTemporary(type: boundType ?? sema.types.anyType)
            instructions.append(.nullAssert(operand: operandID, result: result))
            return result

        case let .safeMemberCall(receiverExpr, calleeName, _, args, _):
            return checkedErasedGenericCallResult(
                driver.callLowerer.lowerSafeMemberCallExpr(
                    exprID,
                    receiverExpr: receiverExpr,
                    calleeName: calleeName,
                    args: args,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                ),
                exprID: exprID,
                boundType: boundType,
                sema: sema,
                interner: interner,
                arena: arena,
                instructions: &instructions
            )

        case let .compoundAssign(op, _, valueExpr, _):
            return lowerCompoundAssign(
                op: op,
                valueExpr: valueExpr,
                exprID: exprID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .indexedCompoundAssign(_, receiverExpr, indices, valueExpr, _):
            return driver.callLowerer.lowerIndexedCompoundAssignExpr(
                exprID,
                receiverExpr: receiverExpr,
                indices: indices,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .memberCompoundAssign(op, receiverExpr, calleeName, valueExpr, _):
            return driver.callLowerer.lowerMemberCompoundAssignExpr(
                exprID,
                op: op,
                receiverExpr: receiverExpr,
                calleeName: calleeName,
                valueExpr: valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .throwExpr(valueExpr, _):
            let thrownValue = lowerExpr(
                valueExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            instructions.append(.rethrow(value: thrownValue))
            let unit = arena.appendExpr(.unit, type: sema.types.nothingType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .lambdaLiteral(params, bodyExpr, _, _):
            let allowsNonLocalReturn = driver.ctx.pendingLambdaNonLocalReturnAllowance
            driver.ctx.pendingLambdaNonLocalReturnAllowance = false
            let value = driver.lambdaLowerer.lowerLambdaLiteralExpr(
                exprID,
                params: params,
                bodyExpr: bodyExpr,
                allowsNonLocalReturn: allowsNonLocalReturn,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
            return driver.callLowerer.materializeNominalFunctionValue(
                value,
                exprID: exprID,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case let .callableRef(receiverExpr, memberName, _):
            return lowerCallableRefExpr(
                receiverExpr: receiverExpr,
                memberName: memberName,
                exprID: exprID,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .objectLiteral(superTypes, declID, _):
            return driver.objectLiteralLowerer.lowerObjectLiteralExpr(
                exprID,
                superTypes: superTypes,
                declID: declID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .localNominalDecl(declID, _):
            return driver.objectLiteralLowerer.lowerLocalNominalDeclExpr(
                exprID,
                declID: declID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .whenExpr(subject, branches, elseExpr, _):
            return driver.controlFlowLowerer.lowerWhenExpr(
                exprID,
                subject: subject,
                branches: branches,
                elseExpr: elseExpr,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .blockExpr(statements, trailingExpr, _):
            for stmt in statements {
                let loweredStmt = lowerExpr(
                    stmt,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
                if driver.controlFlowLowerer.isTerminatedExpr(loweredStmt, arena: arena, sema: sema) {
                    return loweredStmt
                }
            }
            if let trailingExpr {
                if ast.arena.isAnonymousFunction(exprID),
                   statements.count == 1,
                   ast.arena.isAnonymousFunction(statements[0]),
                   case .callableRef? = ast.arena.expr(trailingExpr),
                   let functionSymbol = sema.bindings.identifierSymbols[trailingExpr],
                   sema.symbols.symbol(functionSymbol)?.flags.contains(.localFunction) == true,
                   arena.function(for: functionSymbol)?.isInlineOnly == true,
                   let callableExpr = driver.ctx.localValue(for: functionSymbol)
                {
                    // This synthetic reference is the value of an anonymous
                    // function whose non-local loop jump requires inlining.
                    // Reuse the local function binding so callable-reference
                    // reflection and escaping adapters cannot retain its
                    // caller-owned jump marker after inline expansion.
                    return callableExpr
                }
                return lowerExpr(
                    trailingExpr,
                    ast: ast,
                    sema: sema,
                    arena: arena,
                    interner: interner,
                    propertyConstantInitializers: propertyConstantInitializers,
                    instructions: &instructions
                )
            }
            let unit = arena.appendExpr(.unit, type: sema.types.unitType)
            instructions.append(.constValue(result: unit, value: .unit))
            return unit

        case let .superRef(_, label, _):
            return lowerSuperRefExpr(
                exprID: exprID,
                label: label,
                boundType: boundType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case let .thisRef(label, _):
            return lowerThisRefExpr(
                label: label,
                exprID: exprID,
                boundType: boundType,
                sema: sema,
                arena: arena,
                interner: interner,
                instructions: &instructions
            )

        case let .inExpr(lhsExpr, rhsExpr, _):
            return lowerContainsCheck(
                exprID: exprID,
                lhsExpr: lhsExpr,
                rhsExpr: rhsExpr,
                negated: false,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .notInExpr(lhsExpr, rhsExpr, _):
            return lowerContainsCheck(
                exprID: exprID,
                lhsExpr: lhsExpr,
                rhsExpr: rhsExpr,
                negated: true,
                boundType: boundType,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .destructuringDecl(names, _, initializer, _):
            return lowerDestructuringDecl(
                names: names,
                initializer: initializer,
                exprID: exprID,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )

        case let .forDestructuringExpr(names, iterableExpr, bodyExpr, syntax, _):
            return driver.controlFlowLowerer.lowerForDestructuringExpr(
                exprID,
                names: names,
                iterableExpr: iterableExpr,
                bodyExpr: bodyExpr,
                syntax: syntax,
                ast: ast,
                sema: sema,
                arena: arena,
                interner: interner,
                propertyConstantInitializers: propertyConstantInitializers,
                instructions: &instructions
            )
        }
    }

}
