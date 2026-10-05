
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

        // `a[i] += v` / `a[i]++` on an element type that defines its own
        // operator (`plusAssign`, `plus`, `inc`, ...) must call it on the
        // `get()` result instead of the builtin numeric/String arithmetic.
        let elementOperator: IndexedCompoundAssignElementOperatorBinding?
        switch resolveIndexedElementOperator(
            id, op: op, receiverType: receiverType, elementType: elementType,
            valueType: valueType, range: range, ctx: ctx
        ) {
        case .failed:
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        case .builtin:
            if driver.exprChecker.rejectInvalidBuiltinCharCompoundAssignment(
                id, op: op, lhs: elementType, rhs: valueType, range: range, ctx: ctx
            ) {
                return sema.types.errorType
            }
            elementOperator = nil
        case let .resolved(binding):
            elementOperator = binding
            sema.bindings.bindIndexedCompoundAssignElementOperator(id, binding: binding)
        }

        let resultType = elementOperator?.resultType ?? compoundOpResultType(
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
        // An in-place `plusAssign` mutates the element returned by `get()`
        // and never writes it back, so the receiver needs no `set()`.
        if operatorResolved,
           elementOperator?.kind != .inPlace,
           !isConcreteArrayLikeReceiverType(receiverType, sema: sema, interner: interner)
        {
            let setOperatorBound = bindIndexedCompoundAssignSetOperator(
                id, receiverType: receiverType, indexTypes: indexTypes, valueType: resultType,
                elementType: elementType, range: range, ctx: ctx
            )
            // KSWIFTK-BUG: a get()-only receiver with no matching set() overload
            // (wrong arity, mismatched parameter types, ...) must be rejected here,
            // matching real Kotlin's "no set method providing array access" error.
            // Falling through silently would leave `id` unbound by
            // IndexedCompoundAssignOperatorBinding, and KIR lowering would then
            // treat this as the built-in-array fallback shape: kk_array_set on a
            // non-array receiver, using only the first index and silently
            // discarding any additional ones.
            if !setOperatorBound {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
        }

        // The resolved element operator already checked its own argument
        // and result types; these constraints only describe the builtin path.
        if elementOperator == nil {
            let binaryOp = driver.helpers.compoundAssignToBinaryOp(op)
            let isCharOffset = elementType == sema.types.charType
                && valueType == sema.types.intType
                && [.add, .subtract].contains(binaryOp)
            if !isCharOffset {
                driver.emitSubtypeConstraint(
                    left: valueType, right: elementType,
                    range: ctx.ast.arena.exprRange(valueExpr) ?? range,
                    solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
                )
            }
            driver.emitSubtypeConstraint(
                left: resultType, right: elementType, range: range,
                solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
            )
        }

        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    private enum IndexedElementOperatorResolution {
        /// Primitive/String element, or no applicable operator: keep the
        /// builtin `kk_op_*` / string-concat path.
        case builtin
        case resolved(IndexedCompoundAssignElementOperatorBinding)
        /// A diagnostic has already been emitted.
        case failed
    }

    /// Resolves the operator applied to the element of `a[i] op= v`, mirroring
    /// `inferMemberCompoundAssignExpr`: `++`/`--` use `inc()`/`dec()`;
    /// otherwise the in-place `plusAssign`-style operator wins, then the
    /// binary `plus`-style operator, and both being applicable is ambiguous.
    private func resolveIndexedElementOperator(
        _ id: ExprID,
        op: CompoundAssignOp,
        receiverType: TypeID,
        elementType: TypeID,
        valueType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> IndexedElementOperatorResolution {
        let sema = ctx.sema
        let interner = ctx.interner
        let nonNullElement = sema.types.makeNonNullable(elementType)
        if elementType == sema.types.errorType || nonNullElement == sema.types.stringType {
            return .builtin
        }
        if case .primitive = sema.types.kind(of: nonNullElement),
           nonNullElement != sema.types.charType,
           sema.types.makeNonNullable(valueType) != sema.types.charType
        {
            return .builtin
        }
        let exprChecker = driver.exprChecker

        if ctx.ast.arena.isIncrementDecrement(id) {
            let name = interner.intern(op == .plusAssign ? "inc" : "dec")
            guard let (call, returnType) = resolveElementOperatorCall(
                names: [name], args: [], elementType: elementType, range: range, ctx: ctx
            ) else {
                return .builtin
            }
            guard sema.types.isSubtype(returnType, elementType) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0303",
                    "Operator '\(interner.resolve(name))' result type must be assignable to the left-hand side.",
                    range: range
                )
                return .failed
            }
            return .resolved(IndexedCompoundAssignElementOperatorBinding(
                call: call, kind: .incrementDecrement, elementType: elementType, resultType: returnType
            ))
        }

        let assignNames = exprChecker.operatorFunctionNames(for: op, interner: interner)
        let binaryNames = exprChecker.operatorFunctionNames(
            for: driver.helpers.compoundAssignToBinaryOp(op), interner: interner
        )
        let args = [CallArg(type: valueType)]
        let inPlace = resolveElementOperatorCall(
            names: assignNames, args: args, elementType: elementType, range: range, ctx: ctx
        )
        let binary = resolveElementOperatorCall(
            names: binaryNames, args: args, elementType: elementType, range: range, ctx: ctx
        ).flatMap { call, returnType in
            sema.types.isSubtype(returnType, elementType) ? (call, returnType) : nil
        }

        if let (call, returnType) = inPlace {
            guard sema.types.isSubtype(returnType, sema.types.unitType) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0300",
                    "Operator '\(interner.resolve(assignNames[0]))' used in compound assignment must return Unit.",
                    range: range
                )
                return .failed
            }
            let builtinCharOffset = elementType == sema.types.charType
                && valueType == sema.types.intType
                && !exprChecker.hasInvalidBuiltinCharArithmetic(
                    op: driver.helpers.compoundAssignToBinaryOp(op), lhs: elementType, rhs: valueType, sema: sema
                )
            if binary != nil || builtinCharOffset, receiverSupportsIndexedSet(receiverType, ctx: ctx) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0302",
                    "Assignment operator is ambiguous because both '\(interner.resolve(assignNames[0]))' and the corresponding binary operator are applicable.",
                    range: range
                )
                return .failed
            }
            return .resolved(IndexedCompoundAssignElementOperatorBinding(
                call: call, kind: .inPlace, elementType: elementType, resultType: returnType
            ))
        }
        if let (call, returnType) = binary {
            return .resolved(IndexedCompoundAssignElementOperatorBinding(
                call: call, kind: .binary, elementType: elementType, resultType: returnType
            ))
        }
        return .builtin
    }

    /// Resolves an operator member/extension on the element type without
    /// touching `callBindings[id]`, which holds the `get()` binding.
    private func resolveElementOperatorCall(
        names: [InternedString],
        args: [CallArg],
        elementType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> (CallBinding, TypeID)? {
        let sema = ctx.sema
        var candidates = driver.exprChecker.collectOperatorCandidates(
            names: names, receiverType: elementType, ctx: ctx
        )
        if candidates.isEmpty, let valueType = args.first?.type,
           sema.types.makeNonNullable(elementType) == sema.types.charType
            || sema.types.makeNonNullable(valueType) == sema.types.charType
        {
            let name = ctx.interner.resolve(names[0])
            let binaryOp: BinaryOp? = switch name {
            case "plus": .add
            case "minus": .subtract
            case "times": .multiply
            case "div": .divide
            case "rem": .modulo
            default: nil
            }
            let needsExtension = binaryOp.map {
                driver.exprChecker.hasInvalidBuiltinCharArithmetic(op: $0, lhs: elementType, rhs: valueType, sema: sema)
            } ?? name.hasSuffix("Assign")
            if needsExtension {
                candidates = driver.exprChecker.collectScopedOperatorExtensionCandidates(
                    names: names, receiverType: elementType, ctx: ctx
                )
            }
        }
        guard !candidates.isEmpty else { return nil }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(range: range, calleeName: names[0], args: args),
            expectedType: nil, implicitReceiverType: elementType, ctx: ctx.semaCtx
        )
        guard resolved.diagnostic == nil,
              let chosen = resolved.chosenCallee,
              let signature = sema.symbols.functionSignature(for: chosen)
        else {
            return nil
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let returnType = sema.types.substituteTypeParameters(
            in: signature.returnType,
            substitution: resolved.substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
        let call = CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: resolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { _, value in value },
            parameterMapping: resolved.parameterMapping
        )
        return (call, returnType)
    }

    /// `a[i] += v` is only ambiguous between `plusAssign` and `plus` when the
    /// `plus` form could actually be written back through `set()`.
    private func receiverSupportsIndexedSet(_ receiverType: TypeID, ctx: TypeInferenceContext) -> Bool {
        if isConcreteArrayLikeReceiverType(receiverType, sema: ctx.sema, interner: ctx.interner) {
            return true
        }
        return !driver.helpers.collectMemberFunctionCandidates(
            named: ctx.interner.intern("set"), receiverType: receiverType,
            sema: ctx.sema, interner: ctx.interner
        ).isEmpty
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
    /// Returns `true` once a matching `set()` overload is resolved and bound;
    /// `false` when the receiver has no usable `set()` (missing entirely, or
    /// no overload whose parameters accept `indexTypes + valueType`) — the
    /// caller must then treat this as a hard Sema error rather than silently
    /// falling back to the raw array runtime.
    private func bindIndexedCompoundAssignSetOperator(
        _ id: ExprID,
        receiverType: TypeID,
        indexTypes: [TypeID],
        valueType: TypeID,
        elementType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        let interner = ctx.interner
        let setName = interner.intern("set")
        let setCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: setName, receiverType: receiverType, sema: sema, interner: interner
        )
        guard !setCandidates.isEmpty else {
            reportMissingIndexedSetOperator(range: range, ctx: ctx)
            return false
        }

        var callArgTypes = indexTypes
        callArgTypes.append(valueType)
        let callArgs = callArgTypes.map { CallArg(type: $0) }
        let resolved = ctx.resolver.resolveCall(
            candidates: setCandidates,
            call: CallExpr(range: range, calleeName: setName, args: callArgs),
            expectedType: nil, implicitReceiverType: receiverType, ctx: ctx.semaCtx
        )
        guard let chosenSet = resolved.chosenCallee else {
            reportMissingIndexedSetOperator(range: range, ctx: ctx)
            return false
        }

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
        return true
    }

    private func reportMissingIndexedSetOperator(range: SourceRange, ctx: TypeInferenceContext) {
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0002",
            "No viable overload found for operator 'set'.",
            range: range
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
        receiverTypeRef: TypeRefID? = nil,
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

        let receiverType = receiverTypeRef.map {
            driver.helpers.resolveTypeRef(
                $0, ast: ast, sema: sema, interner: interner, scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics, inferenceContext: ctx, usageRange: range
            )
        }
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

        var functionFlags: SymbolFlags = [.localFunction]
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
            receiverType: receiverType,
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
            receiver: receiverType,
            params: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: isSuspend,
            nullability: .nonNull
        )))

        // Local functions introduce a new scope for control flow: reset loop/lambda stacks.
        var bodyLocals = locals
        let bodyReceiverType: TypeID? = receiverType ?? ctx.implicitReceiverType
        var bodyCtx = ctx.copying(
            implicitReceiverType: bodyReceiverType,
            loopDepth: 0,
            loopLabelStack: [],
            lambdaLabelStack: [],
            lambdaDepth: 0,
            enclosingFunctionReturnType: resolvedReturnType,
            currentDeclSymbol: receiverType != nil ? funSymbol : ctx.currentDeclSymbol
        )
        if let receiverType {
            let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: funSymbol)
            bodyLocals[interner.intern("this")] = (receiverType, receiverSymbol, false, true)
            bodyCtx = bodyCtx.withOuterReceiver(label: name, type: receiverType, symbol: receiverSymbol)
        }
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
                receiverType: receiverType,
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
            receiver: receiverType,
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
