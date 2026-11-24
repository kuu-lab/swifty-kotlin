
final class ExprTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func exprSpineContainsSafeMemberAccess(_ id: ExprID, ast: ASTModule) -> Bool {
        var currentID = id
        var visited: Set<ExprID> = []
        while visited.insert(currentID).inserted {
            guard let expr = ast.arena.expr(currentID) else { return false }
            switch expr {
            case .safeMemberCall, .safeMemberAssign:
                return true
            case let .memberCall(receiver, _, _, _, _),
                 let .memberAssign(receiver, _, _, _):
                currentID = receiver
            case let .nullAssert(operand, _):
                currentID = operand
            default:
                return false
            }
        }
        return false
    }

    func isUnguardedSafeIndexedAccessReceiver(_ id: ExprID, ast: ASTModule) -> Bool {
        guard !ast.arena.isParenthesized(id) else { return false }
        switch ast.arena.expr(id) {
        case .safeMemberCall:
            return true
        case let .indexedAccess(receiver, _, _):
            return isUnguardedSafeIndexedAccessReceiver(receiver, ast: ast)
        default:
            return false
        }
    }

    // swiftlint:disable:next cyclomatic_complexity
    func inferExpr(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID? = nil,
        isStatementContext: Bool = false,
        inferLambdaResultType: Bool = false
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard let expr = ast.arena.expr(id) else {
            return sema.types.errorType
        }

        validateExpressionAnnotationVisibility(id, ctx: ctx)

        // A discarded statement evaluates a call for its side effects only —
        // the JVM pops the result without checkcasting it, so a statement-
        // context erased result must not claim its substituted type either
        // (KUU-3893). Branch tails reach this through the propagated
        // isStatementContext flag; transparent blocks forward it through the
        // consumer unwrap in recordGenericCallConsumer.
        if isStatementContext, expectedType == nil {
            driver.recordGenericCallConsumer(id, type: sema.types.unitType)
        }

        if let expectedType,
           let widened = inferWidenedIntegerConstantExpression(id, ctx: ctx, locals: &locals, expectedType: expectedType)
        {
            return widened
        }

        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        let longType = sema.types.longType
        let floatType = sema.types.floatType
        let doubleType = sema.types.doubleType
        let charType = sema.types.charType
        let stringType = sema.types.stringType

        switch expr {
        case let .intLiteral(value, _):
            let literalType = intLiteralType(expectedType: expectedType, sema: sema, defaultType: intType, literalValue: value)
            sema.bindings.bindExprType(id, type: literalType)
            return literalType

        case .longLiteral:
            sema.bindings.bindExprType(id, type: longType)
            return longType

        case let .uintLiteral(value, _):
            let literalType = uintLiteralType(
                expectedType: expectedType,
                sema: sema,
                literalValue: value
            )
            sema.bindings.bindExprType(id, type: literalType)
            return literalType

        case .ulongLiteral:
            sema.bindings.bindExprType(id, type: sema.types.ulongType)
            return sema.types.ulongType

        case .floatLiteral:
            sema.bindings.bindExprType(id, type: floatType)
            return floatType

        case .doubleLiteral:
            sema.bindings.bindExprType(id, type: doubleType)
            return doubleType

        case .charLiteral:
            sema.bindings.bindExprType(id, type: charType)
            return charType

        case .nullLiteral:
            sema.bindings.bindExprType(id, type: sema.types.nullableNothingType)
            return sema.types.nullableNothingType

        case .boolLiteral:
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case .stringLiteral:
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case let .stringTemplate(parts, _):
            for part in parts {
                if case let .expression(exprID) = part {
                    _ = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
                    // Template parts are appended through Any?
                    // (StringBuilder.append(Object)); the JVM does not claim
                    // the part's substituted type (KUU-3893).
                    driver.recordGenericCallConsumer(exprID, type: sema.types.nullableAnyType)
                }
            }
            sema.bindings.bindExprType(id, type: stringType)
            return stringType

        case let .nameRef(name, nameRange):
            let nameType = inferNameRefExpr(id, name: name, nameRange: nameRange, ctx: ctx, locals: &locals)
            if let expectedType,
               !sema.types.isSubtype(nameType, expectedType),
               let companionType = driver.helpers.retypeClassNameAsCompanionValue(
                   id, currentType: nameType, ast: ast, sema: sema
               )
            {
                if sema.types.isSubtype(companionType, expectedType) {
                    return companionType
                }
                sema.bindings.bindExprType(id, type: nameType)
            }
            return nameType

        case let .forExpr(loopVariable, iterableExpr, bodyExpr, label, range):
            return driver.controlFlowChecker.inferForExpr(id, loopVariable: loopVariable, iterableExpr: iterableExpr, bodyExpr: bodyExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case let .whileExpr(conditionExpr, bodyExpr, label, range):
            return driver.controlFlowChecker.inferWhileExpr(id, conditionExpr: conditionExpr, bodyExpr: bodyExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case let .doWhileExpr(bodyExpr, conditionExpr, label, range):
            return driver.controlFlowChecker.inferDoWhileExpr(id, bodyExpr: bodyExpr, conditionExpr: conditionExpr, label: label, range: range, ctx: ctx, locals: &locals)

        case let .breakExpr(label, range):
            if ctx.loopDepth == 0 {
                if let lambdaPath = ctx.lambdaPathForEnclosingLoopJump(label: label) {
                    sema.bindings.bindLoopJump(id, lambdaPath: lambdaPath)
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0018",
                        "'break' is only allowed inside loop bodies.",
                        range: range
                    )
                }
            } else if let label, !ctx.loopLabelStack.contains(label) {
                if let lambdaPath = ctx.lambdaPathForEnclosingLoopJump(label: label) {
                    sema.bindings.bindLoopJump(id, lambdaPath: lambdaPath)
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0097",
                        "'break' with label '@\(interner.resolve(label))' does not reference a valid enclosing loop.",
                        range: range
                    )
                }
            }
            if ctx.loopDepth > 0, label.map(ctx.loopLabelStack.contains) ?? true {
                ctx.recordLoopJump(locals, label: label, isBreak: true)
            }
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .continueExpr(label, range):
            if ctx.loopDepth == 0 {
                if let lambdaPath = ctx.lambdaPathForEnclosingLoopJump(label: label) {
                    sema.bindings.bindLoopJump(id, lambdaPath: lambdaPath)
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0019",
                        "'continue' is only allowed inside loop bodies.",
                        range: range
                    )
                }
            } else if let label, !ctx.loopLabelStack.contains(label) {
                if let lambdaPath = ctx.lambdaPathForEnclosingLoopJump(label: label) {
                    sema.bindings.bindLoopJump(id, lambdaPath: lambdaPath)
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0098",
                        "'continue' with label '@\(interner.resolve(label))' does not reference a valid enclosing loop.",
                        range: range
                    )
                }
            }
            if ctx.loopDepth > 0, label.map(ctx.loopLabelStack.contains) ?? true {
                ctx.recordLoopJump(locals, label: label, isBreak: false)
            }
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .localDecl(name, isMutable, typeAnnotation, initializer, isDelegated, isLateinit, range):
            return driver.localDeclChecker.inferLocalDeclExpr(
                id,
                name: name,
                isMutable: isMutable,
                typeAnnotation: typeAnnotation,
                initializer: initializer,
                isDelegated: isDelegated,
                isLateinit: isLateinit,
                range: range,
                ctx: ctx,
                locals: &locals
            )

        case let .localAssign(name, value, range):
            return driver.localDeclChecker.inferLocalAssignExpr(id, name: name, value: value, range: range, ctx: ctx, locals: &locals)

        case let .memberAssign(receiverExpr, calleeName, valueExpr, range):
            var assignCtx = ctx
            assignCtx.receiverConditionallyEvaluated = ctx.isConditionallyEvaluated
            if exprSpineContainsSafeMemberAccess(receiverExpr, ast: ast) {
                assignCtx.isConditionallyEvaluated = true
            }
            return inferMemberAssignExpr(
                id, receiver: receiverExpr, name: calleeName, value: valueExpr,
                range: range, ctx: assignCtx, locals: &locals
            )

        case let .safeMemberAssign(receiverExpr, calleeName, valueExpr, range):
            var assignCtx = ctx
            assignCtx.receiverConditionallyEvaluated = ctx.isConditionallyEvaluated
            assignCtx.isConditionallyEvaluated = true
            return inferMemberAssignExpr(
                id, receiver: receiverExpr, name: calleeName, value: valueExpr,
                range: range, ctx: assignCtx, locals: &locals, isSafeCall: true
            )

        case let .indexedAccess(receiverExpr, indices, range):
            var indexCtx = ctx
            indexCtx.receiverConditionallyEvaluated = ctx.isConditionallyEvaluated
            let receiverHasUnguardedSafeAccess = isUnguardedSafeIndexedAccessReceiver(receiverExpr, ast: ast)
            if exprSpineContainsSafeMemberAccess(receiverExpr, ast: ast) {
                indexCtx.isConditionallyEvaluated = true
            }
            return driver.localDeclChecker.inferIndexedAccessExpr(
                id,
                receiverExpr: receiverExpr,
                indices: indices,
                range: range,
                expectedType: expectedType,
                ctx: indexCtx,
                locals: &locals,
                isSafeChain: receiverHasUnguardedSafeAccess
            )

        case let .indexedAssign(receiverExpr, indices, valueExpr, range):
            var assignCtx = ctx
            assignCtx.receiverConditionallyEvaluated = ctx.isConditionallyEvaluated
            if exprSpineContainsSafeMemberAccess(receiverExpr, ast: ast) {
                assignCtx.isConditionallyEvaluated = true
            }
            return driver.localDeclChecker.inferIndexedAssignExpr(id, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: assignCtx, locals: &locals)

        case let .returnExpr(value, label, range):
            let lambdaReturnScope = label.flatMap { label in
                ctx.lambdaReturnScopes.last { $0.label == label }
            }
            let targetsFunction = label.map { label in
                !ctx.hasLambdaLabel(label)
                    && ctx.enclosingFunctionSymbol.flatMap { sema.symbols.symbol($0)?.name } == label
            } ?? (ctx.lambdaDepth > 0)
            let targetsEnclosingFunction = label == nil || targetsFunction
            let isProhibitedPropertyInitializerReturn =
                ctx.isInPropertyInitializer && targetsEnclosingFunction
            let returnsFromConstructor = ctx.enclosingFunctionSymbol.flatMap {
                sema.symbols.symbol($0)?.kind == .constructor
            } ?? false
            let returnsFromInitBlock = ctx.returnTargetIsInitBlock && (label == nil || targetsFunction)
            let isConstructorReturnWithValue = returnsFromConstructor
                && value != nil
                && (label == nil || targetsFunction)
            if returnsFromInitBlock {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0312",
                    "Returns are not allowed in initializer blocks.",
                    range: range
                )
            }
            if let lambdaReturnScope,
               let targetIndex = ctx.enclosingLambdaExprIDs.lastIndex(of: lambdaReturnScope.exprID) {
                sema.bindings.bindLambdaReturn(
                    id, target: lambdaReturnScope.exprID,
                    lambdaPath: Array(ctx.enclosingLambdaExprIDs.dropFirst(targetIndex + 1))
                )
            }
            if isProhibitedPropertyInitializerReturn {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0042",
                    "'return' is prohibited here.",
                    range: range
                )
            } else if targetsFunction, let functionSymbol = ctx.enclosingFunctionSymbol {
                sema.bindings.bindFunctionReturn(id, symbol: functionSymbol, lambdaPath: ctx.enclosingLambdaExprIDs)
            } else if label == nil,
                      (ctx.lambdaDepth > 0 || ctx.enclosingFunctionSymbol == nil),
                      !returnsFromInitBlock {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0042",
                    "'return' does not reference an enclosing function.",
                    range: range
                )
            } else if let label, !ctx.hasLambdaLabel(label) {
                let labelName = interner.resolve(label)
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0042",
                    ctx.hasNonFunctionLambdaLabel(label)
                        ? "Target label '\(labelName)' does not denote a function."
                        : "'return@\(labelName)' does not reference a valid enclosing lambda or function.",
                    range: range
                )
            }
            if ctx.enclosingFunctionProhibitsExpressionBodyReturn,
               ctx.lambdaDepth == 0,
               label == nil || targetsFunction
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0311",
                    "Returns are not allowed for functions with expression body.",
                    range: range
                )
            }
            // An unlabeled `return` always targets the enclosing named
            // function, whether or not it sits inside a lambda -- so its
            // value must be inferred against *that* function's declared
            // return type, never the ambient `expectedType` threaded down
            // through whatever expression happens to syntactically contain
            // it (a lambda's own expected Boolean/result type, but equally
            // an elvis/if/when/try branch's expected type propagated in from
            // an outer assignment: `x = if (c) 1 else return null` inside a
            // function returning `Int?` must check `return null` against
            // `Int?`, not `x`'s declared `Int`).
            let returnExpectedType: TypeID? = if isConstructorReturnWithValue {
                nil
            } else if label == nil || targetsFunction,
                                                    let enclosingFunctionReturnType = ctx.enclosingFunctionReturnType
            {
                enclosingFunctionReturnType
            } else if let lambdaReturnScope {
                lambdaReturnScope.expectedReturnType
            } else {
                expectedType
            }
            if let value {
                let resolved = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: returnExpectedType)
                driver.recordGenericCallConsumer(
                    value, type: returnExpectedType == sema.types.unitType ? nil : returnExpectedType
                )
                if isConstructorReturnWithValue, resolved != sema.types.unitType {
                    sema.diagnostics.error(
                        "KSWIFTK-SEMA-0042",
                        "'return' with a value is not allowed in a constructor.",
                        range: range
                    )
                }
                if (!(label == nil || targetsFunction) || !ctx.isPropertyGetterReturn),
                   returnExpectedType == sema.types.unitType,
                   sema.types.makeNonNullable(resolved) == sema.types.unitType
                {
                    sema.bindings.markUnitReturnCoercion(value)
                }
                lambdaReturnScope?.returnValueTypes[id] = driver.helpers.retypeClassNameAsCompanionValue(
                    value, currentType: resolved, ast: ast, sema: sema
                ) ?? resolved
                let returnsRangeExpr = returnExpectedType.map {
                    driver.helpers.rangeExprMatchesDeclaredElementType(
                        bodyExprID: value,
                        bodyType: resolved,
                        declaredType: $0,
                        sema: sema,
                        interner: interner
                    )
                } ?? false
                if let returnExpectedType, !returnsRangeExpr {
                    driver.emitSubtypeConstraint(
                        left: resolved,
                        right: returnExpectedType,
                        range: range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.sema.diagnostics,
                        secondaryRanges: enclosingDeclSiteRanges(ctx: ctx),
                        suppressPlatformWarning: ctx.suppressPlatformReturnWarning,
                        diagnosticCode: "KSWIFTK-SEMA-0469",
                        failureMessage: "Return type mismatch."
                    )
                }
            } else {
                lambdaReturnScope?.returnValueTypes[id] = sema.types.unitType
                if let returnExpectedType {
                    driver.emitSubtypeConstraint(
                        left: sema.types.unitType,
                        right: returnExpectedType,
                        range: range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.sema.diagnostics,
                        secondaryRanges: enclosingDeclSiteRanges(ctx: ctx),
                        suppressPlatformWarning: ctx.suppressPlatformReturnWarning,
                        diagnosticCode: "KSWIFTK-SEMA-0469",
                        failureMessage: "Return type mismatch."
                    )
                }
            }
            if let lambdaReturnScope, ctx.enclosingTryFinallyDepth == 0 {
                lambdaReturnScope.returnLocalStates.append(locals)
            }
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return driver.controlFlowChecker.inferIfExpr(id, condition: condition, thenExpr: thenExpr, elseExpr: elseExpr, ctx: ctx, locals: &locals, expectedType: expectedType, isStatementContext: isStatementContext)

        case let .tryExpr(body, catchClauses, finallyExpr, _):
            return driver.controlFlowChecker.inferTryExpr(id, body: body, catchClauses: catchClauses, finallyExpr: finallyExpr, ctx: ctx, locals: &locals, expectedType: expectedType, isStatementContext: isStatementContext)

        case let .binary(op, lhsID, rhsID, range):
            return inferBinaryExpr(
                id, op: op, lhsID: lhsID, rhsID: rhsID, range: range,
                ctx: ctx, locals: &locals, expectedType: expectedType,
                isStatementContext: isStatementContext
            )

        case let .call(calleeID, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, scope: ctx.scope, diagnostics: ctx.sema.diagnostics, inferenceContext: ctx, usageRange: range)
            var callCtx = ctx
            callCtx.isCallResultDiscarded = isStatementContext && expectedType == nil
            callCtx.receiverConditionallyEvaluated = ctx.isConditionallyEvaluated
            if exprSpineContainsSafeMemberAccess(calleeID, ast: ast) {
                callCtx.isConditionallyEvaluated = true
            }
            return driver.callChecker.inferCallExpr(id, calleeID: calleeID, args: args, range: range, ctx: callCtx, locals: &locals, expectedType: expectedType, explicitTypeArgs: explicitTypeArgs)

        case let .memberCall(receiverID, calleeName, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, scope: ctx.scope, diagnostics: ctx.sema.diagnostics, inferenceContext: ctx, usageRange: range)
            var callCtx = ctx
            callCtx.isCallResultDiscarded = isStatementContext && expectedType == nil
            callCtx.receiverConditionallyEvaluated = ctx.isConditionallyEvaluated
            if exprSpineContainsSafeMemberAccess(receiverID, ast: ast) {
                callCtx.isConditionallyEvaluated = true
            }
            return driver.callChecker.inferMemberCallExpr(
                id, receiverID: receiverID, calleeName: calleeName,
                args: args, range: range, ctx: callCtx, locals: &locals,
                expectedType: expectedType, explicitTypeArgs: explicitTypeArgs
            )

        case let .unaryExpr(op, operandID, range):
            let type: TypeID
            switch op {
            case .not:
                let inferredOperand = driver.inferExpr(operandID, ctx: ctx, locals: &locals)
                let operandType = sema.types.capturedOperatorReceiverType(
                    of: inferredOperand
                )

                if let overloadedType = inferUnaryOperatorExpr(
                    id,
                    op: op,
                    operandType: operandType,
                    hasCapturedOperand: sema.types.containsCapturedTypes(inferredOperand),
                    range: range,
                    ctx: ctx,
                    locals: locals,
                    expectedType: expectedType
                ) {
                    return overloadedType
                }
                driver.emitSubtypeConstraint(
                    left: operandType, right: boolType,
                    range: ast.arena.exprRange(operandID) ?? range,
                    solver: ConstraintSolver(), sema: sema,
                    diagnostics: ctx.sema.diagnostics
                )
                if case .primitive(.boolean, .platformType) = sema.types.kind(of: operandType) {
                    let nonNullOperandType = sema.types.makeNonNullable(operandType)
                    driver.recordPlatformNullAssertion(
                        operandID,
                        sourceType: operandType,
                        targetType: nonNullOperandType
                    )
                }
                type = boolType
            case .unaryPlus, .unaryMinus:
                if case let .intLiteral(literalValue, _) = ast.arena.expr(operandID) {
                    let foldedValue = op == .unaryMinus ? -literalValue : literalValue
                    type = intLiteralType(
                        expectedType: expectedType,
                        sema: sema,
                        defaultType: intType,
                        literalValue: foldedValue
                    )
                    _ = driver.inferExpr(
                        operandID, ctx: ctx, locals: &locals,
                        expectedType: op == .unaryPlus ? type : nil
                    )
                } else {
                    let inferredOperand = driver.inferExpr(operandID, ctx: ctx, locals: &locals, expectedType: expectedType)
                    let operandType = sema.types.capturedOperatorReceiverType(
                        of: inferredOperand
                    )
                    if let overloadedType = inferUnaryOperatorExpr(
                        id,
                        op: op,
                        operandType: operandType,
                        hasCapturedOperand: sema.types.containsCapturedTypes(inferredOperand),
                        range: range,
                        ctx: ctx,
                        locals: locals,
                        expectedType: expectedType
                    ) {
                        // The resolved `unaryPlus`/`unaryMinus` member call keeps
                        // the operand as its receiver, so a platform-primitive
                        // operand needs the same runtime null assertion the
                        // fallback path below records — `-list.pollFirst()`
                        // on an empty container must NPE like the JVM unbox.
                        if case .primitive(_, .platformType) = sema.types.kind(of: operandType) {
                            driver.recordPlatformNullAssertion(
                                operandID,
                                sourceType: operandType,
                                targetType: sema.types.makeNonNullable(operandType)
                            )
                        }
                        return overloadedType
                    }
                    if case .primitive(_, .platformType) = sema.types.kind(of: operandType) {
                        type = sema.types.makeNonNullable(operandType)
                        driver.recordPlatformNullAssertion(operandID, sourceType: operandType, targetType: type)
                    } else {
                        type = operandType
                    }
                }
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case let .isCheck(exprID, typeRefID, negated, range):
            let subjectType = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            // `is`/`!is` tests the raw operand — the JVM emits instanceof on
            // the erased value (or a null check when the static type already
            // proves it), never a claim checkcast first (KUU-3893). A `when`
            // subject is different: its synthesized `is` conditions reuse the
            // subject ExprID directly, and the JVM has already claimed that
            // value into a typed local before the checks run — the subject's
            // own boundary claim must stand.
            if exprID != ctx.whenConditionSubject {
                driver.recordGenericCallConsumer(exprID, type: sema.types.nullableAnyType)
            }
            let targetType = driver.helpers.resolveTypeRef(
                typeRefID,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.sema.diagnostics,
                inferenceContext: ctx,
                usageRange: range,
                allowBareGenericTypeAliasProjection: true
            )
            let subjectNonNull = sema.types.makeNonNullable(subjectType)
            let targetNonNull = sema.types.makeNonNullable(targetType)
            if case .functionType = sema.types.kind(of: targetType),
               !sema.types.isSubtype(
                   subjectNonNull,
                   targetNonNull
               )
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-ERASED-TYPE",
                    "Cannot check for instance of erased type '\(sema.types.renderType(targetType))': function parameter and return types are not available at runtime.",
                    range: range
                )
            }
            if case let .typeParam(typeParam) = sema.types.kind(of: targetType),
               let typeParameterSymbol = sema.symbols.symbol(typeParam.symbol),
               !typeParameterSymbol.flags.contains(.reifiedTypeParameter)
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0084",
                    "Cannot check for instance of non-reified type parameter '\(interner.resolve(typeParameterSymbol.name))'.",
                    range: range
                )
            }
            let hasErasedTypeArguments: Bool
            if case let .classType(classType) = sema.types.kind(of: targetType) {
                hasErasedTypeArguments = (classType.args + classType.enclosingTypeArgs).contains { arg in
                    if case .star = arg { return false }
                    return true
                }
            } else {
                hasErasedTypeArguments = false
            }
            let subjectHasKnownTargetInstantiation: Bool
            if sema.types.isSubtype(subjectNonNull, targetNonNull) {
                subjectHasKnownTargetInstantiation = true
            } else if case let .classType(subjectClass) = sema.types.kind(of: subjectNonNull),
                      case let .classType(targetClass) = sema.types.kind(of: targetNonNull),
                      targetClass.enclosingTypeArgs.allSatisfy({ arg in
                          if case .star = arg { return true }
                          return false
                      }),
                      let inferredArgs = sema.types.narrowedSubtypeArgs(
                          forSubtype: targetClass.classSymbol,
                          givenSupertype: subjectClass.classSymbol,
                          supertypeArgs: subjectClass.args
                      ),
                      inferredArgs.count == targetClass.args.count
            {
                subjectHasKnownTargetInstantiation = zip(targetClass.args, inferredArgs).allSatisfy { targetArg, inferredArg in
                    switch targetArg {
                    case .star:
                        return true
                    case let .invariant(targetArgType), let .out(targetArgType), let .in(targetArgType):
                        guard case let .invariant(inferredArgType) = inferredArg else { return false }
                        return targetArgType == inferredArgType
                    }
                }
            } else {
                subjectHasKnownTargetInstantiation = false
            }
            if hasErasedTypeArguments,
               subjectType != sema.types.errorType,
               targetType != sema.types.errorType,
               !subjectHasKnownTargetInstantiation
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-ERASED-TYPE",
                    "Cannot check for instance of erased type '\(sema.types.displayName(of: targetType, symbols: sema.symbols, interner: interner))'.",
                    range: range
                )
            }
            if subjectType != sema.types.errorType, targetType != sema.types.errorType {
                let nullEscape = sema.types.nullability(of: subjectType) == .nullable
                    && sema.types.nullability(of: targetType) == .nullable
                if !negated,
                   !nullEscape,
                   !isRangeRepresentationCompatible(
                       subjectExpr: exprID,
                       subjectType: subjectNonNull,
                       targetType: targetNonNull,
                       sema: sema,
                       interner: interner
                   ),
                   isDefinitelyDisjoint(subject: subjectNonNull, target: targetNonNull, sema: sema, interner: interner)
                {
                    if let severity = impossibleIsCheckSeverity(
                        subjectExpr: exprID,
                        narrowedSubjectType: subjectNonNull,
                        targetType: targetNonNull,
                        locals: locals,
                        ctx: ctx
                    ) {
                        ctx.sema.diagnostics.emit(Diagnostic(
                            severity: severity,
                            code: "KSWIFTK-SEMA-0415",
                            message: "check for instance is always 'false'.",
                            primaryRange: range,
                            secondaryRanges: []
                        ))
                    }
                }
            }
            sema.bindings.bindIsCheckTargetType(id, type: targetType)
            _ = targetType
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .asCast(exprID, typeRefID, isSafe, range):
            var targetType = driver.helpers.resolveTypeRef(
                typeRefID,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.sema.diagnostics,
                inferenceContext: ctx,
                usageRange: range,
                allowBareGenericTypeAliasProjection: true
            )
            var sourceType: TypeID
            let isDirectCall = switch ast.arena.expr(exprID) {
            case .call, .memberCall, .safeMemberCall: ast.arena.isExplicitCall(exprID)
            default: false
            }
            if isDirectCall, targetType != sema.types.errorType {
                let checkpoint = sema.diagnostics.checkpoint()
                var trialLocals = locals
                sourceType = driver.inferExpr(exprID, ctx: ctx, locals: &trialLocals)
                let errors = sema.diagnostics.diagnostics.dropFirst(checkpoint).filter { $0.severity == .error }
                let inferenceErrors: Set<String> = ["KSWIFTK-SEMA-INFER", "KSWIFTK-TYPE-0001"]
                if !errors.isEmpty, errors.allSatisfy({ inferenceErrors.contains($0.code) }) {
                    sema.diagnostics.rollback(to: checkpoint)
                    sema.bindings.removeExprBindings(exprID)
                    sourceType = driver.inferExpr(exprID, ctx: ctx, locals: &locals, expectedType: targetType)
                } else {
                    locals = trialLocals
                }
            } else {
                sourceType = driver.inferExpr(exprID, ctx: ctx, locals: &locals)
            }
            // The cast itself checks the erased value, including a safe cast.
            driver.recordGenericCallConsumer(exprID, type: sema.types.nullableAnyType)
            if case let .classType(targetClass) = sema.types.kind(of: targetType),
               targetClass.args.isEmpty,
               !sema.types.nominalTypeParameterSymbols(for: targetClass.classSymbol).isEmpty,
               case let .classType(sourceClass) = sema.types.kind(of: sema.types.makeNonNullable(sourceType)),
               let inferredArgs = sema.types.narrowedSubtypeArgs(
                   forSubtype: targetClass.classSymbol,
                   givenSupertype: sourceClass.classSymbol,
                   supertypeArgs: sourceClass.args
               )
            {
                targetType = sema.types.make(.classType(ClassType(
                    classSymbol: targetClass.classSymbol,
                    args: inferredArgs,
                    nullability: targetClass.nullability
                )))
            }
            let type: TypeID = if isSafe {
                sema.types.makeNullable(targetType)
            } else {
                targetType
            }
            sema.bindings.bindCastTargetType(id, type: targetType)
            let isNullToNullableCast = sourceType == sema.types.nullableNothingType
                && sema.types.nullability(of: targetType) == .nullable
            if let typeRef = ast.arena.typeRef(typeRefID),
               case let .named(_, argRefs, _) = typeRef,
               !argRefs.isEmpty,
               !isNullToNullableCast
            {
                let hasNonStarArg = argRefs.contains { arg in
                    if case .star = arg {
                        return false
                    }
                    return true
                }
                if hasNonStarArg {
                    let operatorText = isSafe ? "as?" : "as"
                    ctx.sema.diagnostics.warning(
                        "KSWIFTK-SEMA-UNCHECKED-CAST",
                        "Unchecked cast '\(operatorText)' to generic type erases type arguments at runtime.",
                        range: range
                    )
                }
            }
            if !ctx.isConditionallyEvaluated,
               !isSafe,
               let castSubjectExpr = ast.arena.expr(exprID),
               case let .nameRef(castVarName, _) = castSubjectExpr,
               let castLocal = locals[castVarName],
               driver.helpers.isStableLocalSymbol(castLocal.symbol, sema: sema)
            {
                let refinedType: TypeID = if sema.types.isSubtype(castLocal.0, targetType) {
                    castLocal.0
                } else if targetType == sema.types.anyType {
                    sema.types.definitelyNonNullForm(of: castLocal.0)
                } else if sema.types.isSubtype(targetType, castLocal.0) {
                    targetType
                } else {
                    sema.types.make(.intersection([castLocal.0, targetType]))
                }
                locals[castVarName] = (refinedType, castLocal.symbol, castLocal.isMutable, castLocal.isInitialized)
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case let .nullAssert(exprID, _):
            let operandType = driver.inferExpr(
                exprID, ctx: ctx, locals: &locals,
                expectedType: expectedType.map { sema.types.makeNullable($0) }
            )
            if expectedType == nil {
                // `x!!` only asserts non-null — the JVM emits checkNotNull on
                // the erased value without a claim checkcast (KUU-3893). An
                // expected type still claims it through the fallback below.
                driver.recordGenericCallConsumer(exprID, type: sema.types.anyType)
            }
            let type = sema.types.definitelyNonNullForm(of: operandType)
            if !ctx.isConditionallyEvaluated {
                let base = ctx.flowState.includingMembers(from: locals)
                let narrowed = ctx.dataFlow.narrowNonNull(
                    exprID, base: base, locals: locals, ast: ast, sema: sema, interner: interner
                )
                if narrowed != base { applyFlowStateToLocals(narrowed, locals: &locals, sema: sema) }
            }
            sema.bindings.bindExprType(id, type: type)
            return type

        case let .safeMemberCall(receiverID, calleeName, typeArgRefs, args, range):
            let explicitTypeArgs = driver.helpers.resolveExplicitTypeArgs(typeArgRefs, ast: ast, sema: sema, interner: interner, scope: ctx.scope, diagnostics: ctx.sema.diagnostics, inferenceContext: ctx, usageRange: range)
            var callCtx = ctx
            callCtx.isCallResultDiscarded = isStatementContext && expectedType == nil
            callCtx.receiverConditionallyEvaluated = ctx.isConditionallyEvaluated
            callCtx.isConditionallyEvaluated = true
            return driver.callChecker.inferSafeMemberCallExpr(
                id, receiverID: receiverID, calleeName: calleeName,
                args: args, range: range, ctx: callCtx, locals: &locals,
                expectedType: expectedType, explicitTypeArgs: explicitTypeArgs
            )

        case let .compoundAssign(op, name, valueExpr, range):
            return inferCompoundAssignExpr(id, op: op, name: name, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .indexedCompoundAssign(op, receiverExpr, indices, valueExpr, range):
            return driver.localDeclChecker.inferIndexedCompoundAssignExpr(id, op: op, receiverExpr: receiverExpr, indices: indices, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .memberCompoundAssign(op, receiverExpr, calleeName, valueExpr, range):
            return inferMemberCompoundAssignExpr(id, op: op, receiverExpr: receiverExpr, calleeName: calleeName, valueExpr: valueExpr, range: range, ctx: ctx, locals: &locals)

        case let .whenExpr(subjectID, branches, elseExpr, range):
            return driver.controlFlowChecker.inferWhenExpr(id, subjectID: subjectID, branches: branches, elseExpr: elseExpr, range: range, ctx: ctx, locals: &locals, expectedType: expectedType, isStatementContext: isStatementContext)

        case let .throwExpr(value, range):
            let operandType = driver.inferExpr(value, ctx: ctx, locals: &locals, expectedType: nil)
            // ATHROW consumes the erased value directly; no claim checkcast
            // precedes it on the JVM (KUU-3893).
            driver.recordGenericCallConsumer(value, type: sema.types.nullableAnyType)
            if operandType != sema.types.errorType,
               let throwableType = driver.helpers.throwableType(sema: sema, interner: ctx.interner),
               !sema.types.isSubtype(operandType, throwableType)
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0414",
                    "type mismatch: inferred type is '\(sema.types.displayName(of: operandType, symbols: sema.symbols, interner: ctx.interner))', but 'Throwable' was expected.",
                    range: range
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.nothingType)
            return sema.types.nothingType

        case let .lambdaLiteral(params, body, _, _):
            return inferLambdaLiteralExpr(
                id, params: params, body: body, ctx: ctx, locals: &locals,
                expectedType: expectedType, inferErasedReturnType: inferLambdaResultType
            )

        case let .objectLiteral(superTypes, declID, _):
            return inferObjectLiteralExpr(id, superTypes: superTypes, declID: declID, ctx: ctx, locals: &locals)

        case let .callableRef(receiver, member, range):
            return inferCallableRefExpr(id, receiver: receiver, member: member, range: range, ctx: ctx, locals: &locals, expectedType: expectedType)

        case let .blockExpr(statements, trailingExpr, _):
            let containsIncrementDecrementAssignment = statements.contains {
                ast.arena.isIncrementDecrement($0)
            }
            let preservesOuterDataFlow = ast.arena.isCallResultCompoundAssignmentBlock(id)
                || containsIncrementDecrementAssignment
            ctx.dataFlow.localStability.analyze(statements + (trailingExpr.map { [$0] } ?? []), ast: ast)
            let contextualAnonymousFunctionDecl: ExprID? = {
                guard ast.arena.isAnonymousFunction(id),
                      statements.count == 1,
                      let statement = statements.first,
                      let statementExpr = ast.arena.expr(statement),
                      case .localFunDecl = statementExpr
                else {
                    return nil
                }
                return statement
            }()
            let blockCtx = ctx.exportBlockLocalsForExpr == id ? ctx : ctx.copying(
                scope: BlockScope(parent: ctx.scope, symbols: sema.symbols)
            )
            var blockLocals = locals
            var reachedNothing = false
            for stmt in statements {
                if reachedNothing {
                    if let stmtRange = ast.arena.exprRange(stmt) {
                        ctx.sema.diagnostics.warning(
                            "KSWIFTK-SEMA-0096",
                            "Unreachable code.",
                            range: stmtRange
                        )
                    }
                    _ = driver.inferExpr(stmt, ctx: blockCtx, locals: &blockLocals, expectedType: nil, isStatementContext: true)
                    continue
                }
                let stmtExpectedType = stmt == contextualAnonymousFunctionDecl ? expectedType : nil
                let stmtType = driver.inferExpr(stmt, ctx: blockCtx, locals: &blockLocals, expectedType: stmtExpectedType, isStatementContext: true)
                if stmtType == sema.types.nothingType {
                    reachedNothing = true
                }
            }
            let resultType: TypeID
            if reachedNothing {
                if let trailingExpr {
                    if let trailingRange = ast.arena.exprRange(trailingExpr) {
                        ctx.sema.diagnostics.warning(
                            "KSWIFTK-SEMA-0096",
                            "Unreachable code.",
                            range: trailingRange
                        )
                    }
                    _ = driver.inferExpr(trailingExpr, ctx: blockCtx, locals: &blockLocals, expectedType: expectedType, isStatementContext: isStatementContext)
                }
                resultType = sema.types.nothingType
            } else if let trailingExpr {
                let tailType = driver.inferExpr(trailingExpr, ctx: blockCtx, locals: &blockLocals, expectedType: expectedType, isStatementContext: isStatementContext)
                resultType = driver.helpers.retypeClassNameAsCompanionValue(
                    trailingExpr, currentType: tailType, ast: ast, sema: sema
                ) ?? tailType
            } else {
                resultType = sema.types.unitType
            }
            if ctx.exportBlockLocalsForExpr == id {
                locals = blockLocals
            } else {
                for (name, outerLocal) in locals {
                    if let blockLocal = blockLocals.binding(named: name, matching: outerLocal.symbol),
                       (preservesOuterDataFlow
                           || (outerLocal.isMutable && sema.types.nullability(of: sema.symbols.propertyType(for: outerLocal.symbol) ?? outerLocal.type) == .nullable))
                           || (!outerLocal.isInitialized && blockLocal.isInitialized)
                    {
                        locals[name] = (blockLocal.type, outerLocal.symbol, outerLocal.isMutable, blockLocal.isInitialized)
                    }
                }
                locals.possiblyAssignedVals.formUnion(blockLocals.possiblyAssignedVals)
                locals.memberFlow = blockLocals.memberFlow
                locals.variableFacts = blockLocals.variableFacts
                locals.invalidatedVariableFacts = blockLocals.invalidatedVariableFacts
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case let .localFunDecl(name, receiverTypeRef, valueParams, returnTypeRef, body, isSuspend, range, typeParams, _):
            return driver.localDeclChecker.inferLocalFunDeclExpr(
                id,
                name: name,
                typeParams: typeParams,
                contextReceivers: ast.arena.localFunContextReceivers(for: id),
                isAnonymousFunction: ast.arena.isAnonymousFunction(id),
                receiverTypeRef: receiverTypeRef,
                valueParams: valueParams,
                returnTypeRef: returnTypeRef,
                body: body,
                isSuspend: isSuspend,
                expectedType: expectedType,
                range: range,
                ctx: ctx,
                locals: &locals
            )

        case let .localNominalDecl(declID, range):
            return inferLocalNominalDeclExpr(id, declID: declID, range: range, ctx: ctx, locals: &locals)

        case let .superRef(interfaceQualifier, label, range):
            return inferSuperRefExpr(
                id, interfaceQualifier: interfaceQualifier, label: label, range: range, ctx: ctx
            )

        case let .thisRef(label, range):
            return inferThisRefExpr(id, label: label, range: range, ctx: ctx, locals: locals)

        case let .inExpr(lhsID, rhsID, range):
            let lhsType = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            let rhsType = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            inferContainsCallBinding(
                exprID: id,
                elementExpr: lhsID,
                containerExpr: rhsID,
                elementType: lhsType,
                containerType: rhsType,
                range: range,
                ctx: ctx,
                locals: &locals
            )
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .notInExpr(lhsID, rhsID, range):
            let lhsType = driver.inferExpr(lhsID, ctx: ctx, locals: &locals)
            let rhsType = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            inferContainsCallBinding(
                exprID: id,
                elementExpr: lhsID,
                containerExpr: rhsID,
                elementType: lhsType,
                containerType: rhsType,
                range: range,
                ctx: ctx,
                locals: &locals
            )
            sema.bindings.bindExprType(id, type: boolType)
            return boolType

        case let .destructuringDecl(names, isMutable, initializer, range):
            return driver.controlFlowChecker.inferDestructuringDeclExpr(id, names: names, isMutable: isMutable, initializer: initializer, range: range, ctx: ctx, locals: &locals)

        case let .forDestructuringExpr(names, iterableExpr, bodyExpr, syntax, range):
            return driver.controlFlowChecker.inferForDestructuringExpr(
                id, names: names, iterableExpr: iterableExpr, bodyExpr: bodyExpr,
                syntax: syntax, range: range, ctx: ctx, locals: &locals
            )
        }
    }

    private func inferContainsCallBinding(
        exprID: ExprID,
        elementExpr: ExprID,
        containerExpr: ExprID,
        elementType: TypeID,
        containerType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        let containsName = interner.intern("contains")

        func containsExtensionCandidates(receiverType: TypeID) -> [SymbolID] {
            func visibleExtensions(_ candidates: [SymbolID]) -> [SymbolID] {
                ctx.filterByVisibility(candidates).visible.filter {
                    sema.symbols.symbol($0)?.flags.contains(.operatorFunction) == true
                        && sema.symbols.functionSignature(for: $0)?.receiverType != nil
                        && !isHiddenByDeprecationOrVersionAnnotation($0, symbols: sema.symbols)
                }
            }
            let extensions = visibleExtensions(ctx.cachedScopeLookup(containsName))
            if !ctx.resolver.probeCall(
                candidates: extensions,
                call: CallExpr(range: range, calleeName: containsName, args: [CallArg(type: elementType)], isOperatorCall: true),
                expectedType: nil,
                implicitReceiverType: receiverType,
                ctx: ctx.sema
            ).viableCandidates.isEmpty {
                return extensions
            }
            return visibleExtensions(ctx.scope.lookupMergingChain(containsName))
        }

        func hasApplicableContainsExtension(receiverType: TypeID) -> Bool {
            !ctx.resolver.probeCall(
                candidates: containsExtensionCandidates(receiverType: receiverType),
                call: CallExpr(range: range, calleeName: containsName, args: [CallArg(type: elementType)], isOperatorCall: true),
                expectedType: nil,
                implicitReceiverType: receiverType,
                ctx: ctx.sema
            ).viableCandidates.isEmpty
        }

        let nullableRangeReceiver: TypeID? = {
            guard sema.types.nullability(of: elementType) == .nullable else { return nil }
            if let concrete = driver.callChecker.sourceLevelRangeMemberLookupType(
                receiverExpr: containerExpr, receiverType: containerType, sema: sema, interner: interner
            ) {
                return concrete
            }
            for name in ["ClosedRange", "OpenEndRange"] {
                guard let symbol = sema.symbols.lookup(fqName: ["kotlin", "ranges", name].map(interner.intern)) else { continue }
                let rangeType = sema.types.make(.classType(ClassType(classSymbol: symbol, args: [.star], nullability: .nonNull)))
                if sema.types.isSubtype(containerType, rangeType) { return containerType }
            }
            return nil
        }()
        if let sourceReceiver = nullableRangeReceiver {
            let call = CallExpr(range: range, calleeName: containsName, args: [CallArg(type: elementType)], isOperatorCall: true)
            let members = driver.helpers.collectMemberFunctionCandidates(
                named: containsName, receiverType: sourceReceiver, sema: sema, interner: interner
            )
            let memberResult = ctx.resolver.resolveCall(
                candidates: members, call: call, expectedType: nil,
                implicitReceiverType: sourceReceiver, ctx: ctx.sema
            )
            let extensions = containsExtensionCandidates(receiverType: sourceReceiver)
            let resolved = memberResult.chosenCallee != nil ? memberResult : ctx.resolver.resolveCall(
                candidates: extensions, call: call, expectedType: nil,
                implicitReceiverType: sourceReceiver, ctx: ctx.sema
            )
            if let chosen = resolved.chosenCallee {
                sema.bindings.bindCall(exprID, binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: resolved.substitutedTypeArguments
                        .sorted { $0.key.rawValue < $1.key.rawValue }.map { $0.value },
                    parameterMapping: resolved.parameterMapping
                ))
            } else if let diagnostic = resolved.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
            }
            return
        }

        if let floatingPointRangeReceiver = driver.callChecker.floatingPointRangeArgumentType(
            containerExpr,
            ast: ctx.ast,
            sema: sema,
            interner: interner
        ) {
            let call = CallExpr(range: range, calleeName: containsName, args: [CallArg(type: elementType)], isOperatorCall: true)
            let members = driver.helpers.collectMemberFunctionCandidates(
                named: containsName,
                receiverType: floatingPointRangeReceiver,
                sema: sema,
                interner: interner
            )
            let memberResult = ctx.resolver.resolveCall(
                candidates: members,
                call: call,
                expectedType: nil,
                implicitReceiverType: floatingPointRangeReceiver,
                ctx: ctx.sema
            )
            let extensions = containsExtensionCandidates(receiverType: floatingPointRangeReceiver)
            let extensionResult = extensions.isEmpty ? nil : ctx.resolver.resolveCall(
                candidates: extensions,
                call: call,
                expectedType: nil,
                implicitReceiverType: floatingPointRangeReceiver,
                ctx: ctx.sema
            )
            let resolved = memberResult.chosenCallee != nil ? memberResult : extensionResult ?? memberResult
            if let chosen = resolved.chosenCallee {
                sema.bindings.bindCall(exprID, binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: resolved.substitutedTypeArguments
                        .sorted { $0.key.rawValue < $1.key.rawValue }.map { $0.value },
                    parameterMapping: resolved.parameterMapping
                ))
            } else if let diagnostic = resolved.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
            } else if let expectedElementType = driver.helpers.rangeLikeDeclaredElementType(
                for: floatingPointRangeReceiver,
                sema: sema,
                interner: interner
            ) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "Argument type mismatch: expected '\(sema.types.renderType(expectedElementType))', got '\(sema.types.renderType(elementType))'.",
                    range: ctx.ast.arena.exprRange(elementExpr)
                )
            }
            return
        }

        // A `downTo` expression materializes a progression, not a range. Int
        // `downTo` already binds the nominal IntProgression type; non-Int
        // operands keep the scalar range marker, so member-call dispatch still
        // needs the progression kind here. Binding the *Range member would
        // emit a call whose receiver type can never hold the materialized
        // progression (a JVM invokevirtual of IntRange.contains on an
        // IntProgression fails verification).
        let membershipRangeKind = MemberRuntimeDispatch.memberCallReceiverKind(
            MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: containerExpr,
                receiverType: containerType,
                sema: sema,
                interner: interner
            ),
            receiverExpr: containerExpr,
            ast: ctx.ast
        )

        if let rangeSourceReceiverType = driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ),
        membershipRangeKind == .intRange {
            if sema.types.makeNonNullable(elementType) == sema.types.intType {
                let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: containsName,
                    receiverType: rangeSourceReceiverType,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.flags.contains(.operatorFunction),
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else { return false }
                    return signature.parameterTypes.count == 1
                }
                let memberCall = ctx.resolver.resolveCall(
                    candidates: memberCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)],
                        isOperatorCall: true
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.sema
                )
                if let chosen = memberCall.chosenCallee {
                    sema.bindings.bindCall(
                        exprID,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: memberCall.substitutedTypeArguments
                                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                .map { _, value in value },
                            parameterMapping: memberCall.parameterMapping
                        )
                    )
                    return
                }
            }
            let scopedRangeUserCandidates = driver.callChecker
                .collectScopedRangeUserExtensionCandidates(
                    named: containsName,
                    receiverType: rangeSourceReceiverType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                )
                .filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.flags.contains(SymbolFlags.operatorFunction)
                    else {
                        return false
                    }
                    return driver.callChecker.isIntRangeCrossTypeContainsCandidate(
                        candidate,
                        sema: sema
                    )
                }
            if !scopedRangeUserCandidates.isEmpty {
                let resolved = ctx.resolver.resolveCall(
                    candidates: scopedRangeUserCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)],
                        isOperatorCall: true
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.sema
                )
                if let chosen = resolved.chosenCallee {
                    sema.bindings.bindCall(
                        exprID,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: resolved.substitutedTypeArguments
                                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                .map { _, value in value },
                            parameterMapping: resolved.parameterMapping
                        )
                    )
                    return
                }
                let hasBundledRangeCandidate = driver.callChecker
                    .hasIntRangeSourceBackedContainsCandidate(
                        receiverType: rangeSourceReceiverType,
                        argumentType: sema.types.makeNonNullable(elementType),
                        sema: sema,
                        interner: interner
                    )
                let rangeMemberCandidates = driver.helpers
                    .collectMemberFunctionCandidates(
                        named: containsName,
                        receiverType: rangeSourceReceiverType,
                        sema: sema,
                        interner: interner
                    )
                    .filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.flags.contains(SymbolFlags.operatorFunction),
                              let signature = sema.symbols.functionSignature(for: candidate)
                        else {
                            return false
                        }
                        return signature.parameterTypes.count == 1
                    }
                // Viability, not a unique winner: a receiver that conforms to
                // both ClosedRange and OpenEndRange offers the same `contains`
                // member through two supertype paths, which resolveCall reports
                // as ambiguous. This check only decides whether the bundled
                // member surface can handle the call, so probe for at least one
                // applicable member instead.
                let hasApplicableRangeMember = !ctx.resolver.probeCall(
                    candidates: rangeMemberCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)],
                        isOperatorCall: true
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.sema
                ).viableCandidates.isEmpty
                if !hasBundledRangeCandidate,
                   !hasApplicableRangeMember,
                   !hasApplicableContainsExtension(receiverType: rangeSourceReceiverType),
                   let diagnostic = resolved.diagnostic
                {
                    ctx.sema.diagnostics.emit(diagnostic)
                    return
                }
            }
        }

        if let rangeSourceReceiverType = driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ),
        MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ) == .uintRange {
            if sema.types.makeNonNullable(elementType) == sema.types.uintType {
                let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: containsName,
                    receiverType: rangeSourceReceiverType,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.flags.contains(.operatorFunction),
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else { return false }
                    return signature.parameterTypes.count == 1
                }
                let memberCall = ctx.resolver.resolveCall(
                    candidates: memberCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)],
                        isOperatorCall: true
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.sema
                )
                if let chosen = memberCall.chosenCallee {
                    sema.bindings.bindCall(
                        exprID,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: memberCall.substitutedTypeArguments
                                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                .map { _, value in value },
                            parameterMapping: memberCall.parameterMapping
                        )
                    )
                    return
                }
            }
            let scopedRangeUserCandidates = driver.callChecker
                .collectScopedRangeUserExtensionCandidates(
                    named: containsName,
                    receiverType: rangeSourceReceiverType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                )
                .filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.flags.contains(SymbolFlags.operatorFunction)
                    else {
                        return false
                    }
                    return driver.callChecker.isUIntRangeCrossTypeContainsCandidate(
                        candidate,
                        sema: sema
                    )
                }
            if !scopedRangeUserCandidates.isEmpty {
                let resolved = ctx.resolver.resolveCall(
                    candidates: scopedRangeUserCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)],
                        isOperatorCall: true
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.sema
                )
                if let chosen = resolved.chosenCallee {
                    sema.bindings.bindCall(
                        exprID,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: resolved.substitutedTypeArguments
                                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                .map { _, value in value },
                            parameterMapping: resolved.parameterMapping
                        )
                    )
                    return
                }
                let hasBundledRangeCandidate = driver.callChecker
                    .hasIntRangeSourceBackedContainsCandidate(
                        receiverType: rangeSourceReceiverType,
                        argumentType: sema.types.makeNonNullable(elementType),
                        sema: sema,
                        interner: interner
                    )
                let rangeMemberCandidates = driver.helpers
                    .collectMemberFunctionCandidates(
                        named: containsName,
                        receiverType: rangeSourceReceiverType,
                        sema: sema,
                        interner: interner
                    )
                    .filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.flags.contains(SymbolFlags.operatorFunction),
                              let signature = sema.symbols.functionSignature(for: candidate)
                        else {
                            return false
                        }
                        return signature.parameterTypes.count == 1
                    }
                // Viability, not a unique winner: a receiver that conforms to
                // both ClosedRange and OpenEndRange offers the same `contains`
                // member through two supertype paths, which resolveCall reports
                // as ambiguous. This check only decides whether the bundled
                // member surface can handle the call, so probe for at least one
                // applicable member instead.
                let hasApplicableRangeMember = !ctx.resolver.probeCall(
                    candidates: rangeMemberCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: containsName,
                        args: [CallArg(type: elementType)],
                        isOperatorCall: true
                    ),
                    expectedType: nil,
                    implicitReceiverType: rangeSourceReceiverType,
                    ctx: ctx.sema
                ).viableCandidates.isEmpty
                if !hasBundledRangeCandidate,
                   !hasApplicableRangeMember,
                   !hasApplicableContainsExtension(receiverType: rangeSourceReceiverType),
                   let diagnostic = resolved.diagnostic
                {
                    ctx.sema.diagnostics.emit(diagnostic)
                    return
                }
            }
        }

        if let rangeSourceReceiverType = driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ),
        MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ) == .longRange {
            let isLongLiteral = driver.callChecker.isContextualizableIntegerLiteral(
                elementExpr,
                ast: ctx.ast
            )
            let resolvedElementType: TypeID = if isLongLiteral {
                driver.inferExpr(
                    elementExpr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: sema.types.longType
                )
            } else {
                elementType
            }
            if isLongLiteral,
               let member = driver.callChecker.longRangeContainsMemberSymbol(
                   receiverType: rangeSourceReceiverType,
                   sema: sema,
                   interner: interner
               )
            {
                sema.bindings.bindCall(
                    exprID,
                    binding: CallBinding(
                        chosenCallee: member,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                return
            }
            if !isLongLiteral {
                let scopedRangeUserCandidates = driver.callChecker
                    .collectScopedRangeUserExtensionCandidates(
                        named: containsName,
                        receiverType: rangeSourceReceiverType,
                        ctx: ctx,
                        sema: sema,
                        interner: interner
                    )
                    .filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.flags.contains(SymbolFlags.operatorFunction),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              signature.parameterTypes.count == 1,
                              signature.parameterTypes[0] == sema.types.makeNonNullable(resolvedElementType)
                        else {
                            return false
                        }
                        return [sema.types.byteType, sema.types.intType, sema.types.shortType]
                            .contains(signature.parameterTypes[0])
                    }
                if !scopedRangeUserCandidates.isEmpty {
                    let resolved = ctx.resolver.resolveCall(
                        candidates: scopedRangeUserCandidates,
                        call: CallExpr(
                            range: range,
                            calleeName: containsName,
                            args: [CallArg(type: resolvedElementType)],
                            isOperatorCall: true
                        ),
                        expectedType: nil,
                        implicitReceiverType: rangeSourceReceiverType,
                        ctx: ctx.sema
                    )
                    if let chosen = resolved.chosenCallee {
                        sema.bindings.bindCall(
                            exprID,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: resolved.substitutedTypeArguments
                                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                    .map { _, value in value },
                                parameterMapping: resolved.parameterMapping
                            )
                        )
                        return
                    }
                }
            }
            if let sourceSymbol = driver.callChecker.sourceRangeHOFSymbol(
                calleeName: containsName,
                rangeKind: .longRange,
                argCount: 1,
                argumentTypes: [sema.types.makeNonNullable(resolvedElementType)],
                argumentLabels: [nil],
                sema: sema,
                interner: interner
            ) {
                sema.bindings.bindCall(
                    exprID,
                    binding: CallBinding(
                        chosenCallee: sourceSymbol,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                return
            }
        }

        if driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ) != nil,
        MemberRuntimeDispatch.rangeReceiverKind(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ) == .ulongRange {
            let isUnsignedLiteral = driver.callChecker.isContextualizableUnsignedIntegerLiteral(
                elementExpr,
                ast: ctx.ast
            )
            let resolvedElementType: TypeID = if isUnsignedLiteral {
                driver.inferExpr(
                    elementExpr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: sema.types.ulongType
                )
            } else {
                elementType
            }
            if isUnsignedLiteral,
               let member = driver.callChecker.ulongRangeContainsMemberSymbol(
                   receiverType: driver.callChecker.sourceLevelRangeMemberLookupType(
                       receiverExpr: containerExpr,
                       receiverType: containerType,
                       sema: sema,
                       interner: interner
                   ) ?? containerType,
                   sema: sema,
                   interner: interner
               )
            {
                sema.bindings.bindCall(
                    exprID,
                    binding: CallBinding(
                        chosenCallee: member,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                return
            }
            if let sourceSymbol = driver.callChecker.sourceRangeHOFSymbol(
                calleeName: containsName,
                rangeKind: .ulongRange,
                argCount: 1,
                argumentTypes: [sema.types.makeNonNullable(resolvedElementType)],
                argumentLabels: [nil],
                sema: sema,
                interner: interner
            ) {
                sema.bindings.bindCall(
                    exprID,
                    binding: CallBinding(
                        chosenCallee: sourceSymbol,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                return
            }
        }

        // The bundled progressions declare `contains` as a kotlin.ranges
        // package extension rather than a class member, so neither the
        // same-element member path above nor the generic member-candidate
        // path below can see it — `x in progression` would silently fall back
        // to the kk_op_contains runtime stub. Bind the source-backed
        // extension directly when its parameter accepts the element type.
        if driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        ) != nil,
        let rangeKind = membershipRangeKind,
        [MemberDispatchReceiverKind.intProgression, .longProgression, .charProgression,
         .uintProgression, .ulongProgression].contains(rangeKind) {
            if let sourceSymbol = driver.callChecker.sourceRangeHOFSymbol(
                calleeName: containsName,
                rangeKind: rangeKind,
                argCount: 1,
                argumentTypes: [sema.types.makeNonNullable(elementType)],
                argumentLabels: [nil],
                sema: sema,
                interner: interner
            ) {
                sema.bindings.bindCall(
                    exprID,
                    binding: CallBinding(
                        chosenCallee: sourceSymbol,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                return
            }
        }

        // Primitive receivers normally use the generic runtime helper, but a
        // scoped `operator fun` extension must take precedence when applicable.
        // Recover nominal range types for generic Iterable.contains resolution.
        // String is `.stringStruct`, not `.classType` (KSWIFTK-INTERNAL-0001), but it does
        // have a bundled-Kotlin-source `contains` to dispatch to (KSP-408), so it must not
        // be skipped here — unlike genuine primitives/ranges, kk_op_contains has no String
        // case at all, and falling through to it would silently return false for every
        // `x in someString` regardless of the actual contents.
        let sourceRangeType = driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: containerExpr,
            receiverType: containerType,
            sema: sema,
            interner: interner
        )
        if let sourceRangeType,
           driver.helpers.rangeLikeDeclaredElementType(for: sourceRangeType, sema: sema, interner: interner)
               == sema.types.makeNonNullable(elementType)
        {
            return
        }
        let nonNullContainerType = sourceRangeType ?? sema.types.makeNonNullable(containerType)
        switch sema.types.kind(of: nonNullContainerType) {
        case .classType, .stringStruct, .primitive(_, _):
            break
        default:
            return
        }

        let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: containsName,
            receiverType: nonNullContainerType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(SymbolFlags.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1
            else {
                return false
            }
            return true
        }

        let scopeCandidates = containsExtensionCandidates(receiverType: nonNullContainerType).filter { candidate in
            guard !memberCandidates.contains(candidate),
                  let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(SymbolFlags.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let receiverType = signature.receiverType
            else {
                return false
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullContainerType,
                declaredReceiver: receiverType,
                sema: sema
            )
        }

        let syntheticExtensionCandidates = sema.symbols.lookupByShortName(containsName).filter { candidate in
            guard !memberCandidates.contains(candidate),
                  !scopeCandidates.contains(candidate),
                  let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(SymbolFlags.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let receiverType = signature.receiverType,
                  !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols)
            else {
                return false
            }
            if let parentID = sema.symbols.parentSymbol(for: candidate),
               let parentSym = sema.symbols.symbol(parentID),
               parentSym.kind == .property
            {
                return false
            }
            guard symbol.flags.contains(.synthetic) || sema.symbols.isSourceBackedSymbol(candidate) else {
                return false
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullContainerType,
                declaredReceiver: receiverType,
                sema: sema
            )
        }

        var candidates = memberCandidates
        candidates.append(contentsOf: scopeCandidates)
        candidates.append(contentsOf: syntheticExtensionCandidates)

        // Drop synthetic supertype candidates when a bundled source implementation
        // exists on a subtype. Overload resolution currently treats extension
        // functions as having no class type parameters, which makes a synthetic
        // Collection.contains look more specific than List.contains; prefer the
        // source member from the more-derived receiver.
        func receiverClassSymbol(of signature: FunctionSignature?) -> SymbolID? {
            guard let receiverType = signature?.receiverType else { return nil }
            let nonNull = sema.types.makeNonNullable(receiverType)
            guard case let .classType(classType) = sema.types.kind(of: nonNull) else {
                return nil
            }
            return classType.classSymbol
        }
        let sourceCandidates = candidates.filter { sema.symbols.isSourceBackedSymbol($0) }
        if !sourceCandidates.isEmpty {
            let sourceReceiverClasses = Set(sourceCandidates.compactMap { receiverClassSymbol(of: sema.symbols.functionSignature(for: $0)) })
            candidates = candidates.filter { candidate in
                guard sema.symbols.symbol(candidate) != nil,
                      !sema.symbols.isSourceBackedSymbol(candidate),
                      let candidateClass = receiverClassSymbol(of: sema.symbols.functionSignature(for: candidate))
                else {
                    return true
                }
                if sourceReceiverClasses.contains(candidateClass) {
                    return false
                }
                return !sourceReceiverClasses.contains(where: {
                    sema.types.isNominalSubtypeSymbol($0, of: candidateClass)
                })
            }
        }

        guard !candidates.isEmpty else { return }

        let integerLiteral = driver.callChecker.integerLiteralValues(elementExpr, ast: ctx.ast)
        let callArgs = [CallArg(
            type: elementType,
            signedIntegerLiteral: integerLiteral.signed,
            unsignedIntegerLiteral: integerLiteral.unsigned
        )]
        let call = CallExpr(range: range, calleeName: containsName, args: callArgs, isOperatorCall: true)
        let retainedMembers = candidates.filter { memberCandidates.contains($0) }
        if case .primitive = sema.types.kind(of: nonNullContainerType),
           ctx.resolver.probeCall(
               candidates: candidates,
               call: call,
               expectedType: nil,
               implicitReceiverType: nonNullContainerType,
               ctx: ctx.sema
           ).viableCandidates.isEmpty
        {
            return
        }
        let hasViableMember = !ctx.resolver.probeCall(
            candidates: retainedMembers,
            call: call,
            expectedType: nil,
            implicitReceiverType: nonNullContainerType,
            ctx: ctx.sema
        ).viableCandidates.isEmpty
        let resolved = ctx.resolver.resolveCall(
            candidates: hasViableMember ? retainedMembers : candidates,
            call: call,
            expectedType: nil,
            implicitReceiverType: nonNullContainerType,
            ctx: ctx.sema
        )

        guard let chosen = resolved.chosenCallee else {
            if let (_, symbol) = resolveClassTypeSymbol(nonNullContainerType, sema: sema),
               symbol.fqName.isEmpty
                   || symbol.fqName == [interner.intern("kotlin"), symbol.name],
               let arrayElement = driver.callChecker.primitiveArrayElementType(
                   className: symbol.name, sema: sema, interner: interner
               ),
               sema.types.isSubtype(elementType, arrayElement)
            {
                return
            }
            if let diagnostic = resolved.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
            }
            return
        }

        sema.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: resolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map { _, value in value },
                parameterMapping: resolved.parameterMapping
            )
        )
        driver.callChecker.contextualizeResolvedIntegerArguments(
            args: [CallArgument(expr: elementExpr)],
            resolved: resolved,
            ctx: ctx,
            locals: &locals
        )
    }

    func operatorFunctionNames(for op: BinaryOp, interner: StringInterner) -> [InternedString] {
        switch op {
        case .modulo:
            return [interner.intern("rem"), interner.intern("mod")]
        default:
            return [interner.intern(op.kotlinFunctionName)]
        }
    }

    func operatorFunctionNames(for op: UnaryOp, interner: StringInterner) -> [InternedString] {
        [interner.intern(op.kotlinFunctionName)]
    }

    func operatorFunctionNames(for op: CompoundAssignOp, interner: StringInterner) -> [InternedString] {
        switch op {
        case .modAssign:
            return [interner.intern("remAssign"), interner.intern("modAssign")]
        default:
            return [interner.intern(op.kotlinFunctionName)]
        }
    }

    func collectOperatorCandidates(
        names: [InternedString],
        receiverType: TypeID,
        call: CallExpr,
        locals: LocalBindings,
        ctx: TypeInferenceContext,
        allowsImplicitReceiverMemberExtensionOperators: Bool = true
    ) -> [SymbolID] {
        let sema = ctx.sema
        let interner = ctx.interner
        let isNonNullablePrimitive = if case .primitive(_, .nonNull) = sema.types.kind(of: receiverType) {
            true
        } else {
            false
        }
        let allowedOnPrimitive = names.contains { name in
            switch interner.resolve(name) {
            case "downTo", "rangeTo", "rangeUntil", "step":
                return true
            case "unaryPlus", "unaryMinus":
                return sema.types.isUnsigned(receiverType)
            default:
                return false
            }
        }
        guard !isNonNullablePrimitive || allowedOnPrimitive else { return [] }

        let knownNames = KnownCompilerNames(interner: interner)

        var candidates: [SymbolID] = []
        var seen: Set<SymbolID> = []

        func operatorCandidateMatchesReceiver(_ candidate: SymbolID) -> Bool {
            guard receiverType != sema.types.errorType else {
                return false
            }
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let signatureReceiverType = signature.receiverType
            else {
                return true
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: signatureReceiverType,
                sema: sema
            )
        }

        for name in names {
            let isInheritedOperator = knownNames.inheritedOperatorNames.contains(name)
            for candidate in driver.helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            ) {
                guard seen.insert(candidate).inserted,
                      let symbol = sema.symbols.symbol(candidate)
                else {
                    continue
                }
                guard operatorCandidateMatchesReceiver(candidate) else {
                    continue
                }
                if symbol.flags.contains(SymbolFlags.operatorFunction) {
                    candidates.append(candidate)
                } else if isInheritedOperator,
                          symbol.kind == .function,
                          symbol.flags.contains(SymbolFlags.overrideMember) {
                    candidates.append(candidate)
                }
            }

            guard isInheritedOperator else {
                continue
            }

            let nominalRoots = driver.helpers.allNominalSymbols(
                of: receiverType,
                types: sema.types,
                symbols: sema.symbols
            )
            var ownerQueue: [SymbolID] = nominalRoots
            var visitedOwners: Set<SymbolID> = []
            while !ownerQueue.isEmpty {
                let owner = ownerQueue.removeFirst()
                guard visitedOwners.insert(owner).inserted,
                      let ownerSymbol = sema.symbols.symbol(owner)
                else {
                    continue
                }
                ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
                let memberFQName = ownerSymbol.fqName + [name]
                for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                    guard seen.insert(candidate).inserted,
                          let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          symbol.flags.contains(.overrideMember),
                          sema.symbols.parentSymbol(for: candidate) == owner
                    else {
                        continue
                    }
                    guard operatorCandidateMatchesReceiver(candidate) else {
                        continue
                    }
                    candidates.append(candidate)
                }
            }
        }

        if !candidates.isEmpty {
            return candidates
        }

        let memberExtensionCandidates = allowsImplicitReceiverMemberExtensionOperators
            ? collectImplicitReceiverMemberExtensionOperatorCandidates(
                names: names,
                receiverType: receiverType,
                call: call,
                ctx: ctx
            )
            : []
        if !memberExtensionCandidates.isEmpty {
            return memberExtensionCandidates
        }

        let localExtensionCandidates = collectLocalOperatorExtensionCandidates(
            names: names, receiverType: receiverType, call: call, locals: locals, ctx: ctx
        )
        if !localExtensionCandidates.isEmpty {
            return localExtensionCandidates
        }

        for name in names {
            let scopedCandidates = ctx.scope.lookup(name, matching: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      sema.symbols.functionSignature(for: candidate)?.receiverType != nil
                else {
                    return false
                }
                if symbol.flags.contains(.expectDeclaration),
                   sema.symbols.actualSymbol(for: candidate) != nil {
                    return false
                }
                guard operatorCandidateMatchesReceiver(candidate) else {
                    return false
                }
                if symbol.flags.contains(.localFunction) {
                    return !ctx.resolver.probeCall(
                        candidates: [candidate], call: call, expectedType: nil,
                        implicitReceiverType: receiverType, ctx: sema
                    ).viableCandidates.isEmpty
                }
                return true
            })
            for candidate in scopedCandidates where seen.insert(candidate).inserted {
                candidates.append(candidate)
            }
        }

        if candidates.isEmpty {
            for name in names {
                for candidate in sema.symbols.lookupByShortName(name) {
                    guard seen.insert(candidate).inserted,
                          let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          symbol.flags.contains(.synthetic),
                          symbol.flags.contains(.operatorFunction),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let signatureReceiverType = signature.receiverType,
                          receiverType != sema.types.errorType,
                          driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                              callSiteReceiver: receiverType,
                              declaredReceiver: signatureReceiverType,
                              sema: sema
                          )
                    else {
                        continue
                    }
                    candidates.append(candidate)
                }
            }
        }

        if candidates.count > 1,
           case let .classType(actualClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
        {
            let exactReceiverCandidates = candidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiver))
                else {
                    return false
                }
                return receiverClassType.classSymbol == actualClassType.classSymbol
            }
            if !exactReceiverCandidates.isEmpty {
                return exactReceiverCandidates
            }
        }

        return candidates
    }

    private func collectImplicitReceiverMemberExtensionOperatorCandidates(
        names: [InternedString],
        receiverType: TypeID,
        call: CallExpr,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        guard receiverType != sema.types.errorType else { return [] }

        for dispatchReceiver in ctx.implicitReceiverMemberLookupEntries() {
            var eligible: [SymbolID] = []
            var seen: Set<SymbolID> = []
            for name in names {
                for candidate in driver.helpers.collectMemberFunctionCandidates(
                    named: name,
                    receiverType: dispatchReceiver.type,
                    sema: sema,
                    interner: ctx.interner
                ) where seen.insert(candidate).inserted {
                    guard !ctx.isCandidateBlockedByDslMarker(candidate),
                          let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          symbol.flags.contains(.operatorFunction),
                          sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil,
                          let declaredReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                          driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                              callSiteReceiver: receiverType,
                              declaredReceiver: declaredReceiver,
                              sema: sema
                          )
                    else {
                        continue
                    }
                    eligible.append(candidate)
                }
            }
            let visible = ctx.filterByVisibility(eligible).visible
            guard !visible.isEmpty else { continue }
            // Collection admits declared type parameters leniently so generic
            // member extensions stay reachable; claim the tier only when a
            // candidate is viable for this operand/argument pair. An
            // inapplicable member extension (`Ring<T>.T.plus` seen from an
            // unrelated `Foo` operand) must not shadow package-scope
            // extensions, and an inapplicable inner tier must not hide an
            // applicable outer receiver's operator (KUU-4420).
            let hasViableCandidate = !ctx.resolver.probeCall(
                candidates: visible,
                call: call,
                expectedType: nil,
                implicitReceiverType: receiverType,
                ctx: sema
            ).viableCandidates.isEmpty
            if hasViableCandidate {
                return visible
            }
        }

        return []
    }

    private func inferUnaryOperatorExpr(
        _ id: ExprID,
        op: UnaryOp,
        operandType: TypeID,
        hasCapturedOperand: Bool = false,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        expectedType: TypeID?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let lhsIsPrimitive = if case .primitive = sema.types.kind(of: operandType) { true } else { false }
        let operandIsNullableReceiver = sema.types.nullability(of: operandType) == .nullable
            && operandType != sema.types.errorType
        let operatorNames = operatorFunctionNames(for: op, interner: interner)
        let operatorCall = CallExpr(
            range: range,
            calleeName: operatorNames[0],
            args: [],
            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type),
            isOperatorCall: true
        )
        let operatorCandidates = collectOperatorCandidates(
            names: operatorNames,
            receiverType: operandType,
            call: operatorCall,
            locals: locals,
            ctx: ctx
        )
        let displayOperatorName = interner.resolve(operatorNames[0])

        if !operatorCandidates.isEmpty {
            let hasUninferredOperatorReturn = operatorCandidates.contains { candidate in
                driver.inferredReturnFunctions[candidate] != nil
                    && !driver.checkedInferredReturnFunctions.contains(candidate)
                    && !driver.checkingInferredReturnFunctions.contains(candidate)
            }
            if hasUninferredOperatorReturn {
                let inputSelection = ctx.resolver.resolveCall(
                    candidates: operatorCandidates,
                    call: operatorCall,
                    expectedType: nil,
                    implicitReceiverType: operandType,
                    ctx: sema
                )
                if inputSelection.diagnostic == nil,
                   let chosen = inputSelection.chosenCallee
                {
                    driver.inferFunctionReturnTypesIfNeeded(for: [chosen])
                }
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: operatorCandidates,
                call: operatorCall,
                expectedType: expectedType,
                implicitReceiverType: operandType,
                ctx: ctx.sema
            )
            if let diagnostic = resolved.diagnostic {
                if operandIsNullableReceiver {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0026",
                        "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                        range: range
                    )
                } else {
                    ctx.sema.diagnostics.emit(diagnostic)
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                ctx.sema.diagnostics.error(
                    operandIsNullableReceiver
                        ? "KSWIFTK-SEMA-0026"
                        : "KSWIFTK-SEMA-0002",
                    operandIsNullableReceiver
                        ? "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver."
                        : "No viable overload found for operator '\(displayOperatorName)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let returnType = driver.callChecker.bindCallAndResolveReturnType(
                id,
                chosen: chosen,
                resolved: resolved,
                sema: sema
            )
            if let dispatchOwner = sema.symbols.memberExtensionOwnerSymbol(for: chosen) {
                let dispatchReceiver = ctx.implicitReceiverMemberLookupEntries().first { entry in
                    driver.helpers.allNominalSymbols(
                        of: entry.type,
                        types: sema.types,
                        symbols: sema.symbols
                    ).contains(dispatchOwner)
                }
                sema.bindings.markImplicitReceiverMember(id, name: operatorNames[0])
                if let symbol = dispatchReceiver?.symbol {
                    sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: symbol)
                }
            }
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        if hasCapturedOperand, op == .unaryPlus || op == .unaryMinus,
           !sema.types.isBuiltinArithmeticOperand(operandType)
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002", "No viable overload found for operator '\(displayOperatorName)'.", range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        if operandIsNullableReceiver {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0026",
                "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if op == .unaryPlus || op == .unaryMinus,
           case let .primitive(primitive, _) = sema.types.kind(of: operandType),
           primitive == .boolean || primitive == .char
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(displayOperatorName)'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if (!lhsIsPrimitive || sema.types.isUnsigned(operandType)),
           operandType != sema.types.anyType,
           operandType != sema.types.nullableAnyType,
           operandType != sema.types.errorType
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(displayOperatorName)'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        return nil
    }

    private func inferWidenedIntegerConstantExpression(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID
    ) -> TypeID? {
        let sema = ctx.sema
        guard case let .primitive(primitive, _) = sema.types.kind(of: sema.types.makeNonNullable(expectedType)),
              primitive == .long || primitive == .byte || primitive == .short,
              let value = driver.callChecker.integerConstantExpressionValue(id, ast: ctx.ast)
        else { return nil }
        let widenedType = intLiteralType(
            expectedType: expectedType, sema: sema, defaultType: sema.types.intType, literalValue: value
        )
        guard widenedType != sema.types.intType else { return nil }
        _ = driver.inferExpr(id, ctx: ctx, locals: &locals, expectedType: nil)
        sema.bindings.bindConstExprValue(id, value: primitive == .long ? .longLiteral(value) : .intLiteral(value))
        sema.bindings.bindExprType(id, type: widenedType)
        if case let .unaryExpr(op, operandID, _) = ctx.ast.arena.expr(id) {
            let operandIsIntLiteral: Bool = if case .intLiteral = ctx.ast.arena.expr(operandID) {
                true
            } else {
                false
            }
            if op == .unaryPlus, operandIsIntLiteral {
                _ = driver.inferExpr(operandID, ctx: ctx, locals: &locals, expectedType: widenedType)
            }
        }
        return widenedType
    }

    private func intLiteralType(expectedType: TypeID?, sema: SemaModule, defaultType: TypeID, literalValue: Int64 = 0) -> TypeID {
        let inferredType = literalValue >= Int64(Int32.min) && literalValue <= Int64(Int32.max)
            ? defaultType
            : sema.types.longType
        guard let expectedType else { return inferredType }
        let nonNullExpected = sema.types.makeNonNullable(expectedType)
        guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullExpected) else {
            return inferredType
        }
        switch primitive {
        case .long: return sema.types.longType
        case .byte: return (literalValue >= -128 && literalValue <= 127) ? sema.types.byteType : inferredType
        case .short: return (literalValue >= -32768 && literalValue <= 32767) ? sema.types.shortType : inferredType
        default: return inferredType
        }
    }

    private func enclosingDeclSiteRanges(ctx: TypeInferenceContext) -> [SourceRange] {
        guard let declSymbol = ctx.currentDeclSymbol,
              let site = ctx.sema.symbols.symbol(declSymbol)?.declSite
        else {
            return []
        }
        return [site]
    }

    private func impossibleIsCheckSeverity(
        subjectExpr: ExprID,
        narrowedSubjectType: TypeID,
        targetType: TypeID,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> DiagnosticSeverity? {
        let sema = ctx.sema
        guard let reference = ctx.dataFlow.resolveStableReference(
            subjectExpr,
            locals: locals,
            ast: ctx.ast,
            sema: sema,
            interner: ctx.interner
        ),
        let declaredType = declaredIsCheckSubjectType(
            for: reference.symbol.properties.last ?? reference.symbol.root,
            sema: sema
        ),
        declaredType != sema.types.errorType
        else {
            return .error
        }
        let declaredNonNull = sema.types.makeNonNullable(declaredType)
        guard declaredNonNull != narrowedSubjectType,
              !isDefinitelyDisjoint(
                  subject: declaredNonNull,
                  target: targetType,
                  sema: sema,
                  interner: ctx.interner
              )
        else {
            return .error
        }
        return reference.isStable ? .warning : nil
    }

    private func declaredIsCheckSubjectType(for symbol: SymbolID, sema: SemaModule) -> TypeID? {
        if let type = sema.symbols.propertyType(for: symbol) {
            return type
        }
        guard let owner = sema.symbols.valueParameterOwner(for: symbol)
            ?? sema.symbols.parentSymbol(for: symbol),
            let signature = sema.symbols.functionSignature(for: owner)
        else {
            return nil
        }
        if let index = signature.valueParameterSymbols.firstIndex(of: symbol),
           index < signature.parameterTypes.count
        {
            return signature.parameterTypes[index]
        }
        if symbol == SyntheticSymbolScheme.receiverParameterSymbol(for: owner) {
            return signature.receiverType
        }
        return nil
    }

    private func isDefinitelyDisjoint(
        subject: TypeID,
        target: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let types = sema.types
        if types.isSubtype(subject, target) || types.isSubtype(target, subject) {
            return false
        }
        if hasKnownJvmSerializableOverlap(subject: subject, target: target, sema: sema, interner: interner) {
            return false
        }
        if hasKnownJvmNumericOverlap(subject: subject, target: target, sema: sema, interner: interner)
            || hasKnownJvmAppendableOverlap(subject: subject, target: target, sema: sema, interner: interner)
        {
            return false
        }
        if hasImpreciseIsCheckShape(subject, sema: sema)
            || (hasImpreciseIsCheckShape(target, sema: sema)
                && !hasOnlyStarProjectedClassArguments(target, sema: sema))
        {
            return false
        }
        return isFinalForIsCheck(subject, sema: sema) || isFinalForIsCheck(target, sema: sema)
    }

    private func hasKnownJvmSerializableOverlap(
        subject: TypeID,
        target: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard sema.requiresResolvedLibraryCalls,
              let serializableSymbol = sema.symbols.lookup(fqName: ["java", "io", "Serializable"].map(interner.intern)),
              sema.symbols.symbol(serializableSymbol)?.kind == .interface
        else {
            return false
        }

        func isSerializableInterface(_ type: TypeID) -> Bool {
            guard case let .classType(classType) = sema.types.kind(of: type) else { return false }
            return classType.classSymbol == serializableSymbol
        }

        func isJvmSerializableBuiltin(_ type: TypeID) -> Bool {
            switch sema.types.kind(of: type) {
            case .stringStruct:
                return true
            case let .primitive(primitive, _):
                switch primitive {
                case .boolean, .char, .int, .long, .float, .double, .byte, .short:
                    return true
                case .uint, .ulong, .ubyte, .ushort:
                    return false
                }
            default:
                return false
            }
        }

        return isJvmSerializableBuiltin(subject) && isSerializableInterface(target)
            || isSerializableInterface(subject) && isJvmSerializableBuiltin(target)
    }

    private func hasKnownJvmNumericOverlap(
        subject: TypeID,
        target: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard sema.requiresResolvedLibraryCalls else { return false }

        func isKotlinNumber(_ type: TypeID) -> Bool {
            guard case let .classType(classType) = sema.types.kind(of: type),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return symbol.fqName == [interner.intern("kotlin"), interner.intern("Number")]
        }

        func isJvmNumericType(_ type: TypeID) -> Bool {
            switch sema.types.kind(of: type) {
            case let .primitive(primitive, _):
                switch primitive {
                case .byte, .short, .int, .long, .float, .double:
                    return true
                case .boolean, .char, .uint, .ulong, .ubyte, .ushort:
                    return false
                }
            case let .classType(classType):
                guard let symbol = sema.symbols.symbol(classType.classSymbol),
                      symbol.fqName.count == 2,
                      [interner.intern("kotlin"), interner.intern("java")].contains(symbol.fqName[0])
                else {
                    return false
                }
                switch interner.resolve(symbol.fqName[1]) {
                case "Byte", "Short", "Int", "Integer", "Long", "Float", "Double":
                    return true
                default:
                    return false
                }
            default:
                return false
            }
        }

        return isKotlinNumber(subject) && isJvmNumericType(target)
            || isKotlinNumber(target) && isJvmNumericType(subject)
    }

    private func hasKnownJvmAppendableOverlap(
        subject: TypeID,
        target: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard sema.requiresResolvedLibraryCalls,
              let appendableSymbol = sema.symbols.lookup(
                  fqName: ["java", "lang", "Appendable"].map(interner.intern)
              ),
              sema.symbols.symbol(appendableSymbol)?.kind == .interface
        else {
            return false
        }

        func isAppendable(_ type: TypeID) -> Bool {
            guard case let .classType(classType) = sema.types.kind(of: type) else { return false }
            return classType.classSymbol == appendableSymbol
        }

        func isKotlinStringBuilder(_ type: TypeID) -> Bool {
            guard case let .classType(classType) = sema.types.kind(of: type),
                  let symbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return false
            }
            return symbol.fqName == [
                interner.intern("kotlin"), interner.intern("text"), interner.intern("StringBuilder"),
            ]
        }

        return isKotlinStringBuilder(subject) && isAppendable(target)
            || isAppendable(subject) && isKotlinStringBuilder(target)
    }

    private func isRangeRepresentationCompatible(
        subjectExpr: ExprID,
        subjectType: TypeID,
        targetType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard sema.bindings.isRangeExpr(subjectExpr) || sema.bindings.isFloatingPointRangeExpr(subjectExpr),
              case .primitive = sema.types.kind(of: subjectType),
              case let .classType(targetClass) = sema.types.kind(of: targetType),
              let targetSymbol = sema.symbols.symbol(targetClass.classSymbol)
        else {
            return false
        }

        let floatingPointElementType = sema.bindings.floatingPointRangeElementType(forExpr: subjectExpr)
        let isFloatingRange = floatingPointElementType != nil
            || subjectType == sema.types.floatType
            || subjectType == sema.types.doubleType
        let isDiscreteRange = floatingPointElementType == nil && (
            subjectType == sema.types.charType
                || subjectType == sema.types.uintType
                || subjectType == sema.types.ulongType
                || subjectType == sema.types.longType
                || subjectType == sema.types.intType
        )
        guard isFloatingRange || isDiscreteRange else {
            return false
        }

        let kotlinRangesFQName = [
            interner.intern("kotlin"),
            interner.intern("ranges"),
        ]
        let targetName = interner.resolve(targetSymbol.name)
        if Array(targetSymbol.fqName.dropLast()) == kotlinRangesFQName {
            switch targetName {
            case "ClosedRange":
                return true
            case "OpenEndRange":
                return isDiscreteRange
            case "ClosedFloatingPointRange":
                return isFloatingRange
            default:
                break
            }
        }
        if targetSymbol.fqName == [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Iterable")] {
            return isDiscreteRange
        }

        let rangeTypeNames: [String]
        if sema.bindings.isCharRangeExpr(subjectExpr) {
            rangeTypeNames = ["CharRange", "CharProgression"]
        } else if sema.bindings.isUIntRangeExpr(subjectExpr) {
            rangeTypeNames = ["UIntRange", "UIntProgression"]
        } else if sema.bindings.isULongRangeExpr(subjectExpr) {
            rangeTypeNames = ["ULongRange", "ULongProgression"]
        } else if subjectType == sema.types.longType {
            rangeTypeNames = ["LongRange", "LongProgression"]
        } else if subjectType == sema.types.intType {
            rangeTypeNames = ["IntRange", "IntProgression"]
        } else {
            return false
        }

        return rangeTypeNames.contains { name in
            targetSymbol.fqName == kotlinRangesFQName + [interner.intern(name)]
        }
    }

    private func hasImpreciseIsCheckShape(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: type) {
        case .typeParam, .functionType, .intersection:
            return true
        case .classType(let classType):
            return !classType.args.isEmpty
        default:
            return false
        }
    }

    private func hasOnlyStarProjectedClassArguments(_ type: TypeID, sema: SemaModule) -> Bool {
        guard case .classType(let classType) = sema.types.kind(of: type), !classType.args.isEmpty else {
            return false
        }
        return classType.args.allSatisfy { argument in
            if case .star = argument { return true }
            return false
        }
    }

    private func isFinalForIsCheck(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: type) {
        case .primitive, .stringStruct, .unit:
            return true
        case .classType(let classType):
            guard let symbol = sema.symbols.symbol(classType.classSymbol) else {
                return false
            }
            switch symbol.kind {
            case .class, .enumClass, .object, .annotationClass:
                return !symbol.flags.contains(.openType)
                    && !symbol.flags.contains(.abstractType)
                    && !symbol.flags.contains(.sealedType)
            default:
                return false
            }
        default:
            return false
        }
    }

    private func uintLiteralType(expectedType: TypeID?, sema: SemaModule, literalValue: UInt64) -> TypeID {
        let inferredType = literalValue <= UInt64(UInt32.max)
            ? sema.types.uintType
            : sema.types.ulongType
        guard let expectedType else {
            return inferredType
        }
        let nonNullExpected = sema.types.makeNonNullable(expectedType)
        guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullExpected) else {
            return inferredType
        }
        switch primitive {
        case .ulong:
            return sema.types.ulongType
        case .ubyte:
            return literalValue <= UInt64(UInt8.max) ? sema.types.ubyteType : inferredType
        case .ushort:
            return literalValue <= UInt64(UInt16.max) ? sema.types.ushortType : inferredType
        default:
            return inferredType
        }
    }
}
