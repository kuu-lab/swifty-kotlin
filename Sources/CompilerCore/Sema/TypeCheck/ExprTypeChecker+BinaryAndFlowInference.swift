
extension ExprTypeChecker {
    func applyFlowStateToLocals(
        _ state: DataFlowState,
        locals: inout LocalBindings,
        sema _: SemaModule
    ) {
        for (name, local) in locals {
            guard let varState = state.variables[local.symbol],
                  varState.possibleTypes.count == 1,
                  let narrowed = varState.possibleTypes.first
            else {
                continue
            }
            locals[name] = (narrowed, local.symbol, local.isMutable, local.isInitialized)
        }
        locals.memberFlow = state.members
    }

    // swiftlint:disable:next cyclomatic_complexity
    func inferBinaryExpr(
        _ id: ExprID,
        op: BinaryOp,
        lhsID: ExprID,
        rhsID: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        let boolType = sema.types.booleanType
        let intType = sema.types.intType
        let longType = sema.types.longType
        let floatType = sema.types.floatType
        let doubleType = sema.types.doubleType
        let charType = sema.types.charType
        let stringType = sema.types.stringType
        let ubyteType = sema.types.ubyteType
        let ushortType = sema.types.ushortType
        let ulongType = sema.types.ulongType
        let uintType = sema.types.uintType
        let requiresEqualityOperandFactoryInference: Bool = switch op {
        case .equal, .notEqual, .identityEqual, .notIdentityEqual:
            true
        default:
            false
        }

        if op == .logicalAnd || op == .logicalOr {
            let lhs = driver.inferExpr(lhsID, ctx: ctx, locals: &locals, expectedType: boolType)
            driver.emitSubtypeConstraint(
                left: lhs,
                right: boolType,
                range: ast.arena.exprRange(lhsID) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
            let lhsBranch = ctx.dataFlow.branchOnCondition(
                lhsID,
                base: ctx.flowState.includingMembers(from: locals),
                locals: locals,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope
            )
            let rhsState = op == .logicalAnd ? lhsBranch.trueState : lhsBranch.falseState
            var rhsLocals = locals
            applyFlowStateToLocals(rhsState, locals: &rhsLocals, sema: sema)
            let rhs = driver.inferExpr(
                rhsID,
                ctx: ctx.copying(flowState: rhsState),
                locals: &rhsLocals,
                expectedType: boolType
            )
            driver.emitSubtypeConstraint(
                left: rhs,
                right: boolType,
                range: ast.arena.exprRange(rhsID) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }

        // A simple, already-available fallback can constrain a generic safe-call
        // on the left (`x?.let { Result.failure(it) } ?: RESUME`). Resolve only
        // an independent name reference early: arbitrary RHS expressions may
        // read locals modified while checking the LHS and must keep their order.
        let isSafeLetElvisFailure: Bool
        if op == .elvis,
           case let .safeMemberCall(_, member, _, args, _) = ast.arena.expr(lhsID),
           interner.resolve(member) == "let", args.count == 1,
           case let .lambdaLiteral(_, lambdaBodyID, _, _) = ast.arena.expr(args[0].expr)
        {
            let bodyID: ExprID? = if case let .blockExpr(_, trailing, _) = ast.arena.expr(lambdaBodyID) {
                trailing
            } else {
                lambdaBodyID
            }
            isSafeLetElvisFailure = if let bodyID,
               case let .memberCall(_, method, typeArgs, _, _) = ast.arena.expr(bodyID),
               interner.resolve(method) == "failure", typeArgs.isEmpty
            { true } else { false }
        } else {
            isSafeLetElvisFailure = false
        }
        let earlyElvisRhs: TypeID? = {
            guard isSafeLetElvisFailure, expectedType == nil,
                  case let .nameRef(rhsName, _) = ast.arena.expr(rhsID),
                  locals[rhsName]?.isInitialized != false
            else { return nil }
            let rhsType = driver.inferExpr(rhsID, ctx: ctx, locals: &locals)
            guard case let .classType(resultClass) = sema.types.kind(of: sema.types.makeNonNullable(rhsType)),
                  sema.symbols.symbol(resultClass.classSymbol)?.fqName
                    == KnownCompilerNames(interner: interner).kotlinResultFQName
            else { return nil }
            return rhsType
        }()
        let isElvisCallLhs: Bool = if op == .elvis {
            switch ast.arena.expr(lhsID) {
            case .call, .memberCall, .safeMemberCall:
                true
            default:
                false
            }
        } else {
            false
        }
        // A call on the Elvis LHS can use the enclosing result type as a
        // generic-inference hint. Other expressions keep their natural type so
        // the context does not incorrectly constrain the Elvis LUB.
        let lhsExpectedType: TypeID? = if isSafeLetElvisFailure {
            expectedType ?? earlyElvisRhs
        } else if isElvisCallLhs {
            expectedType
        } else {
            nil
        }
        var lhsCtx = ctx
        if requiresEqualityOperandFactoryInference {
            lhsCtx.collectionFactoryInferenceRequiredForEqualityOperand = lhsID
        }
        lhsCtx.isElvisBranchExpectedTypeHint = isElvisCallLhs && !isSafeLetElvisFailure && expectedType != nil
        let lhsOperandType = driver.inferExpr(
            lhsID, ctx: lhsCtx, locals: &locals,
            expectedType: lhsExpectedType
        )
        // A bare `ClassName` on an Elvis side denotes the companion object;
        // keep the companion value type through the join (KUU-3232).
        let inferredLhs = op == .elvis
            ? driver.helpers.retypeClassNameAsCompanionValue(
                lhsID, currentType: lhsOperandType, ast: ast, sema: sema
            ) ?? lhsOperandType
            : lhsOperandType
        var lhs = sema.types.capturedOperatorReceiverType(of: inferredLhs)
        // Elvis uses an enclosing expected type for its RHS, but the LHS's
        // non-null type is only a contextual hint when no enclosing type exists.
        // Apply that hint to lambda inputs (so implicit `it` can be inferred)
        // and integer literals (which adopt the expected primitive type). Other
        // expressions must keep their natural result type: constraining e.g.
        // `run { ... }` to the LHS type rejects valid `Boolean? ?: Unit` code.
        let nonNullLhs = sema.types.makeNonNullable(lhs)
        let rhsIsIntegerLiteral: Bool = {
            guard let rhsExpr = ast.arena.expr(rhsID) else { return false }
            switch rhsExpr {
            case .intLiteral, .uintLiteral:
                return true
            case let .unaryExpr(op, operandID, _)
                where op == .unaryPlus || op == .unaryMinus:
                guard let operandExpr = ast.arena.expr(operandID) else { return false }
                switch operandExpr {
                case .intLiteral, .uintLiteral:
                    return true
                default:
                    return false
                }
            default:
                return false
            }
        }()
        // A zero-argument branch call has no argument evidence for its generic
        // result. The resolver treats its peer type as a hint, leaving concrete
        // fallback return types unchanged.
        let rhsIsZeroArgumentCallWithoutExplicitTypeArguments: Bool = {
            switch ast.arena.expr(rhsID) {
            case let .call(_, typeArgs, args, _),
                 let .memberCall(_, _, typeArgs, args, _),
                 let .safeMemberCall(_, _, typeArgs, args, _):
                return typeArgs.isEmpty && args.isEmpty
            default:
                return false
            }
        }()
        let rhsUsesElvisPeerTypeHint = op == .elvis
            && expectedType == nil
            && rhsIsZeroArgumentCallWithoutExplicitTypeArguments
            && nonNullLhs != sema.types.errorType
            && nonNullLhs != sema.types.nothingType
        let rhsExpectedType: TypeID? = if op == .elvis {
            if let expectedType {
                expectedType
            } else if nonNullLhs != sema.types.errorType,
                      nonNullLhs != sema.types.nothingType,
                      rhsIsIntegerLiteral
            {
                nonNullLhs
            } else if rhsUsesElvisPeerTypeHint {
                nonNullLhs
            } else {
                nil
            }
        } else {
            nil
        }
        let rhsIsCall: Bool = if op == .elvis {
            switch ast.arena.expr(rhsID) {
            case .call, .memberCall, .safeMemberCall:
                true
            default:
                false
            }
        } else {
            false
        }
        var rhsCtx = ctx
        if requiresEqualityOperandFactoryInference {
            rhsCtx.collectionFactoryInferenceRequiredForEqualityOperand = rhsID
        }
        if op == .elvis, expectedType == nil, rhsIsCall,
           nonNullLhs != sema.types.errorType,
           nonNullLhs != sema.types.nothingType
        {
            rhsCtx.elvisRhsCallResultTypeHint = nonNullLhs
            rhsCtx.elvisRhsCallResultTypeHintExpr = rhsID
        }
        var rhs: TypeID
        if let earlyElvisRhs {
            rhs = earlyElvisRhs
        } else if op == .elvis,
                  expectedType == nil,
                  case let .lambdaLiteral(params, body, _, _) = ast.arena.expr(rhsID),
                  case .functionType = sema.types.kind(of: nonNullLhs)
        {
            rhs = inferLambdaLiteralExpr(
                rhsID,
                params: params,
                body: body,
                ctx: ctx,
                locals: &locals,
                expectedType: nonNullLhs,
                expectedTypeIsHintOnly: true
            )
        } else {
            rhsCtx.isElvisBranchExpectedTypeHint = rhsUsesElvisPeerTypeHint
            if op == .elvis {
                // The elvis RHS only runs when the LHS is null, so effects it
                // records on locals (for example `x ?: (y as T)` narrowing y)
                // must not leak past the join. Check it on a discarded copy.
                var rhsLocals = locals
                rhs = driver.inferExpr(rhsID, ctx: rhsCtx, locals: &rhsLocals, expectedType: rhsExpectedType)
            } else {
                rhs = driver.inferExpr(rhsID, ctx: rhsCtx, locals: &locals, expectedType: rhsExpectedType)
            }
        }
        if op == .elvis {
            rhs = driver.helpers.retypeClassNameAsCompanionValue(
                rhsID, currentType: rhs, ast: ast, sema: sema
            ) ?? rhs
        }
        let inferredRhs = rhs
        rhs = sema.types.capturedOperatorReceiverType(of: inferredRhs)

        // Numeric operators on a type parameter are resolved against its
        // concrete primitive upper bound (for example, `T : Double`). Keep
        // the operand bindings generic; the resulting primitive expression
        // type lets ABI lowering unbox those values before emitting the op.
        if [.add, .subtract, .multiply, .divide, .modulo].contains(op),
           let primitiveLhs = resolvePrimitiveArithmeticUpperBound(
               of: lhs, types: sema.types, symbols: sema.symbols
           ),
           let primitiveRhs = resolvePrimitiveArithmeticUpperBound(
               of: rhs, types: sema.types, symbols: sema.symbols
           ),
           sema.types.isBuiltinArithmeticOperand(primitiveLhs),
           sema.types.isBuiltinArithmeticOperand(primitiveRhs)
        {
            lhs = primitiveLhs
            rhs = primitiveRhs
        }

        if [.add, .subtract, .multiply, .divide, .modulo,
            .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
            .rangeTo, .rangeUntil, .downTo, .step].contains(op) {
            if case .primitive(_, .platformType) = sema.types.kind(of: lhs) {
                let target = sema.types.makeNonNullable(lhs)
                driver.recordPlatformNullAssertion(lhsID, sourceType: lhs, targetType: target)
                lhs = target
            }
            if case .primitive = sema.types.kind(of: lhs),
               case .primitive(_, .platformType) = sema.types.kind(of: rhs) {
                let target = sema.types.makeNonNullable(rhs)
                driver.recordPlatformNullAssertion(rhsID, sourceType: rhs, targetType: target)
                rhs = target
            }
        }
        // `===`/`!==` are raw identity comparisons: unlike `==`/`!=` they never
        // dispatch through a user-defined (or inherited Any) `equals()` override,
        // so they must bypass the operator-candidate resolution below entirely.
        if op == .identityEqual || op == .notIdentityEqual {
            let lhsType = equalityDeclaredType(lhsID, inferred: lhs, sema: sema)
            let rhsType = equalityDeclaredType(rhsID, inferred: rhs, sema: sema)
            if identityEqualityHasValueClassOperand(lhsType, rhsType, sema: sema)
                || identityEqualityHasDistinctPrimitiveTypes(lhsType, rhsType, sema: sema)
            {
                let lhsName = sema.types.displayName(of: lhsType, symbols: sema.symbols, interner: interner)
                let rhsName = sema.types.displayName(of: rhsType, symbols: sema.symbols, interner: interner)
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "Identity equality for arguments of types '\(lhsName)' and '\(rhsName)' is prohibited.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if identityEqualityHasDistinctSingletonTypes(lhsType, rhsType, sema: sema) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "Operator '\(op == .identityEqual ? "===" : "!==")' cannot be applied to unrelated singleton types.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if identityEqualityHasDistinctAnonymousObjectTypes(lhsType, rhsType, sema: sema) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "Operator '\(op == .identityEqual ? "===" : "!==")' cannot be applied to unrelated anonymous object types.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            sema.bindings.bindExprType(id, type: boolType)
            return boolType
        }
        if (op == .equal || op == .notEqual),
           equalityHasIncompatibleBuiltinTypes(
               equalityOperandType(lhsID, inferred: lhs, ctx: ctx),
               equalityOperandType(rhsID, inferred: rhs, ctx: ctx),
               sema: sema
           )
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "Operator '\(op == .equal ? "==" : "!=")' cannot be applied to unrelated types.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if op == .add,
           isCoroutineContextLikeType(lhs, sema: sema, interner: interner),
           isCoroutineContextLikeType(rhs, sema: sema, interner: interner),
           let coroutineContextType = coroutineContextType(sema: sema, interner: interner)
        {
            sema.bindings.bindExprType(id, type: coroutineContextType)
            return coroutineContextType
        }
        let lhsIsPrimitive = if case .primitive = sema.types.kind(of: lhs) { true } else { false }
        let operatorNames = operatorFunctionNames(for: op, interner: interner)
        let operatorName = operatorNames[0]
        let shouldUseInheritedEqualityDispatch: Bool = switch op {
        case .equal, .notEqual:
            sema.types.isDefinitelyNonNull(lhs) && sema.types.isDefinitelyNonNull(rhs)
        default:
            true
        }
        let rhsIntegerLiteral = driver.callChecker.integerLiteralValues(rhsID, ast: ast)
        let operatorCall = CallExpr(
            range: range,
            calleeName: operatorName,
            args: [CallArg(
                type: rhs,
                signedIntegerLiteral: rhsIntegerLiteral.signed,
                unsignedIntegerLiteral: rhsIntegerLiteral.unsigned
            )]
        )
        var collectedOperatorCandidates: [SymbolID] = if shouldUseInheritedEqualityDispatch {
            collectOperatorCandidates(
                names: operatorNames,
                receiverType: lhs,
                call: operatorCall,
                locals: locals,
                ctx: ctx
            )
        } else {
            []
        }
        if op == .add, sema.types.isString(lhs) {
            let scopedStringPlusCandidates = collectScopedOperatorExtensionCandidates(
                names: operatorNames,
                receiverType: lhs,
                ctx: ctx
            )
            for candidate in scopedStringPlusCandidates where !collectedOperatorCandidates.contains(candidate) {
                collectedOperatorCandidates.append(candidate)
            }
            let hasApplicableNonBuiltinStringPlusCandidate = collectedOperatorCandidates.contains { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1
                else {
                    return false
                }
                let isBuiltinStringFallback = symbol.fqName.map({ interner.resolve($0) }) == ["kotlin", "text", "plus"]
                    && signature.receiverType.map(sema.types.isString) == true
                    && signature.parameterTypes == [sema.types.nullableAnyType]
                guard !isBuiltinStringFallback else { return false }
                if let receiverType = signature.receiverType,
                   !sema.types.typeContainsAnyTypeParam(receiverType),
                   !sema.types.typeContainsAnyTypeParam(lhs),
                   !sema.types.isSubtype(lhs, receiverType)
                {
                    return false
                }
                let parameterType = signature.parameterTypes[0]
                return sema.types.typeContainsAnyTypeParam(parameterType)
                    || sema.types.typeContainsAnyTypeParam(rhs)
                    || sema.types.isSubtype(rhs, parameterType)
            }
            // Keep the direct concatenation path unless another applicable
            // operator could override the stdlib's String?.plus(Any?) fallback.
            if !hasApplicableNonBuiltinStringPlusCandidate {
                sema.bindings.bindExprType(id, type: stringType)
                return stringType
            }
        }
        var operatorCandidates = driver.callChecker.preferMostSpecificMemberReceiverCandidates(
            collectedOperatorCandidates,
            receiverType: lhs,
            argumentTypes: [rhs],
            sema: sema,
            interner: interner
        )
        // KSP-1281: the bundled generic `T.rangeTo`/`T.rangeUntil` extension in
        // ranges/Stdlib.kt must not capture `..`/`..<` on primitive receivers —
        // those keep the existing scalar range-handle path (markRangeExpr +
        // `__kk_*` construction), which the heap-allocated ComparableRange the
        // generic body builds cannot represent. The generic extension only
        // covers receivers without a concrete range representation (String,
        // user Comparable types), matching upstream where the concrete
        // `Int.rangeTo` members win over the extension.
        if lhsIsPrimitive, op == .rangeTo || op == .rangeUntil {
            operatorCandidates = operatorCandidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let receiverType = signature.receiverType
                else {
                    return true
                }
                if case .typeParam = sema.types.kind(of: receiverType) {
                    return false
                }
                return true
            }
        }
        // A built-in or bundled rangeTo candidate can exist for the receiver
        // while rejecting the RHS type. Kotlin then considers visible operator
        // extensions; keep member precedence by retrying only when the current
        // candidates have no viable call.
        if op == .rangeTo,
           ctx.resolver.probeCall(
               candidates: operatorCandidates,
               call: operatorCall,
               expectedType: nil,
               implicitReceiverType: lhs,
               ctx: sema
           ).viableCandidates.isEmpty
        {
            let localExtensionCandidates = collectLocalOperatorExtensionCandidates(
                names: operatorNames,
                receiverType: lhs,
                call: operatorCall,
                locals: locals,
                ctx: ctx
            )
            if !localExtensionCandidates.isEmpty {
                operatorCandidates = localExtensionCandidates
            } else {
                let extensionCandidates = collectScopedOperatorExtensionCandidates(
                    names: operatorNames,
                    receiverType: lhs,
                    ctx: ctx
                )
                if !ctx.resolver.probeCall(
                    candidates: extensionCandidates,
                    call: operatorCall,
                    expectedType: nil,
                    implicitReceiverType: lhs,
                    ctx: sema
                ).viableCandidates.isEmpty {
                    operatorCandidates = extensionCandidates
                }
            }
        }
        // `collectOperatorCandidates` deliberately excludes primitive receivers
        // from member lookup for non-range operators. That also hides scoped
        // operator extensions because they aren't members. Search for those
        // extensions in the existing arithmetic fallback cases and for primitive
        // comparisons without a built-in operand pair (or with a nullable
        // receiver), where a user `compareTo` must run before builtin fallback.
        let isComparisonOperator: Bool = switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            true
        default:
            false
        }
        // Boolean is not an arithmetic operand, but `kotlin.Boolean` implements
        // `Comparable<Boolean>` (`true > false` is legal): its 0/1
        // representation lets the same machine-compare path serve the
        // relational operators, so pair it with itself as a builtin
        // comparison (KUU-3490).
        let isBuiltinComparisonPair = (sema.types.isBuiltinArithmeticOperand(lhs)
            && sema.types.isBuiltinArithmeticOperand(rhs)
            && ((lhs == charType) == (rhs == charType)))
            || (lhs == boolType && rhs == boolType)
        let isNullablePrimitiveReceiver: Bool = if case .primitive(_, .nullable) = sema.types.kind(of: lhs) {
            true
        } else {
            false
        }
        if operatorCandidates.isEmpty, lhsIsPrimitive {
            let rhsIsNumeric = if case .primitive = sema.types.kind(of: sema.types.makeNonNullable(rhs)) { true } else { false }
            let isPrimitiveArithmeticOperator = [.add, .subtract, .multiply, .divide, .modulo].contains(op)
            let shouldSearchForScopedExtension = isPrimitiveArithmeticOperator
                && (!rhsIsNumeric || isNullablePrimitiveReceiver || hasInvalidBuiltinCharArithmetic(op: op, lhs: lhs, rhs: rhs, sema: sema))
                || isComparisonOperator && (isNullablePrimitiveReceiver || !isBuiltinComparisonPair)
            if shouldSearchForScopedExtension {
                let localExtensionCandidates = collectLocalOperatorExtensionCandidates(
                    names: operatorNames,
                    receiverType: lhs,
                    call: operatorCall,
                    locals: locals,
                    ctx: ctx
                )
                if !localExtensionCandidates.isEmpty {
                    operatorCandidates = localExtensionCandidates
                } else {
                    let extensionCandidates = collectScopedOperatorExtensionCandidates(
                        names: operatorNames,
                        receiverType: lhs,
                        argumentType: isComparisonOperator || (isPrimitiveArithmeticOperator && isNullablePrimitiveReceiver)
                            ? rhs
                            : lhs == charType && op == .add && sema.types.isString(rhs) ? rhs : nil,
                        ctx: ctx
                    )
                    if !extensionCandidates.isEmpty {
                        operatorCandidates = extensionCandidates
                    }
                }
            }
        }
        // Kotlin's `+` resolves against the LHS (receiver) type: `String.plus(Any?)`
        // accepts any RHS, but non-String receivers don't get string concatenation
        // just because the RHS happens to be a String (e.g. `1 + "x"` is not valid
        // Kotlin, and `listOf("x") + "y"` must resolve via the List plus fallback
        // below, not collapse to `String`).
        if op == .add,
           lhs == charType,
           sema.types.isString(rhs),
           sema.types.isDefinitelyNonNull(rhs),
           operatorCandidates.isEmpty
        {
            sema.bindings.bindExprType(id, type: stringType)
            return stringType
        }
        if !lhsIsPrimitive, op == .add || op == .subtract {
            let isListLhs = driver.callChecker.isListLikeType(lhs, sema: sema, interner: interner)
            let isSeqLhs = driver.callChecker.isSequenceLikeType(lhs, sema: sema, interner: interner)
            let isCollExpr = sema.bindings.isCollectionExpr(lhsID)
            // For lists and plain collection exprs: fall back only when no operator candidates exist.
            // For sequences: also fall back when candidates exist but none accepts the RHS type
            // (e.g. `seq + element` where only `plus(Sequence<Any>)` is registered).
            let shouldFallBack = (isListLhs || isCollExpr) && operatorCandidates.isEmpty
                || isSeqLhs && operatorCandidates.isEmpty
            if shouldFallBack {
                sema.bindings.bindExprType(id, type: lhs)
                sema.bindings.markCollectionExpr(id)
                return lhs
            }
        }
        if operatorCandidates.isEmpty {
            if [.add, .subtract, .multiply, .divide, .modulo,
                .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual,
                .rangeTo, .rangeUntil, .downTo, .step].contains(op)
            {
                if sema.types.nullability(of: lhs) == .nullable {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0026",
                        "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if sema.types.nullability(of: rhs) == .nullable {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
            }
        }
        let lhsIsAny = lhs == sema.types.anyType || lhs == sema.types.nullableAnyType
        let rhsIsAny = rhs == sema.types.anyType || rhs == sema.types.nullableAnyType
        if !lhsIsPrimitive, !lhsIsAny, !rhsIsAny, operatorCandidates.isEmpty, lhs != sema.types.errorType, rhs != sema.types.errorType {
            switch op {
            case .add, .subtract, .multiply, .divide, .modulo:
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            default:
                break
            }
        }
        // kotlinc requires the `operator` modifier on `compareTo` for
        // `<`/`<=`/`>`/`>=` syntax. A member named `compareTo` without the
        // modifier cannot serve the comparison; report it explicitly instead
        // of letting the expression fall through to the built-in numeric
        // fallback below.
        if isComparisonOperator, operatorCandidates.isEmpty, !lhsIsPrimitive, lhs != sema.types.errorType {
            let hasNonOperatorCompareTo = driver.helpers.collectMemberFunctionCandidates(
                named: interner.intern("compareTo"),
                receiverType: lhs,
                sema: sema,
                interner: interner
            ).contains { driver.helpers.isNonOperatorConventionFunction($0, sema: sema) }
            if hasNonOperatorCompareTo {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0432",
                    "'operator' modifier is required on 'compareTo' in '\(driver.helpers.conventionReceiverDisplayName(lhs, sema: sema, interner: interner))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
        }
        if !operatorCandidates.isEmpty {
            let isComparisonOperator: Bool = switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                true
            default:
                false
            }
            let hasUninferredOperatorReturn = operatorCandidates.contains { candidate in
                driver.inferredReturnFunctions[candidate] != nil
                    && !driver.checkedInferredReturnFunctions.contains(candidate)
                    && !driver.checkingInferredReturnFunctions.contains(candidate)
            }
            if isComparisonOperator, hasUninferredOperatorReturn {
                // Select by receiver and operand types before inferring a return
                // type, so an unselected overload cannot create a false cycle.
                // The final resolution below then enforces compareTo's Int result.
                let inputSelection = ctx.resolver.resolveCall(
                    candidates: operatorCandidates,
                    call: operatorCall,
                    expectedType: nil,
                    implicitReceiverType: lhs,
                    ctx: ctx.sema
                )
                if inputSelection.diagnostic == nil,
                   let chosen = inputSelection.chosenCallee
                {
                    driver.inferFunctionReturnTypesIfNeeded(for: [chosen])
                }
            }
            // Comparison operators desugar to compareTo(), which always returns Int.
            // The binary expression itself is Boolean, so do not pass that as the
            // call's expected return type; otherwise Int <: Boolean fails.
            let operatorExpectedType: TypeID? = switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                intType
            default:
                expectedType
            }
            let isSeqLhs = driver.callChecker.isSequenceLikeType(lhs, sema: sema, interner: interner)
            let resolved = ctx.resolver.resolveCall(
                candidates: operatorCandidates,
                call: operatorCall,
                expectedType: operatorExpectedType,
                implicitReceiverType: lhs,
                ctx: ctx.sema
            )
            if isSeqLhs, resolved.chosenCallee == nil {
                sema.bindings.bindExprType(id, type: lhs)
                sema.bindings.markCollectionExpr(id)
                return lhs
            }
            if let diagnostic = resolved.diagnostic {
                if let fallbackType = bindComparableUpperBoundOperatorFallback(
                    id,
                    op: op,
                    lhs: lhs,
                    rhs: rhs,
                    candidates: operatorCandidates,
                    sema: sema
                ) {
                    return fallbackType
                }
                if lhs != sema.types.errorType, rhs != sema.types.errorType {
                    if sema.types.nullability(of: lhs) == .nullable, op != .equal, op != .notEqual {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0026",
                            "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                            range: range
                        )
                    } else {
                        ctx.sema.diagnostics.emit(diagnostic)
                    }
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                if let fallbackType = bindComparableUpperBoundOperatorFallback(
                    id,
                    op: op,
                    lhs: lhs,
                    rhs: rhs,
                    candidates: operatorCandidates,
                    sema: sema
                ) {
                    return fallbackType
                }
                if lhs != sema.types.errorType, rhs != sema.types.errorType {
                    if sema.types.nullability(of: lhs) == .nullable, op != .equal, op != .notEqual {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0026",
                            "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                            range: range
                        )
                    } else {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0002",
                            "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                            range: range
                        )
                    }
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            driver.callChecker.contextualizeResolvedIntegerArguments(
                args: [CallArgument(expr: rhsID)],
                resolved: resolved,
                ctx: ctx,
                locals: &locals
            )
            let returnType = driver.callChecker.bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            // compareTo desugaring: comparison operators (<, <=, >, >=) that resolve
            // to a compareTo method should produce Bool, not the compareTo return type (Int).
            // The KIR lowerer will emit: compareTo(a, b) <op> 0
            let effectiveType: TypeID = switch op {
            case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
                boolType
            default:
                returnType
            }
            if [.rangeTo, .rangeUntil, .downTo, .step].contains(op) {
                // Source-backed range operators do not reach the legacy range
                // marker path below when ordinary operator resolution succeeds.
                driver.callChecker.markRangeCallBindings(
                    id,
                    chosen: chosen,
                    returnType: returnType,
                    sema: sema
                )
                // A resolved call returning a range interface yields a heap
                // object, not a runtime range box. Operand-based marks would
                // misroute `x in` to the `__kk_*_range_*` bridges and erase
                // the custom rangeTo call (KUU-2941).
                if !driver.helpers.isRangeInterfaceType(returnType, sema: sema, interner: interner) {
                    if [.rangeTo, .rangeUntil, .downTo].contains(op) {
                        sema.bindings.markRangeExpr(id)
                        if lhs == ulongType || rhs == ulongType {
                            sema.bindings.markULongRangeExpr(id)
                        } else if lhs == uintType || rhs == uintType
                            || lhs == ubyteType || rhs == ubyteType
                            || lhs == ushortType || rhs == ushortType
                        {
                            sema.bindings.markUIntRangeExpr(id)
                        }
                        if lhs == charType || rhs == charType {
                            sema.bindings.markCharRangeExpr(id)
                        }
                        if lhs == sema.types.doubleType || rhs == sema.types.doubleType
                            || lhs == sema.types.floatType || rhs == sema.types.floatType
                        {
                            let elementType = lhs == sema.types.floatType || rhs == sema.types.floatType
                                ? sema.types.floatType
                                : sema.types.doubleType
                            sema.bindings.bindFloatingPointRangeElementType(elementType, forExpr: id)
                        }
                    } else {
                        sema.bindings.markRangeExpr(id)
                        if lhs == uintType || sema.bindings.isUIntRangeExpr(lhsID) {
                            sema.bindings.markUIntRangeExpr(id)
                        }
                        if lhs == ulongType || sema.bindings.isULongRangeExpr(lhsID) {
                            sema.bindings.markULongRangeExpr(id)
                        }
                        if sema.bindings.isCharRangeExpr(lhsID) {
                            sema.bindings.markCharRangeExpr(id)
                        }
                    }
                }
            }
            sema.bindings.bindExprType(id, type: effectiveType)
            return effectiveType
        }
        let isRelationalComparison: Bool = switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            true
        default:
            false
        }
        if isRelationalComparison, lhs != sema.types.errorType, rhs != sema.types.errorType {
            if !isBuiltinComparisonPair {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
        }
        // Char concatenation and applicable operator overloads return above.
        // A textual RHS alone must not enable the primitive arithmetic fallback.
        if sema.types.containsCapturedTypes(inferredLhs) || sema.types.containsCapturedTypes(inferredRhs),
           [.add, .subtract, .multiply, .divide, .modulo].contains(op),
           !sema.types.isBuiltinArithmeticOperand(lhs) || !sema.types.isBuiltinArithmeticOperand(rhs)
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002", "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        let hasInvalidTextAddition = op == .add && (
            sema.types.isString(rhs)
                || driver.callChecker.syntheticCharSequenceType(sema: sema).map {
                    sema.types.isSubtype(sema.types.makeNonNullable(rhs), $0)
                } == true
        )
        if hasInvalidTextAddition || hasInvalidBuiltinCharArithmetic(op: op, lhs: lhs, rhs: rhs, sema: sema) {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        // The switch below implements only the built-in numeric and range
        // operators. Restrict it to builtin arithmetic operands (numeric
        // primitives and Char): Boolean has no `plus`/`rangeTo` member in
        // Kotlin, and a class/String/Any operand can never promote into a
        // numeric result. Without this gate `true + true` silently coerces
        // true to 1. `Nothing` passes through as a subtype of every operand.
        if [.add, .subtract, .multiply, .divide, .modulo,
            .rangeTo, .rangeUntil, .downTo, .step].contains(op),
           lhs != sema.types.errorType, rhs != sema.types.errorType,
           (!(sema.types.isBuiltinArithmeticOperand(lhs) || lhs == sema.types.nothingType)
               || !(sema.types.isBuiltinArithmeticOperand(rhs) || rhs == sema.types.nothingType))
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        var type: TypeID

        let lhsIsSigned = sema.types.isSigned(lhs)
        let rhsIsUnsigned = sema.types.isUnsigned(rhs)
        let lhsIsUnsigned = sema.types.isUnsigned(lhs)
        let rhsIsSigned = sema.types.isSigned(rhs)

        // Kotlin's UIntProgression.step(Int) and ULongProgression.step(Long)
        // take a signed parameter, so mixed signedness is valid only when the
        // receiver is unsigned and the step operand matches the expected signed
        // type: Int for UIntProgression, Int or Long for ULongProgression
        // (Int is implicitly widened to Long in Kotlin).
        // The reverse (signed..signed step unsigned) is rejected because
        // IntProgression.step takes Int, not UInt.
        let allowsMixedSignedness: Bool = {
            if case .step = op, lhsIsUnsigned, rhsIsSigned {
                if lhs == uintType { return rhs == intType }
                // ULongProgression.step expects Long. Kotlin does not perform
                // implicit numeric widening for non-literals; only integer
                // literal constants adapt to the expected parameter type.
                // Accept Int only when the rhs is a literal constant.
                if lhs == ulongType {
                    if rhs == longType { return true }
                    if rhs == intType {
                        if let rhsExpr = ast.arena.expr(rhsID),
                           case .intLiteral = rhsExpr {
                            return true
                        }
                        return false
                    }
                }
            }
            return false
        }()

        if !allowsMixedSignedness, (lhsIsSigned && rhsIsUnsigned) || (lhsIsUnsigned && rhsIsSigned) {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0043",
                "Operator '\(interner.resolve(operatorName))' cannot be applied to '(signed, unsigned)' or '(unsigned, signed)' types.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        switch op {
        case .add:
            if lhs == charType && rhs == intType {
                type = charType
            } else if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
            } else if lhsIsUnsigned || rhsIsUnsigned {
                type = uintType
            } else {
                type = intType
            }
        case .subtract:
            if lhs == charType && rhs == charType {
                type = intType
            } else if lhs == charType && rhs == intType {
                type = charType
            } else if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
            } else if lhsIsUnsigned || rhsIsUnsigned {
                type = uintType
            } else {
                type = intType
            }
        case .multiply, .divide, .modulo:
            if lhs == doubleType || rhs == doubleType {
                type = doubleType
            } else if lhs == floatType || rhs == floatType {
                type = floatType
            } else if lhs == longType || rhs == longType {
                type = longType
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
            } else if lhsIsUnsigned || rhsIsUnsigned {
                type = uintType
            } else {
                type = intType
            }
        case .equal, .notEqual, .identityEqual, .notIdentityEqual, .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            type = boolType
        case .logicalAnd, .logicalOr:
            driver.emitSubtypeConstraint(
                left: lhs, right: boolType,
                range: ast.arena.exprRange(lhsID) ?? range,
                solver: ConstraintSolver(), sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
            driver.emitSubtypeConstraint(
                left: rhs, right: boolType,
                range: ast.arena.exprRange(rhsID) ?? range,
                solver: ConstraintSolver(), sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
            type = boolType
        case .elvis:
            // Kotlin's `?:` joins `T & Any` (not bare `T`) with the rhs —
            // the lhs value is proven non-null, so a null-capable type
            // parameter needs its definitely-non-null form (KUU-2693).
            let nonNullLhs = sema.types.definitelyNonNullForm(of: lhs)
            let elvisRhs = driver.helpers.retypeBranchClassObjectValue(
                rhsID, currentType: rhs, ast: ast, sema: sema
            ) ?? rhs
            type = sema.types.lub([nonNullLhs, elvisRhs])
            // Smart cast: `x ?: return` / `x ?: throw` narrows x to non-null (P5-66)
            if let rhsExpr = ast.arena.expr(rhsID),
               driver.helpers.isTerminatingExpr(rhsExpr)
            {
                if let lhsExpr = ast.arena.expr(lhsID),
                   case let .nameRef(elvisVarName, _) = lhsExpr,
                   let elvisLocal = locals[elvisVarName],
                   driver.helpers.isStableLocalSymbol(elvisLocal.symbol, sema: sema)
                {
                    let nonNullType = sema.types.definitelyNonNullForm(of: elvisLocal.type)
                    locals[elvisVarName] = (nonNullType, elvisLocal.symbol, elvisLocal.isMutable, elvisLocal.isInitialized)
                }
            }
        case .rangeTo, .rangeUntil, .downTo:
            // kotlinc requires a matching stdlib overload for the operand pair:
            // the signed integers pair with each other, while Char, each
            // unsigned type, and the floating-point types only pair with
            // themselves (and no floating-point `downTo` exists at all). The
            // builtin fallback otherwise accepts every builtin-arithmetic pair
            // such as `'a'..1.5` (KUU-3121).
            let isValidBuiltinRangePair: Bool = switch op {
            case .downTo:
                (lhsIsSigned && rhsIsSigned)
                    || (lhs == rhs && lhs != sema.types.doubleType && lhs != sema.types.floatType)
            default:
                (lhsIsSigned && rhsIsSigned) || lhs == rhs
            }
            if !isValidBuiltinRangePair,
               lhs != sema.types.nothingType, rhs != sema.types.nothingType
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-TYPE-0001",
                    "Argument type mismatch: actual type is '\(sema.types.renderType(rhs))', but '\(sema.types.renderType(lhs))' was expected.",
                    range: ast.arena.exprRange(rhsID) ?? range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if lhs == longType || rhs == longType {
                type = longType
            } else if lhs == ulongType || rhs == ulongType {
                type = ulongType
                sema.bindings.markULongRangeExpr(id)
            } else if lhs == uintType || rhs == uintType
                || lhs == ubyteType || rhs == ubyteType
                || lhs == ushortType || rhs == ushortType
            {
                type = uintType
                sema.bindings.markUIntRangeExpr(id)
            } else {
                type = intType
            }
            sema.bindings.markRangeExpr(id)
            if lhs == sema.types.doubleType || rhs == sema.types.doubleType ||
                lhs == sema.types.floatType || rhs == sema.types.floatType
            {
                let elementType = lhs == sema.types.floatType || rhs == sema.types.floatType
                    ? sema.types.floatType
                    : sema.types.doubleType
                sema.bindings.bindFloatingPointRangeElementType(elementType, forExpr: id, endExclusive: op == .rangeUntil)
            }
            if lhs == sema.types.charType || rhs == sema.types.charType {
                sema.bindings.markCharRangeExpr(id)
            }
        case .step:
            // An Int range expression uses the scalar Int type plus a range
            // marker, but `step` returns IntProgression, not IntRange. Keep that
            // nominal distinction so source-backed HOF lookup does not bind a
            // positive-step progression to the IntRange overload and then lower
            // its loop with step 1 (KUU-576).
            if lhs == longType {
                type = longType
            } else if lhs == ulongType {
                type = ulongType
            } else if lhs == uintType {
                type = uintType
                sema.bindings.markUIntRangeExpr(id)
            } else if sema.bindings.isRangeExpr(lhsID),
                      !sema.bindings.isCharRangeExpr(lhsID),
                      let intProgressionType = nominalRangeType(
                          named: "IntProgression",
                          sema: sema,
                          interner: interner
                      )
            {
                type = intProgressionType
            } else {
                type = intType
            }
            sema.bindings.markRangeExpr(id)
            if sema.bindings.isCharRangeExpr(lhsID) {
                sema.bindings.markCharRangeExpr(id)
            }
            if sema.bindings.isULongRangeExpr(lhsID) {
                sema.bindings.markULongRangeExpr(id)
            }
            if sema.bindings.isUIntRangeExpr(lhsID) {
                sema.bindings.markUIntRangeExpr(id)
            }
        case .bitwiseAnd, .bitwiseOr, .bitwiseXor, .shl, .shr, .ushr:
            preconditionFailure("Bitwise/shift binary operators must be parsed as infix member calls")
        }
        if [.add, .subtract, .multiply, .divide, .modulo].contains(op),
           type == intType,
           let expectedType,
           sema.types.makeNonNullable(expectedType) == longType,
           let constValue = ConstantCollector().literalConstantExpr(id, ast: ast, interner: interner),
           case let .intLiteral(foldedInt) = constValue
        {
            type = longType
            sema.bindings.bindConstExprValue(id, value: .longLiteral(foldedInt))
        }
        sema.bindings.bindExprType(id, type: type)
        return type
    }

    func collectScopedOperatorExtensionCandidates(
        names: [InternedString],
        receiverType: TypeID,
        argumentType: TypeID? = nil,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        names.flatMap { name in
            ctx.cachedScopeLookup(name).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType
                else { return false }
                if let argumentType,
                   (signature.parameterTypes.count != 1 || !ctx.sema.types.isSubtype(argumentType, signature.parameterTypes[0]))
                {
                    return false
                }
                return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: receiverType, declaredReceiver: declaredReceiver, sema: ctx.sema
                )
            }
        }
    }

