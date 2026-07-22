
final class ControlFlowTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func bindLoopIterationOperators(
        exprID: ExprID,
        iterableType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let nonNullIterableType = sema.types.makeNonNullable(iterableType)

        guard case .classType = sema.types.kind(of: nonNullIterableType) else {
            return nil
        }

        let iteratorName = interner.intern("iterator")
        let iteratorCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: iteratorName,
            receiverType: nonNullIterableType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  !symbol.flags.contains(.synthetic),
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        }

        let iteratorCall: CallBinding?
        let iteratorType: TypeID
        if !iteratorCandidates.isEmpty {
            let iteratorResolved = ctx.resolver.resolveCall(
                candidates: iteratorCandidates,
                call: CallExpr(range: range, calleeName: iteratorName, args: []),
                expectedType: nil,
                implicitReceiverType: nonNullIterableType,
                ctx: ctx.semaCtx
            )

            guard let iteratorChosen = iteratorResolved.chosenCallee,
                  let iteratorSignature = sema.symbols.functionSignature(for: iteratorChosen)
            else {
                return nil
            }

            iteratorCall = CallBinding(
                chosenCallee: iteratorChosen,
                substitutedTypeArguments: iteratorResolved.substitutedTypeArguments
                    .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                    .map { _, value in value },
                parameterMapping: iteratorResolved.parameterMapping
            )

            iteratorType = substituteResolvedType(
                iteratorSignature.returnType,
                signature: iteratorSignature,
                substitutedTypeArguments: iteratorResolved.substitutedTypeArguments,
                sema: sema
            )
        } else if isDirectIteratorType(nonNullIterableType, sema: sema, interner: interner) {
            // Iterator<T> already is the iterator; the stdlib extension
            // Iterator<T>.iterator() returns this, so skip the call and
            // use hasNext()/next() directly on the iterable value.
            iteratorCall = nil
            iteratorType = nonNullIterableType
        } else {
            return nil
        }

        let hasNextName = interner.intern("hasNext")
        let hasNextCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: hasNextName,
            receiverType: iteratorType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        }

        let nextName = interner.intern("next")
        let nextCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: nextName,
            receiverType: iteratorType,
            sema: sema,
            interner: interner
        ).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate)
            else {
                return false
            }
            return signature.parameterTypes.isEmpty
        }

        guard !hasNextCandidates.isEmpty, !nextCandidates.isEmpty else {
            return nil
        }

        let hasNextResolved = ctx.resolver.resolveCall(
            candidates: hasNextCandidates,
            call: CallExpr(range: range, calleeName: hasNextName, args: []),
            expectedType: nil,
            implicitReceiverType: iteratorType,
            ctx: ctx.semaCtx
        )
        let nextResolved = ctx.resolver.resolveCall(
            candidates: nextCandidates,
            call: CallExpr(range: range, calleeName: nextName, args: []),
            expectedType: nil,
            implicitReceiverType: iteratorType,
            ctx: ctx.semaCtx
        )

        guard let hasNextChosen = hasNextResolved.chosenCallee,
              let nextChosen = nextResolved.chosenCallee,
              let nextSignature = sema.symbols.functionSignature(for: nextChosen)
        else {
            return nil
        }

        let hasNextCall = CallBinding(
            chosenCallee: hasNextChosen,
            substitutedTypeArguments: hasNextResolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                .map { _, value in value },
            parameterMapping: hasNextResolved.parameterMapping
        )
        let nextCall = CallBinding(
            chosenCallee: nextChosen,
            substitutedTypeArguments: nextResolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                .map { _, value in value },
            parameterMapping: nextResolved.parameterMapping
        )

        let elementType = substituteResolvedType(
            nextSignature.returnType,
            signature: nextSignature,
            substitutedTypeArguments: nextResolved.substitutedTypeArguments,
            sema: sema
        )

        sema.bindings.bindLoopIteration(
            exprID,
            binding: LoopIterationBinding(
                iteratorCall: iteratorCall,
                hasNextCall: hasNextCall,
                nextCall: nextCall,
                iteratorType: iteratorType,
                elementType: elementType
            )
        )
        return elementType
    }

    private func substituteResolvedType(
        _ type: TypeID,
        signature: FunctionSignature,
        substitutedTypeArguments: [TypeVarID: TypeID],
        sema: SemaModule
    ) -> TypeID {
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        return sema.types.substituteTypeParameters(
            in: type,
            substitution: substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// Returns true when `type` is a subtype of `kotlin.collections.Iterator<*>`,
    /// meaning a `for-in` loop can iterate it directly using `hasNext()`/`next()`.
    private func isDirectIteratorType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let iteratorFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator")
        ]
        guard let iteratorSymbol = sema.symbols.lookup(fqName: iteratorFQName) else {
            return false
        }
        let iteratorType = sema.types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        return sema.types.isSubtype(sema.types.makeNonNullable(type), iteratorType)
    }

    func inferForExpr(
        _ id: ExprID,
        loopVariable: InternedString?,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let iterableType = driver.inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        var bodyLocals = locals
        if let loopVariable {
            // `until` desugars to a memberCall (infix function), not a `.binary` range
            // op, so the AST-shape check alone misses it; fall back to the semantic
            // flag that markRangeCallBindings sets when resolving such calls.
            let isRangeExpr = Self.isRangeExpression(iterableExpr, ast: ctx.ast)
                || sema.bindings.isRangeExpr(iterableExpr)
            let elementType = bindLoopIterationOperators(
                exprID: id,
                iterableType: iterableType,
                range: range,
                ctx: ctx
            ) ?? driver.helpers.iterableElementType(
                for: iterableType,
                isRangeExpr: isRangeExpr,
                isCharRangeExpr: sema.bindings.isCharRangeExpr(iterableExpr),
                sema: sema,
                interner: ctx.interner
            ) ?? sema.types.anyType
            let loopVariableSymbol = sema.symbols.define(
                kind: .local,
                name: loopVariable,
                fqName: [
                    ctx.interner.intern("__for_\(id.rawValue)"),
                    loopVariable,
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            // Only register primitive (and value-class) element types in the
            // symbol table; for complex types (e.g. IndexedValue<Char>) this
            // would change downstream lowering in ways that break field-access
            // codegen (kk_array_get_inbounds gets wrong indices). Value classes
            // are a single-field wrapper like a primitive at the ABI level, so
            // ValueClassUnboxingPass needs this type recorded to recognize
            // `for (box in list) { box.value }` as an unboxing site — without
            // it the loop variable falls back to Any and the property read
            // stays a raw kk_array_get_inbounds on the unboxed underlying value.
            let isValueClassElement: Bool = {
                guard case let .classType(classType) = sema.types.kind(of: elementType),
                      classType.nullability == .nonNull,
                      let sym = sema.symbols.symbol(classType.classSymbol)
                else { return false }
                return sym.flags.contains(.valueType)
            }()
            if case .primitive(_, .nonNull) = sema.types.kind(of: elementType) {
                sema.symbols.setPropertyType(elementType, for: loopVariableSymbol)
            } else if isValueClassElement {
                sema.symbols.setPropertyType(elementType, for: loopVariableSymbol)
            }
            bodyLocals[loopVariable] = (elementType, loopVariableSymbol, false, true)
            sema.bindings.bindIdentifier(id, symbol: loopVariableSymbol)
        }
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        _ = driver.inferExpr(
            bodyExpr,
            ctx: ctx.copying(loopDepth: ctx.loopDepth + 1, loopLabelStack: newLabelStack),
            locals: &bodyLocals,
            expectedType: nil
        )
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferWhileExpr(
        _ id: ExprID,
        conditionExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType
        let conditionType = driver.inferExpr(conditionExpr, ctx: ctx, locals: &locals, expectedType: boolType)
        driver.emitSubtypeConstraint(
            left: conditionType,
            right: boolType,
            range: ast.arena.exprRange(conditionExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        // Smart cast: apply condition branching to the while body (P5-66)
        let branch = ctx.dataFlow.branchOnCondition(
            conditionExpr, base: ctx.flowState, locals: locals,
            ast: ast, sema: sema, interner: interner, scope: ctx.scope
        )
        var bodyLocals = locals
        driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &bodyLocals, sema: sema)
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        let bodyCtx = ctx.copying(loopDepth: ctx.loopDepth + 1, loopLabelStack: newLabelStack, flowState: branch.trueState)
        _ = driver.inferExpr(
            bodyExpr,
            ctx: bodyCtx,
            locals: &bodyLocals,
            expectedType: nil
        )
        let resultType = if isConstantTrueCondition(conditionExpr, ast: ast) && !containsBreakTargetingCurrentLoop(bodyExpr, loopLabelStack: [label], ast: ast) {
            sema.types.nothingType
        } else {
            sema.types.unitType
        }
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    func inferDoWhileExpr(
        _ id: ExprID,
        bodyExpr: ExprID,
        conditionExpr: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let boolType = sema.types.booleanType
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        var bodyLocals = locals
        let bodyCtx = ctx.copying(
            loopDepth: ctx.loopDepth + 1,
            loopLabelStack: newLabelStack,
            exportBlockLocalsForExpr: bodyExpr
        )
        _ = driver.inferExpr(
            bodyExpr,
            ctx: bodyCtx,
            locals: &bodyLocals,
            expectedType: nil
        )
        let conditionType = driver.inferExpr(conditionExpr, ctx: ctx, locals: &bodyLocals, expectedType: boolType)
        driver.emitSubtypeConstraint(
            left: conditionType,
            right: boolType,
            range: ast.arena.exprRange(conditionExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        for (name, local) in locals {
            if !local.isInitialized,
               let bodyLocal = bodyLocals[name], bodyLocal.isInitialized,
               bodyLocal.symbol == local.symbol
            {
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
        }
        let resultType = if isConstantTrueCondition(conditionExpr, ast: ast) && !containsBreakTargetingCurrentLoop(bodyExpr, loopLabelStack: [label], ast: ast) {
            sema.types.nothingType
        } else {
            sema.types.unitType
        }
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    // MARK: - Infinite-loop helpers

    /// Returns true if the condition expression is the boolean literal `true`.
    private func isConstantTrueCondition(_ conditionExpr: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(conditionExpr) else { return false }
        if case .boolLiteral(true, _) = expr { return true }
        return false
    }

    /// Returns true if `exprID` contains a `break` whose target is the loop at
    /// the bottom of `loopLabelStack` (index 0). The stack is ordered from the
    /// loop being checked outwards, so nested loops are appended.
    private func containsBreakTargetingCurrentLoop(
        _ exprID: ExprID,
        loopLabelStack: [InternedString?],
        ast: ASTModule
    ) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        switch expr {
        case .breakExpr(let label, _):
            let targetIndex: Int
            if let label {
                if let idx = loopLabelStack.lastIndex(where: { $0 == label }) {
                    targetIndex = idx
                } else {
                    return false
                }
            } else {
                targetIndex = loopLabelStack.count - 1
            }
            return targetIndex == 0
        case .continueExpr:
            return false
        case .forExpr(_, let iterable, let body, let label, _):
            if containsBreakTargetingCurrentLoop(iterable, loopLabelStack: loopLabelStack, ast: ast) { return true }
            var nestedStack = loopLabelStack
            nestedStack.append(label)
            if containsBreakTargetingCurrentLoop(body, loopLabelStack: nestedStack, ast: ast) { return true }
            return false
        case .whileExpr(let condition, let body, let label, _):
            var nestedStack = loopLabelStack
            nestedStack.append(label)
            if containsBreakTargetingCurrentLoop(condition, loopLabelStack: nestedStack, ast: ast) { return true }
            if containsBreakTargetingCurrentLoop(body, loopLabelStack: nestedStack, ast: ast) { return true }
            return false
        case .doWhileExpr(let body, let condition, let label, _):
            var nestedStack = loopLabelStack
            nestedStack.append(label)
            if containsBreakTargetingCurrentLoop(body, loopLabelStack: nestedStack, ast: ast) { return true }
            if containsBreakTargetingCurrentLoop(condition, loopLabelStack: nestedStack, ast: ast) { return true }
            return false
        case .forDestructuringExpr(_, let iterable, let body, _):
            if containsBreakTargetingCurrentLoop(iterable, loopLabelStack: loopLabelStack, ast: ast) { return true }
            var nestedStack = loopLabelStack
            nestedStack.append(nil)
            if containsBreakTargetingCurrentLoop(body, loopLabelStack: nestedStack, ast: ast) { return true }
            return false
        case .ifExpr(let condition, let thenExpr, let elseExpr, _):
            if containsBreakTargetingCurrentLoop(condition, loopLabelStack: loopLabelStack, ast: ast) { return true }
            if containsBreakTargetingCurrentLoop(thenExpr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            if let elseExpr, containsBreakTargetingCurrentLoop(elseExpr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .whenExpr(let subject, let branches, let elseExpr, _):
            if let subject, containsBreakTargetingCurrentLoop(subject, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for branch in branches {
                for condition in branch.conditions {
                    if containsBreakTargetingCurrentLoop(condition, loopLabelStack: loopLabelStack, ast: ast) { return true }
                }
                if let guardExpr = branch.guard_, containsBreakTargetingCurrentLoop(guardExpr, loopLabelStack: loopLabelStack, ast: ast) { return true }
                if containsBreakTargetingCurrentLoop(branch.body, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            if let elseExpr, containsBreakTargetingCurrentLoop(elseExpr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .tryExpr(let body, let catchClauses, let finallyExpr, _):
            if containsBreakTargetingCurrentLoop(body, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for clause in catchClauses {
                if containsBreakTargetingCurrentLoop(clause.body, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            if let finallyExpr, containsBreakTargetingCurrentLoop(finallyExpr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .blockExpr(let statements, let trailingExpr, _):
            for statement in statements {
                if containsBreakTargetingCurrentLoop(statement, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            if let trailingExpr, containsBreakTargetingCurrentLoop(trailingExpr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .returnExpr(let value, _, _):
            if let value, containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .throwExpr(let value, _):
            return containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast)
        case .localDecl(_, _, _, let initializer, _, _):
            if let initializer, containsBreakTargetingCurrentLoop(initializer, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .localAssign(_, let value, _):
            return containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast)
        case .memberAssign(let receiver, _, let value, _):
            if containsBreakTargetingCurrentLoop(receiver, loopLabelStack: loopLabelStack, ast: ast) { return true }
            if containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .indexedAssign(let receiver, let indices, let value, _):
            if containsBreakTargetingCurrentLoop(receiver, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for index in indices {
                if containsBreakTargetingCurrentLoop(index, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            if containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .call(let callee, _, let args, _):
            if containsBreakTargetingCurrentLoop(callee, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for arg in args {
                if containsBreakTargetingCurrentLoop(arg.expr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            return false
        case .memberCall(let receiver, _, _, let args, _):
            if containsBreakTargetingCurrentLoop(receiver, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for arg in args {
                if containsBreakTargetingCurrentLoop(arg.expr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            return false
        case .safeMemberCall(let receiver, _, _, let args, _):
            if containsBreakTargetingCurrentLoop(receiver, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for arg in args {
                if containsBreakTargetingCurrentLoop(arg.expr, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            return false
        case .indexedAccess(let receiver, let indices, _):
            if containsBreakTargetingCurrentLoop(receiver, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for index in indices {
                if containsBreakTargetingCurrentLoop(index, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            return false
        case .binary(_, let lhs, let rhs, _):
            if containsBreakTargetingCurrentLoop(lhs, loopLabelStack: loopLabelStack, ast: ast) { return true }
            if containsBreakTargetingCurrentLoop(rhs, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return false
        case .unaryExpr(_, let operand, _):
            return containsBreakTargetingCurrentLoop(operand, loopLabelStack: loopLabelStack, ast: ast)
        case .isCheck(let e, _, _, _):
            return containsBreakTargetingCurrentLoop(e, loopLabelStack: loopLabelStack, ast: ast)
        case .asCast(let e, _, _, _):
            return containsBreakTargetingCurrentLoop(e, loopLabelStack: loopLabelStack, ast: ast)
        case .nullAssert(let e, _):
            return containsBreakTargetingCurrentLoop(e, loopLabelStack: loopLabelStack, ast: ast)
        case .compoundAssign(_, _, let value, _):
            return containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast)
        case .indexedCompoundAssign(_, let receiver, let indices, let value, _):
            if containsBreakTargetingCurrentLoop(receiver, loopLabelStack: loopLabelStack, ast: ast) { return true }
            for index in indices {
                if containsBreakTargetingCurrentLoop(index, loopLabelStack: loopLabelStack, ast: ast) { return true }
            }
            return containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast)
        case .memberCompoundAssign(_, let receiver, _, let value, _):
            if containsBreakTargetingCurrentLoop(receiver, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return containsBreakTargetingCurrentLoop(value, loopLabelStack: loopLabelStack, ast: ast)
        case .inExpr(let lhs, let rhs, _):
            if containsBreakTargetingCurrentLoop(lhs, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return containsBreakTargetingCurrentLoop(rhs, loopLabelStack: loopLabelStack, ast: ast)
        case .notInExpr(let lhs, let rhs, _):
            if containsBreakTargetingCurrentLoop(lhs, loopLabelStack: loopLabelStack, ast: ast) { return true }
            return containsBreakTargetingCurrentLoop(rhs, loopLabelStack: loopLabelStack, ast: ast)
        case .destructuringDecl(_, _, let initializer, _):
            return containsBreakTargetingCurrentLoop(initializer, loopLabelStack: loopLabelStack, ast: ast)
        case .stringTemplate(let parts, _):
            for part in parts {
                if case .expression(let e) = part,
                   containsBreakTargetingCurrentLoop(e, loopLabelStack: loopLabelStack, ast: ast) {
                    return true
                }
            }
            return false
        case .lambdaLiteral, .localFunDecl, .objectLiteral, .callableRef, .superRef, .thisRef:
            return false
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral, .stringLiteral, .nameRef:
            return false
        @unknown default:
            return false
        }
    }

    func inferIfExpr(
        _ id: ExprID,
        condition: ExprID,
        thenExpr: ExprID,
        elseExpr: ExprID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType
        let conditionType = driver.inferExpr(condition, ctx: ctx, locals: &locals)
        if conditionType != boolType {
            driver.emitSubtypeConstraint(
                left: conditionType,
                right: boolType,
                range: ast.arena.exprRange(condition),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        let branch = ctx.dataFlow.branchOnCondition(
            condition, base: ctx.flowState, locals: locals,
            ast: ast, sema: sema, interner: interner, scope: ctx.scope
        )
        var thenLocals = locals
        driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &thenLocals, sema: sema)
        let thenCtx = ctx.copying(flowState: branch.trueState)
        let thenType = driver.inferExpr(thenExpr, ctx: thenCtx, locals: &thenLocals, expectedType: expectedType)
        let resolvedType: TypeID
        if let elseExpr {
            var elseLocals = locals
            driver.exprChecker.applyFlowStateToLocals(branch.falseState, locals: &elseLocals, sema: sema)
            let elseCtx = ctx.copying(flowState: branch.falseState)
            let elseType = driver.inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType)
            resolvedType = sema.types.lub([thenType, elseType])
            for (name, local) in locals {
                if !local.isInitialized,
                   let thenLocal = thenLocals[name], thenLocal.isInitialized,
                   thenLocal.symbol == local.symbol,
                   let elseLocal = elseLocals[name], elseLocal.isInitialized,
                   elseLocal.symbol == local.symbol
                {
                    locals[name] = (local.type, local.symbol, local.isMutable, true)
                }
            }
        } else {
            resolvedType = sema.types.unitType
        }
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    func inferTryExpr(
        _ id: ExprID,
        body: ExprID,
        catchClauses: [CatchClause],
        finallyExpr: ExprID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let preTryLocals = locals
        var branchTypes: [TypeID] = []
        var normalCompletionLocals: [LocalBindings] = []

        var tryBodyLocals = preTryLocals
        let tryBodyType = driver.inferExpr(body, ctx: ctx, locals: &tryBodyLocals, expectedType: expectedType)
        branchTypes.append(tryBodyType)
        if tryBodyType != sema.types.nothingType {
            normalCompletionLocals.append(tryBodyLocals)
        }

        for (index, clause) in catchClauses.enumerated() {
            var catchLocals = preTryLocals
            let catchParamType = resolveCatchClauseParameterType(
                clause.paramTypeName,
                sema: sema,
                interner: interner,
                diagnostics: ctx.semaCtx.diagnostics,
                range: clause.range
            )
            var catchParamSymbol = SymbolID.invalid
            if let paramName = clause.paramName {
                catchParamSymbol = sema.symbols.define(
                    kind: .local,
                    name: paramName,
                    fqName: [
                        interner.intern("__try_\(id.rawValue)_catch_\(index)"),
                        paramName,
                    ],
                    declSite: clause.range,
                    visibility: .internal
                )
                sema.symbols.setPropertyType(catchParamType, for: catchParamSymbol)
                catchLocals[paramName] = (catchParamType, catchParamSymbol, false, true)
                sema.bindings.bindIdentifier(clause.body, symbol: catchParamSymbol)
            }
            sema.bindings.bindCatchClause(
                clause.body,
                binding: CatchClauseBinding(parameterSymbol: catchParamSymbol, parameterType: catchParamType)
            )
            let catchType = driver.inferExpr(clause.body, ctx: ctx, locals: &catchLocals, expectedType: expectedType)
            branchTypes.append(catchType)
            if catchType != sema.types.nothingType {
                normalCompletionLocals.append(catchLocals)
            }
        }

        if let finallyExpr {
            // Finally is always checked for side effects, but it does not participate in try-expr type inference.
            var finallyLocals = locals
            _ = driver.inferExpr(finallyExpr, ctx: ctx, locals: &finallyLocals, expectedType: nil)
            locals = finallyLocals
        }

        if !normalCompletionLocals.isEmpty {
            for (name, local) in preTryLocals where !local.isInitialized {
                let initializedInAllNormalBranches = normalCompletionLocals.allSatisfy { branchLocals in
                    guard let branchLocal = branchLocals[name], branchLocal.symbol == local.symbol else {
                        return false
                    }
                    return branchLocal.isInitialized
                }
                guard initializedInAllNormalBranches else {
                    continue
                }
                if let current = locals[name], current.symbol == local.symbol {
                    locals[name] = (current.type, current.symbol, current.isMutable, true)
                } else {
                    locals[name] = (local.type, local.symbol, local.isMutable, true)
                }
            }
        }

        let resolvedType = sema.types.lub(branchTypes)
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    private func resolveCatchClauseParameterType(
        _ typeName: InternedString?,
        sema: SemaModule,
        interner: StringInterner,
        diagnostics: DiagnosticEngine,
        range: SourceRange?
    ) -> TypeID {
        guard let typeName else {
            return sema.types.anyType
        }
        if let builtin = driver.helpers.resolveBuiltinTypeName(typeName, types: sema.types, interner: interner) {
            return builtin
        }
        let candidates = sema.symbols.lookupAll(fqName: [typeName])
            .filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                switch symbol.kind {
                case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            .sorted { $0.rawValue < $1.rawValue }
        let resolvedCandidates = if !candidates.isEmpty {
            candidates
        } else {
            sema.symbols.lookupByShortName(typeName)
                .filter { symbolID in
                    guard let symbol = sema.symbols.symbol(symbolID) else { return false }
                    switch symbol.kind {
                    case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                        return true
                    default:
                        return false
                    }
                }
                .sorted { $0.rawValue < $1.rawValue }
        }
        guard let symbol = resolvedCandidates.first else {
            diagnostics.error(
                "KSWIFTK-SEMA-0085",
                "Unresolved exception type '\(interner.resolve(typeName))' in catch clause.",
                range: range
            )
            return sema.types.errorType
        }
        return sema.types.make(.classType(ClassType(classSymbol: symbol, args: [], nullability: .nonNull)))
    }
}
