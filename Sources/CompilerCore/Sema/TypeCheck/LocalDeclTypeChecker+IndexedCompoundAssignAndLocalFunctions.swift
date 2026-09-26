
extension LocalDeclTypeChecker {
    func inferIndexedCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
        let getName = interner.intern("get")
        let getCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: getName, receiverType: receiverType, sema: sema, interner: interner
        )
        var indexTypes: [TypeID] = []
        for (position, indexExpr) in indices.enumerated() {
            let literalExpectedType = contextualIntegerLiteralExpectedType(
                candidates: getCandidates,
                parameterIndex: position,
                indexExpr: indexExpr,
                ast: ctx.ast,
                sema: sema
            )
            indexTypes.append(driver.inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: literalExpectedType))
        }
        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)

        // Array<*>'s element type is erased to Any? at the type-check level, but the
        // backing store's actual boxed representation (IntBox/LongBox/DoubleBox/...)
        // is only known for a concrete type argument. KIR lowering needs the real
        // element type to pick the matching box/unbox pair for the read-modify-write;
        // without it, it would have to guess (e.g. from the RHS operand's type), which
        // silently corrupts the slot whenever that guess doesn't match the actual
        // runtime element type. Reject at the type-check boundary instead, matching
        // real Kotlin's own restriction that `set` is inaccessible on an out-projected
        // array (`Array<*>` prohibits writes for the same variance-safety reason).
        if isStarProjectedArrayReceiver(receiverType, sema: sema, interner: ctx.interner) {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-STAR-PROJECTED-WRITE",
                "Compound assignment to an element of a star-projected array ('Array<*>') is not allowed: the element type is erased, so it cannot be determined which primitive representation to read and write.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        let (elementType, operatorResolved) = resolveIndexedGetElement(
            id: id, receiverType: receiverType, getCandidates: getCandidates, indexTypes: indexTypes,
            range: range, ctx: ctx
        )

        if !operatorResolved {
            guard indices.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let intType = sema.types.make(.primitive(.int, .nonNull))
            driver.emitSubtypeConstraint(
                left: indexTypes[0], right: intType,
                range: ctx.ast.arena.exprRange(indices[0]) ?? range,
                solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
            )
        }

        let resultType = compoundOpResultType(
            assignOp: op, elementType: elementType, valueType: valueType, sema: sema
        )

        // KSWIFTK-BUG: the write-back half of `a[i] op= v` must go through the
        // same custom operator `set()` that a plain `a[i] = v` would resolve,
        // not the raw built-in array runtime. Only attempt this when `get()`
        // itself resolved to a real member (not the built-in array fallback)
        // and the receiver isn't a genuine array (Array<T>'s `get`/`set` ARE
        // real resolvable members too, but must still go through the raw
        // array/boxing path — mirrored from inferIndexedAssignExpr's
        // `assignReceiverIsArrayLike` guard).
        if operatorResolved, !isConcreteArrayLikeReceiverType(receiverType, sema: sema, interner: interner) {
            bindIndexedCompoundAssignSetOperator(
                id, receiverType: receiverType, indexTypes: indexTypes, valueType: resultType,
                elementType: elementType, range: range, ctx: ctx
            )
        }

        driver.emitSubtypeConstraint(
            left: valueType, right: elementType,
            range: ctx.ast.arena.exprRange(valueExpr) ?? range,
            solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
        )
        driver.emitSubtypeConstraint(
            left: resultType, right: elementType, range: range,
            solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
        )

        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    /// True when `receiverType` is the generic `Array<*>` class specifically (star
    /// type argument), as opposed to a concrete `Array<T>` or one of the
    /// primitive-specialized array types (IntArray, ...). Mirrors
    /// CallLowerer+Operators.swift's isGenericArrayReceiverType/
    /// genericArrayElementType, which need a concrete T to select the matching
    /// box/unbox pair.
    private func isStarProjectedArrayReceiver(_ receiverType: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        guard let (classType, symbol) = resolveClassTypeSymbol(receiverType, sema: sema),
              interner.resolve(symbol.name) == "Array",
              let firstArg = classType.args.first,
              case .star = firstArg
        else {
            return false
        }
        return true
    }

    /// True when `receiverType` is one of the compiler's built-in array types
    /// (Array, IntArray, ByteArray, ...). Mirrors
    /// CallLowerer+ReceiverTypePredicates.swift's isConcreteArrayLikeType,
    /// which KIR lowering uses to keep genuine arrays on the raw
    /// array/boxing runtime path even though `Array<T>` also has real,
    /// resolvable `get`/`set` member symbols.
    private func isConcreteArrayLikeReceiverType(_ receiverType: TypeID, sema: SemaModule, interner: StringInterner) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        return knownNames.isArrayLikeName(symbol.name)
    }

    /// Resolve `operator fun set` for the write-back half of `a[i] op= v` and,
    /// on success, record it via `IndexedCompoundAssignOperatorBinding` so
    /// KIR lowering can dispatch to it instead of the raw array runtime. Only
    /// called once `get()` has already resolved to a real member (see the
    /// `operatorResolved` / `isConcreteArrayLikeReceiverType` guard at the
    /// call site); a `get`-only receiver (no matching `set`) is left
    /// unbound, and KIR lowering keeps its previous (pre-existing) fallback
    /// behavior for that edge case.
    private func bindIndexedCompoundAssignSetOperator(
        _ id: ExprID,
        receiverType: TypeID,
        indexTypes: [TypeID],
        valueType: TypeID,
        elementType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        let setName = interner.intern("set")
        let setCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: setName, receiverType: receiverType, sema: sema, interner: interner
        )
        guard !setCandidates.isEmpty else { return }

        var callArgTypes = indexTypes
        callArgTypes.append(valueType)
        let callArgs = callArgTypes.map { CallArg(type: $0) }
        let resolved = ctx.resolver.resolveCall(
            candidates: setCandidates,
            call: CallExpr(range: range, calleeName: setName, args: callArgs),
            expectedType: nil, implicitReceiverType: receiverType, ctx: ctx.semaCtx
        )
        guard let chosenSet = resolved.chosenCallee else { return }

        sema.bindings.bindIndexedCompoundAssignOperator(
            id,
            binding: IndexedCompoundAssignOperatorBinding(
                setCall: CallBinding(
                    chosenCallee: chosenSet,
                    substitutedTypeArguments: resolved.substitutedTypeArguments
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { _, value in value },
                    parameterMapping: resolved.parameterMapping
                ),
                elementType: elementType
            )
        )
    }

    /// Resolve `operator fun get` on the receiver and return (elementType, wasResolved).
    private func resolveIndexedGetElement(
        id: ExprID,
        receiverType: TypeID,
        getCandidates: [SymbolID],
        indexTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> (TypeID, Bool) {
        let sema = ctx.sema
        let interner = ctx.interner
        let getName = interner.intern("get")
        let fallback = driver.helpers.arrayElementType(
            for: receiverType, sema: sema, interner: interner
        ) ?? sema.types.anyType

        guard !getCandidates.isEmpty else { return (fallback, false) }

        let callArgs = indexTypes.map { CallArg(type: $0) }
        let resolved = ctx.resolver.resolveCall(
            candidates: getCandidates,
            call: CallExpr(range: range, calleeName: getName, args: callArgs),
            expectedType: nil, implicitReceiverType: receiverType, ctx: ctx.semaCtx
        )
        guard let chosen = resolved.chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosen)
        else { return (fallback, false) }

        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: resolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { _, value in value },
            parameterMapping: resolved.parameterMapping
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let elementType = sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
        return (elementType, true)
    }

    /// Compute the result type for a compound binary operation on an indexed element.
    private func compoundOpResultType(
        assignOp: CompoundAssignOp,
        elementType: TypeID,
        valueType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        let stringType = sema.types.stringType
        let underlyingOp = driver.helpers.compoundAssignToBinaryOp(assignOp)
        return switch underlyingOp {
        case .add:
            (elementType == stringType || valueType == stringType) ? stringType : elementType
        default:
            elementType
        }
    }

    func inferLocalFunDeclExpr(
        _ id: ExprID,
        name: InternedString,
        valueParams: [ValueParamDecl],
        returnTypeRef: TypeRefID?,
        body: FunctionBody,
        isSuspend: Bool,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        var parameterTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for param in valueParams {
            let paramType: TypeID = if let typeRefID = param.type {
                driver.helpers.resolveTypeRef(
                    typeRefID,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: ctx.scope,
                    diagnostics: ctx.semaCtx.diagnostics,
                    inferenceContext: ctx,
                    usageRange: range
                )
            } else {
                sema.types.anyType
            }
            parameterTypes.append(paramType)
            let paramSymbol = sema.symbols.define(
                kind: .valueParameter,
                name: param.name,
                fqName: [
                    interner.intern("__localfun_\(id.rawValue)"),
                    param.name,
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(paramType, for: paramSymbol)
            paramSymbols.append(paramSymbol)
        }

        let resolvedReturnType: TypeID = if let returnTypeRef {
            driver.helpers.resolveTypeRef(
                returnTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics,
                inferenceContext: ctx,
                usageRange: range
            )
        } else {
            switch body {
            case .expr:
                sema.types.anyType
            case .block, .unit:
                sema.types.unitType
            }
        }

        var functionFlags: SymbolFlags = []
        if isSuspend {
            functionFlags.insert(.suspendFunction)
        }
        let funSymbol = sema.symbols.define(
            kind: .function,
            name: name,
            fqName: [
                interner.intern("__localfun_\(id.rawValue)"),
                name,
            ],
            declSite: range,
            visibility: .private,
            flags: functionFlags
        )

        let signature = FunctionSignature(
            parameterTypes: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: isSuspend,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: valueParams.map(\.hasDefaultValue),
            valueParameterIsVararg: valueParams.map(\.isVararg),
            valueParameterAllowsNonLocalReturn: valueParams.map { !$0.isCrossinline && !$0.isNoinline }
        )
        sema.symbols.setFunctionSignature(signature, for: funSymbol)

        let funType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: isSuspend,
            nullability: .nonNull
        )))

        // Local functions introduce a new scope for control flow: reset loop/lambda stacks.
        var bodyLocals = locals; let bodyCtx = ctx.copying(
            loopDepth: 0,
            loopLabelStack: [],
            lambdaLabelStack: [],
            lambdaDepth: 0,
            enclosingFunctionReturnType: resolvedReturnType
        )
        for (i, param) in valueParams.enumerated() {
            bodyLocals[param.name] = (parameterTypes[i], paramSymbols[i], false, true)
        }
        bodyLocals[name] = (funType, funSymbol, false, true)
        let inferredBodyType: TypeID
        switch body {
        case let .block(exprs, _):
            var lastType: TypeID = sema.types.unitType
            for (index, expr) in exprs.enumerated() {
                let isLast = index == exprs.count - 1
                let expected = isLast && returnTypeRef != nil ? resolvedReturnType : nil
                lastType = driver.inferExpr(expr, ctx: bodyCtx, locals: &bodyLocals, expectedType: expected)
            }
            inferredBodyType = lastType
        case let .expr(exprID, _):
            inferredBodyType = driver.inferExpr(
                exprID,
                ctx: bodyCtx,
                locals: &bodyLocals,
                expectedType: returnTypeRef != nil ? resolvedReturnType : nil
            )
        case .unit:
            inferredBodyType = sema.types.unitType
        }

        if returnTypeRef == nil, case .expr = body, inferredBodyType != sema.types.errorType {
            let inferredSignature = FunctionSignature(
                parameterTypes: parameterTypes,
                returnType: inferredBodyType,
                isSuspend: isSuspend,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: valueParams.map(\.hasDefaultValue),
                valueParameterIsVararg: valueParams.map(\.isVararg),
                valueParameterAllowsNonLocalReturn: valueParams.map { !$0.isCrossinline && !$0.isNoinline }
            )
            sema.symbols.setFunctionSignature(inferredSignature, for: funSymbol)
        }
        let finalReturnType = sema.symbols.functionSignature(for: funSymbol)?.returnType ?? resolvedReturnType
        let finalFunType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: finalReturnType,
            isSuspend: isSuspend,
            nullability: .nonNull
        )))

        locals[name] = (finalFunType, funSymbol, false, true)
        sema.bindings.bindIdentifier(id, symbol: funSymbol)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