    func hasInvalidBuiltinCharArithmetic(op: BinaryOp, lhs: TypeID, rhs: TypeID, sema: SemaModule) -> Bool {
        guard sema.types.makeNonNullable(lhs) == sema.types.charType
            || sema.types.makeNonNullable(rhs) == sema.types.charType
        else { return false }
        switch op {
        case .add:
            return !(lhs == sema.types.charType
                && (rhs == sema.types.intType || (sema.types.isString(rhs) && sema.types.isDefinitelyNonNull(rhs))))
                && !sema.types.isString(lhs)
        case .subtract:
            return !(lhs == sema.types.charType && (rhs == sema.types.intType || rhs == sema.types.charType))
        case .multiply, .divide, .modulo:
            return true
        default:
            return false
        }
    }

    private func nominalRangeType(
        named name: String,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let symbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("ranges"),
            interner.intern(name),
        ]) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func bindComparableUpperBoundOperatorFallback(
        _ exprID: ExprID,
        op: BinaryOp,
        lhs: TypeID,
        rhs: TypeID,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        switch op {
        case .lessThan, .lessOrEqual, .greaterThan, .greaterOrEqual:
            break
        default:
            return nil
        }
        guard case let .typeParam(lhsParam) = sema.types.kind(of: lhs),
              rhs == lhs || sema.types.isSubtype(rhs, lhs),
              let comparableSymbol = sema.types.comparableInterfaceSymbol,
              typeParameter(lhsParam.symbol, hasComparableSelfBound: lhs, comparableSymbol: comparableSymbol, sema: sema),
              let chosen = candidates.first(where: { candidate in
                  guard let signature = sema.symbols.functionSignature(for: candidate) else {
                      return false
                  }
                  return signature.receiverType != nil && signature.parameterTypes.count == 1
              })
        else {
            return nil
        }

        sema.bindings.bindCall(
            exprID,
            binding: CallBinding(
                chosenCallee: chosen,
                substitutedTypeArguments: [lhs],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(exprID, target: .symbol(chosen))
        sema.bindings.bindExprType(exprID, type: sema.types.booleanType)
        return sema.types.booleanType
    }

    private func typeParameter(
        _ symbol: SymbolID,
        hasComparableSelfBound targetType: TypeID,
        comparableSymbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.typeParameterUpperBounds(for: symbol).contains { bound in
            comparableSelfBoundContains(
                bound,
                targetType: targetType,
                comparableSymbol: comparableSymbol,
                sema: sema
            )
        }
    }

    private func comparableSelfBoundContains(
        _ bound: TypeID,
        targetType: TypeID,
        comparableSymbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        switch sema.types.kind(of: bound) {
        case let .classType(classType):
            guard classType.classSymbol == comparableSymbol,
                  classType.args.count == 1
            else {
                return false
            }

            let argumentType: TypeID
            switch classType.args[0] {
            case let .invariant(type):
                argumentType = type
            case let .in(type):
                argumentType = type
            default:
                return false
            }

            return argumentType == targetType

        case let .intersection(parts):
            return parts.contains {
                comparableSelfBoundContains(
                    $0,
                    targetType: targetType,
                    comparableSymbol: comparableSymbol,
                    sema: sema
                )
            }

        default:
            return false
        }
    }

    func equalityOperandType(_ expr: ExprID, inferred: TypeID, ctx: TypeInferenceContext) -> TypeID {
        let sema = ctx.sema
        let declared = equalityDeclaredType(expr, inferred: inferred, sema: sema)
        // Range literals and their local references can carry a scalar element
        // type for lowering. Compare their source-level range types instead.
        guard sema.bindings.isRangeExpr(expr),
              case .primitive = sema.types.kind(of: sema.types.makeNonNullable(declared))
        else { return declared }
        return driver.callChecker.sourceLevelRangeMemberLookupType(
            receiverExpr: expr,
            receiverType: declared,
            sema: sema,
            interner: ctx.interner
        ) ?? driver.callChecker.floatingPointRangeArgumentType(
            expr,
            ast: ctx.ast,
            sema: sema,
            interner: ctx.interner
        ) ?? declared
    }

    // Use the declaration type for smart-cast references. Kotlin only warns
    // when a comparison becomes incompatible after smart casting.
    private func equalityDeclaredType(_ expr: ExprID, inferred: TypeID, sema: SemaModule) -> TypeID {
        // A callable reference binds its target symbol for lowering, but its
        // expression type is the callable reference type (for example,
        // KMutableProperty0<Int>), not the target property's value type.
        guard sema.bindings.callableRefKind(for: expr) == nil else { return inferred }
        // Receiver-function value invocations retain the callee symbol on the
        // call expression for capture analysis. Their equality type is the
        // inferred invocation result, not the function value's declaration type.
        guard sema.bindings.callableValueCallBinding(for: expr) == nil else { return inferred }
        guard let symbol = sema.bindings.identifierSymbol(for: expr) else { return inferred }
        if let declared = sema.symbols.propertyType(for: symbol) { return declared }
        if let owner = sema.symbols.valueParameterOwner(for: symbol),
           let signature = sema.symbols.functionSignature(for: owner),
           let index = signature.valueParameterSymbols.firstIndex(of: symbol),
           signature.parameterTypes.indices.contains(index)
        {
            return signature.parameterTypes[index]
        }
        return inferred
    }

    private func identityEqualityHasValueClassOperand(_ lhs: TypeID, _ rhs: TypeID, sema: SemaModule) -> Bool {
        for type in [lhs, rhs] {
            switch sema.types.kind(of: type) {
            case .error, .nothing(.nullable):
                return false
            default:
                break
            }
        }
        return [lhs, rhs].contains { type in
            resolveClassTypeSymbol(type, sema: sema)?.symbol.flags.contains(.valueType) == true
        }
    }

    /// kotlinc rejects `===` between different non-null primitive types
    /// (e.g. `Int === Long`) with the same diagnostic as value classes.
    private func identityEqualityHasDistinctPrimitiveTypes(_ lhs: TypeID, _ rhs: TypeID, sema: SemaModule) -> Bool {
        guard case let .primitive(left, .nonNull) = sema.types.kind(of: lhs),
              case let .primitive(right, .nonNull) = sema.types.kind(of: rhs)
        else { return false }
        return left != right
    }

    private func identityEqualityHasDistinctSingletonTypes(_ lhs: TypeID, _ rhs: TypeID, sema: SemaModule) -> Bool {
        // Both nullable types can contain the same null value. Widened operands
        // and type parameters retain their declared types on the caller's path.
        if sema.types.nullability(of: lhs) == .nullable,
           sema.types.nullability(of: rhs) == .nullable {
            return false
        }
        guard let left = resolveClassTypeSymbol(lhs, sema: sema)?.symbol,
              let right = resolveClassTypeSymbol(rhs, sema: sema)?.symbol
        else { return false }
        return left.kind == .object && right.kind == .object && left.id != right.id
    }

    private func identityEqualityHasDistinctAnonymousObjectTypes(_ lhs: TypeID, _ rhs: TypeID, sema: SemaModule) -> Bool {
        // Anonymous object literals are distinct final nominal classes, even
        // when their members or declared supertypes happen to match.
        if sema.types.nullability(of: lhs) == .nullable,
           sema.types.nullability(of: rhs) == .nullable {
            return false
        }
        guard let left = resolveClassTypeSymbol(lhs, sema: sema)?.symbol,
              let right = resolveClassTypeSymbol(rhs, sema: sema)?.symbol
        else { return false }
        return left.flags.contains(.objectLiteralType)
            && right.flags.contains(.objectLiteralType)
            && left.id != right.id
    }

    // Kotlin 2.3.10 rejects unrelated concrete operands when a primitive or
    // String is involved. Ordinary classes may implement cross-type equals.
    // Type-parameter bounds and enum/value-class diagnostics have additional
    // warning rules and remain on the existing path.
    func equalityHasIncompatibleBuiltinTypes(_ lhs: TypeID, _ rhs: TypeID, sema: SemaModule) -> Bool {
        func erasedOperand(_ type: TypeID) -> TypeID? {
            let nonNull = sema.types.makeNonNullable(type)
            switch sema.types.kind(of: nonNull) {
            case .typeParam, .intersection:
                return nil
            case let .classType(classType):
                return sema.types.make(.classType(ClassType(
                    classSymbol: classType.classSymbol,
                    args: classType.args.map { _ in .star },
                    enclosingTypeArgs: classType.enclosingTypeArgs.map { _ in .star },
                    nullability: .nonNull
                )))
            default:
                return nonNull
            }
        }
        guard let lhs = erasedOperand(lhs), let rhs = erasedOperand(rhs),
              !sema.types.isSubtype(lhs, rhs), !sema.types.isSubtype(rhs, lhs)
        else { return false }

        func requiresCompatibleOperand(_ type: TypeID) -> Bool {
            switch sema.types.kind(of: type) {
            case .primitive, .stringStruct:
                return true
            default:
                return false
            }
        }
        return requiresCompatibleOperand(lhs) || requiresCompatibleOperand(rhs)
    }

    private func coroutineContextType(sema: SemaModule, interner: StringInterner) -> TypeID? {
        // CoroutineContext lives in kotlin.coroutines (not kotlinx.coroutines)
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
            interner.intern("CoroutineContext"),
        ]
        guard let symbol = sema.symbols.lookup(fqName: fqName) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    private func isCoroutineContextLikeType(_ type: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return false
        }
        let kotlinxCoroutinesPkg = [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
        ]
        // CoroutineContext lives in kotlin.coroutines, others in kotlinx.coroutines
        let kotlinCoroutinesPkg = [
            interner.intern("kotlin"),
            interner.intern("coroutines"),
        ]
        guard symbol.fqName.starts(with: kotlinxCoroutinesPkg)
            || symbol.fqName.starts(with: kotlinCoroutinesPkg) else {
            return false
        }
        let typeName = interner.resolve(symbol.name)
        return typeName == "CoroutineContext"
            || typeName == "CoroutineDispatcher"
            || typeName == "CoroutineName"
            || typeName == "CoroutineExceptionHandler"
            || typeName == "Job"
    }
}
