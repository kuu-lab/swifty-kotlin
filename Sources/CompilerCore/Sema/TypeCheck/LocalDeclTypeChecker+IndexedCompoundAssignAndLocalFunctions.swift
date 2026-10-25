
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
        let allGetMembers = driver.helpers.collectMemberFunctionCandidates(
            named: getName, receiverType: receiverType, sema: sema, interner: interner
        )
        var getCandidates = ctx.filterByVisibility(allGetMembers).visible.filter {
            ctx.cachedSymbol($0)?.flags.contains(.operatorFunction) == true
        }
        if getCandidates.isEmpty {
            getCandidates = collectIndexedOperatorExtensionCandidates(
                named: getName, receiverType: receiverType, locals: locals, ctx: ctx
            )
        }
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
        // Indexed `++` / `--` is represented as a compound assignment with a
        // synthetic `1`. Its type depends on the element, so defer that literal
        // until `get()` has supplied the element type. Explicit RHS expressions
        // keep their existing eager, unconstrained inference.
        let isIncrementDecrement = ctx.ast.arena.isIncrementDecrement(id)
        let initialValueType: TypeID?
        if isIncrementDecrement {
            initialValueType = nil
        } else {
            initialValueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
        }

        let getCall = CallExpr(
            range: range,
            calleeName: getName,
            args: zip(indices, indexTypes).map { index, type in
                let literal = driver.callChecker.integerLiteralValues(index, ast: ctx.ast)
                return CallArg(type: type, signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned)
            }
        )
        if ctx.resolver.probeCall(
            candidates: getCandidates, call: getCall, expectedType: nil,
            implicitReceiverType: receiverType, ctx: sema
        ).viableCandidates.isEmpty {
            let extensions = collectIndexedOperatorExtensionCandidates(
                named: getName, receiverType: receiverType, call: getCall, locals: locals, ctx: ctx
            )
            if !extensions.isEmpty { getCandidates = extensions }
        }

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
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-STAR-PROJECTED-WRITE",
                "Compound assignment to an element of a star-projected array ('Array<*>') is not allowed: the element type is erased, so it cannot be determined which primitive representation to read and write.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        var (elementType, operatorResolved) = resolveIndexedGetElement(
            id: id, receiverType: receiverType, getCandidates: getCandidates, getCall: getCall,
            ctx: ctx
        )
        if ctx.ast.arena.isNullAssertedCompoundAssignRead(id) {
            // `a[i]!! += v`: the `!!` applies to the element read by `get()`.
            elementType = sema.types.definitelyNonNullForm(of: elementType)
        }

        // A member `get` sharing only the convention name (no `operator`
        // modifier) cannot serve `x[i] op= v`; reject instead of falling back
        // to the built-in array path.
        if !operatorResolved,
           allGetMembers.contains(where: { driver.helpers.isNonOperatorConventionFunction($0, sema: sema) })
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0432",
                "'operator' modifier is required on 'get' in '\(driver.helpers.conventionReceiverDisplayName(receiverType, sema: sema, interner: interner))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        let isBuiltinNumericIncrement = isIncrementDecrement
            && driver.exprChecker.isBuiltinNumericIncrementDecrementTarget(elementType, sema: sema)
        let valueType = initialValueType ?? driver.inferExpr(
            valueExpr,
            ctx: ctx,
            locals: &locals,
            expectedType: isBuiltinNumericIncrement ? elementType : nil
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
                solver: ConstraintSolver(), sema: sema, diagnostics: ctx.sema.diagnostics
            )
        }

        // `a[i] += v` / `a[i]++` on an element type that defines its own
        // operator (`plusAssign`, `plus`, `inc`, ...) must call it on the
        // `get()` result instead of the builtin numeric/String arithmetic.
        let elementOperator: IndexedCompoundAssignElementOperatorBinding?
        switch resolveIndexedElementOperator(
            id, op: op, receiverType: receiverType, elementType: elementType,
            valueType: valueType, range: range, locals: locals, ctx: ctx
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
            guard driver.exprChecker.isBuiltinCompoundAssignOperand(op: op, lhs: elementType, rhs: valueType, sema: sema) else {
                let operatorName = driver.exprChecker.operatorFunctionNames(
                    for: driver.helpers.compoundAssignToBinaryOp(op), interner: interner
                )[0]
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            elementOperator = nil
        case let .resolved(binding):
            elementOperator = binding
            sema.bindings.bindIndexedCompoundAssignElementOperator(id, binding: binding)
        }

        let resultType = if isBuiltinNumericIncrement {
            // Built-in inc/dec writes its wrapped result back to the element
            // type, even when ordinary binary arithmetic promotes that type.
            elementType
        } else {
            elementOperator?.resultType ?? compoundOpResultType(
                assignOp: op, elementType: elementType, valueType: valueType, sema: sema
            )
        }

        // KSWIFTK-BUG: the write-back half of `a[i] op= v` must go through the
        // same custom operator `set()` that a plain `a[i] = v` would resolve,
        // not the raw built-in array runtime. Built-in array members still use
        // the raw array/boxing path, while an applicable extension operator
        // on an array type must use its matching extension `set()`.
        // An in-place `plusAssign` mutates the element returned by `get()`
        // and never writes it back, so the receiver needs no `set()`.
        // A selected extension `get()` on an array-like receiver is custom
        // too; its matching `set()` must be bound so lowering doesn't bypass
        // both extensions through the raw array runtime.
        let getResolvedAsExtension = sema.bindings.callBinding(for: id).map {
            driver.helpers.declaresExtensionReceiver($0.chosenCallee, sema: sema, interner: interner)
        } ?? false
        if operatorResolved,
           elementOperator?.kind != .inPlace,
           (!isConcreteArrayLikeReceiverType(receiverType, sema: sema, interner: interner)
               || getResolvedAsExtension)
        {
            let setOperatorBound = bindIndexedCompoundAssignSetOperator(
                id, receiverType: receiverType, indexExprs: indices, indexTypes: indexTypes, valueType: resultType,
                elementType: elementType, range: range, locals: locals, ctx: ctx
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
            let arithmeticLhs = resolvePrimitiveArithmeticUpperBound(
                of: elementType, types: sema.types, symbols: sema.symbols
            ) ?? elementType
            let arithmeticRhs = resolvePrimitiveArithmeticUpperBound(
                of: valueType, types: sema.types, symbols: sema.symbols
            ) ?? valueType
            let isBuiltinArithmeticPair = sema.types.isBuiltinArithmeticOperand(arithmeticLhs)
                && sema.types.isBuiltinArithmeticOperand(arithmeticRhs)
            // Builtin indexed `++` / `--` has no explicit RHS: the synthetic
            // Int literal `1` is an AST implementation detail, while the
            // operation is defined by the element type. Numeric binary
            // operators also accept a different RHS type when their result
            // can be written back to the element.
            let isStringConcatenation = binaryOp == .add
                && sema.types.makeNonNullable(elementType) == sema.types.stringType
            if !isCharOffset && !isBuiltinNumericIncrement && !isBuiltinArithmeticPair && !isStringConcatenation {
                driver.emitSubtypeConstraint(
                    left: valueType, right: elementType,
                    range: ctx.ast.arena.exprRange(valueExpr) ?? range,
                    solver: ConstraintSolver(), sema: sema, diagnostics: ctx.sema.diagnostics
                )
            }
            driver.emitSubtypeConstraint(
                left: resultType, right: elementType, range: range,
                solver: ConstraintSolver(), sema: sema, diagnostics: ctx.sema.diagnostics
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
        locals: LocalBindings,
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
                names: [name], args: [], elementType: elementType, range: range, locals: locals, ctx: ctx
            ) else {
                return .builtin
            }
            guard sema.types.isSubtype(returnType, elementType) else {
                ctx.sema.diagnostics.error(
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
            names: assignNames, args: args, elementType: elementType, range: range, locals: locals, ctx: ctx
        )
        let binary = resolveElementOperatorCall(
            names: binaryNames, args: args, elementType: elementType, range: range, locals: locals, ctx: ctx
        ).flatMap { call, returnType in
            sema.types.isSubtype(returnType, elementType) ? (call, returnType) : nil
        }

        if let (call, returnType) = inPlace {
            guard sema.types.isSubtype(returnType, sema.types.unitType) else {
                ctx.sema.diagnostics.error(
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
                ctx.sema.diagnostics.error(
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

    /// Does not touch `callBindings[id]`, which holds the `get()` binding.
    private func resolveElementOperatorCall(
        names: [InternedString],
        args: [CallArg],
        elementType: TypeID,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> (CallBinding, TypeID)? {
        let sema = ctx.sema
        let call = CallExpr(range: range, calleeName: names[0], args: args)
        var candidates = driver.exprChecker.collectOperatorCandidates(
            names: names, receiverType: elementType, call: call, locals: locals, ctx: ctx
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
            candidates: candidates, call: call,
            expectedType: nil, implicitReceiverType: elementType, ctx: ctx.sema
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
        let operatorCallBinding = CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: resolved.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue }).map { _, value in value },
            parameterMapping: resolved.parameterMapping
        )
        return (operatorCallBinding, returnType)
    }

    /// `a[i] += v` is only ambiguous between `plusAssign` and `plus` when the
    /// `plus` form could actually be written back through `set()`.
    private func receiverSupportsIndexedSet(_ receiverType: TypeID, ctx: TypeInferenceContext) -> Bool {
        if isConcreteArrayLikeReceiverType(receiverType, sema: ctx.sema, interner: ctx.interner) {
            return true
        }
        return driver.helpers.collectMemberFunctionCandidates(
            named: ctx.interner.intern("set"), receiverType: receiverType,
            sema: ctx.sema, interner: ctx.interner
        ).contains { ctx.cachedSymbol($0)?.flags.contains(.operatorFunction) == true }
    }

    /// Mirrors CallLowerer+Operators.swift's isGenericArrayReceiverType/
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

    /// Mirrors CallLowerer+ReceiverTypePredicates.swift's isConcreteArrayLikeType,
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
    /// called once `get()` has resolved to an operator and either the
    /// receiver is not a concrete array or the selected `get()` is an
    /// extension on an array type. Built-in array member access keeps the raw
    /// array path. A custom `get` without a matching `set` is rejected by the
    /// caller instead of falling back to raw array access.
    /// Returns `true` once a matching `set()` overload is resolved and bound;
    /// `false` when the receiver has no usable `set()` (missing entirely, or
    /// no overload whose parameters accept `indexTypes + valueType`) — the
    /// caller must then treat this as a hard Sema error rather than silently
    /// falling back to the raw array runtime.
    private func bindIndexedCompoundAssignSetOperator(
        _ id: ExprID,
        receiverType: TypeID,
        indexExprs: [ExprID],
        indexTypes: [TypeID],
        valueType: TypeID,
        elementType: TypeID,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        let interner = ctx.interner
        let setName = interner.intern("set")
        var setCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: setName, receiverType: receiverType, sema: sema, interner: interner
        ).filter {
            ctx.cachedSymbol($0)?.flags.contains(.operatorFunction) == true
        }
        var callArgs = zip(indexExprs, indexTypes).map { expr, type in
            let literal = driver.callChecker.integerLiteralValues(expr, ast: ctx.ast)
            return CallArg(type: type, signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned)
        }
        callArgs.append(CallArg(type: valueType, bindsToLastParameter: true))
        let setCall = CallExpr(range: range, calleeName: setName, args: callArgs)
        if ctx.resolver.probeCall(
            candidates: setCandidates, call: setCall, expectedType: nil,
            implicitReceiverType: receiverType, ctx: sema
        ).viableCandidates.isEmpty {
            let extensions = collectIndexedOperatorExtensionCandidates(
                named: setName, receiverType: receiverType, call: setCall, locals: locals, ctx: ctx
            )
            if !extensions.isEmpty { setCandidates = extensions }
        }
        guard !setCandidates.isEmpty else {
            reportMissingIndexedSetOperator(range: range, receiverType: receiverType, ctx: ctx)
            return false
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: setCandidates,
            call: setCall,
            expectedType: nil, implicitReceiverType: receiverType, ctx: ctx.sema
        )
        guard let chosenSet = resolved.chosenCallee else {
            reportMissingIndexedSetOperator(range: range, receiverType: receiverType, ctx: ctx)
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

    private func reportMissingIndexedSetOperator(range: SourceRange, receiverType: TypeID, ctx: TypeInferenceContext) {
        let sema = ctx.sema
        let interner = ctx.interner
        let hasNonOperatorSetMember = driver.helpers.collectMemberFunctionCandidates(
            named: interner.intern("set"), receiverType: receiverType,
            sema: sema, interner: interner
        ).contains { driver.helpers.isNonOperatorConventionFunction($0, sema: sema) }
        if hasNonOperatorSetMember {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0432",
                "'operator' modifier is required on 'set' in '\(driver.helpers.conventionReceiverDisplayName(receiverType, sema: sema, interner: interner))'.",
                range: range
            )
            return
        }
        ctx.sema.diagnostics.error(
            "KSWIFTK-SEMA-0002",
            "No viable overload found for operator 'set'.",
            range: range
        )
    }

    /// Returns (elementType, wasResolved).
    private func resolveIndexedGetElement(
        id: ExprID,
        receiverType: TypeID,
        getCandidates: [SymbolID],
        getCall: CallExpr,
        ctx: TypeInferenceContext
    ) -> (TypeID, Bool) {
        let sema = ctx.sema
        let interner = ctx.interner
        let fallback = driver.helpers.arrayElementType(
            for: receiverType, sema: sema, interner: interner
        ) ?? sema.types.anyType

        guard !getCandidates.isEmpty else { return (fallback, false) }

        let resolved = ctx.resolver.resolveCall(
            candidates: getCandidates,
            call: getCall,
            expectedType: nil, implicitReceiverType: receiverType, ctx: ctx.sema
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

    private func compoundOpResultType(
        assignOp: CompoundAssignOp,
        elementType: TypeID,
        valueType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        let stringType = sema.types.stringType
        let underlyingOp = driver.helpers.compoundAssignToBinaryOp(assignOp)
        let arithmeticLhs = resolvePrimitiveArithmeticUpperBound(
            of: elementType, types: sema.types, symbols: sema.symbols
        ) ?? elementType
        let arithmeticRhs = resolvePrimitiveArithmeticUpperBound(
            of: valueType, types: sema.types, symbols: sema.symbols
        ) ?? valueType
        if sema.types.isBuiltinArithmeticOperand(arithmeticLhs),
           sema.types.isBuiltinArithmeticOperand(arithmeticRhs)
        {
            if arithmeticLhs == sema.types.charType,
               arithmeticRhs == sema.types.intType,
               underlyingOp == .add || underlyingOp == .subtract
            {
                return sema.types.charType
            }
            if arithmeticLhs == sema.types.doubleType || arithmeticRhs == sema.types.doubleType {
                return sema.types.doubleType
            }
            if arithmeticLhs == sema.types.floatType || arithmeticRhs == sema.types.floatType {
                return sema.types.floatType
            }
            if arithmeticLhs == sema.types.longType || arithmeticRhs == sema.types.longType {
                return sema.types.longType
            }
            if arithmeticLhs == sema.types.ulongType || arithmeticRhs == sema.types.ulongType {
                return sema.types.ulongType
            }
            if arithmeticLhs == sema.types.uintType || arithmeticRhs == sema.types.uintType
                || arithmeticLhs == sema.types.ubyteType || arithmeticRhs == sema.types.ubyteType
                || arithmeticLhs == sema.types.ushortType || arithmeticRhs == sema.types.ushortType
            {
                return sema.types.uintType
            }
            return sema.types.intType
        }
        return switch underlyingOp {
        case .add:
            sema.types.makeNonNullable(elementType) == stringType ? stringType : elementType
        default:
            elementType
        }
    }

    func inferLocalFunDeclExpr(
        _ id: ExprID,
        name: InternedString,
        typeParams: [TypeParamDecl] = [],
        contextReceivers: [ContextReceiverDecl] = [],
        receiverTypeRef: TypeRefID? = nil,
        valueParams: [ValueParamDecl],
        returnTypeRef: TypeRefID?,
        body: FunctionBody,
        isSuspend: Bool,
        expectedType: TypeID? = nil,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let localFunctionScope = FunctionScope(parent: ctx.scope, symbols: sema.symbols)
        var typeParameterSymbols: [SymbolID] = []
        var reifiedTypeParameterIndices: Set<Int> = []
        for (index, typeParam) in typeParams.enumerated() {
            if typeParam.variance != .invariant {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0443",
                    "Variance annotations are only allowed for type parameters of classes and interfaces.",
                    range: range
                )
            }
            var flags: SymbolFlags = []
            if typeParam.isReified {
                flags.insert(.reifiedTypeParameter)
                reifiedTypeParameterIndices.insert(index)
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-0020",
                    "Only type parameters of inline functions can be reified",
                    range: range
                )
            }
            let typeParamSymbol = sema.symbols.define(
                kind: .typeParameter,
                name: typeParam.name,
                fqName: [
                    interner.intern("__localfun_\(id.rawValue)"),
                    name,
                    typeParam.name,
                ],
                declSite: range,
                visibility: .private,
                flags: flags
            )
            typeParameterSymbols.append(typeParamSymbol)
            localFunctionScope.insert(typeParamSymbol)
        }
        let functionTypeContext = ctx.copying(scope: localFunctionScope)
        for (typeParam, typeParamSymbol) in zip(typeParams, typeParameterSymbols) {
            let upperBounds = typeParam.upperBounds.compactMap { boundRef in
                driver.helpers.resolveTypeRef(
                    boundRef,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: localFunctionScope,
                    diagnostics: sema.diagnostics,
                    inferenceContext: functionTypeContext,
                    usageRange: range
                )
            }
            if !upperBounds.isEmpty {
                sema.symbols.setTypeParameterUpperBounds(upperBounds, for: typeParamSymbol)
            }
        }
        let typeParameterUpperBoundsList = typeParameterSymbols.map {
            sema.symbols.typeParameterUpperBounds(for: $0)
        }

        let receiverType = receiverTypeRef.map {
            driver.helpers.resolveTypeRef(
                $0, ast: ast, sema: sema, interner: interner, scope: localFunctionScope,
                diagnostics: ctx.sema.diagnostics, inferenceContext: functionTypeContext, usageRange: range
            )
        }
        let contextReceiverTypes = contextReceivers.compactMap { contextReceiver in
            driver.helpers.resolveTypeRef(
                contextReceiver.type,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: localFunctionScope,
                diagnostics: ctx.sema.diagnostics,
                inferenceContext: functionTypeContext,
                usageRange: range
            )
        }
        let contextParameterDeclarations: [
            (declaration: ContextReceiverDecl, symbol: SymbolID, type: TypeID)
        ] = contextReceivers.enumerated().compactMap { index, declaration
            -> (declaration: ContextReceiverDecl, symbol: SymbolID, type: TypeID)? in
            guard declaration.isContextParameter, contextReceiverTypes.indices.contains(index) else {
                return nil
            }
            let symbol = sema.symbols.define(
                kind: .valueParameter,
                name: declaration.name ?? interner.intern("$contextParameter\(index)"),
                fqName: [
                    interner.intern("__localfun_\(id.rawValue)"),
                    name,
                    interner.intern("$context"),
                    interner.intern("$\(index)"),
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(contextReceiverTypes[index], for: symbol)
            return (declaration: declaration, symbol: symbol, type: contextReceiverTypes[index])
        }
        // Anonymous-function declarations receive an expected type from their
        // wrapper block, so unannotated parameters can be typed before the body.
        let expectedFunctionType: FunctionType? = {
            guard let expectedType else { return nil }
            if case let .functionType(functionType) = sema.types.kind(of: expectedType) {
                return functionType
            }
            if let functionType = sema.types.nominalFunctionType(for: expectedType) {
                return functionType
            }
            return driver.helpers.samFunctionType(for: expectedType, sema: sema)
        }()
        let expectedParameterTypes = expectedFunctionType.flatMap { functionType in
            functionType.params.count == valueParams.count ? functionType.params : nil
        }
        var parameterTypes: [TypeID] = []
        var paramSymbols: [SymbolID] = []
        for (index, param) in valueParams.enumerated() {
            let paramType: TypeID = if let typeRefID = param.type {
                driver.helpers.resolveTypeRef(
                    typeRefID,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: localFunctionScope,
                    diagnostics: ctx.sema.diagnostics,
                    inferenceContext: functionTypeContext,
                    usageRange: range
                )
            } else if let expectedParameterTypes, expectedParameterTypes.indices.contains(index) {
                expectedParameterTypes[index]
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
                scope: localFunctionScope,
                diagnostics: ctx.sema.diagnostics,
                inferenceContext: functionTypeContext,
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
        if ast.arena.isInfixFunction(id) { functionFlags.insert(.infixFunction) }
        if ast.arena.isOperatorFunction(id) { functionFlags.insert(.operatorFunction) }
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
            contextReceiverTypes: contextReceiverTypes,
            contextParameterSymbols: contextParameterDeclarations.map(\.symbol),
            contextParameterTypes: contextParameterDeclarations.map(\.type),
            parameterTypes: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: isSuspend,
            valueParameterSymbols: paramSymbols,
            valueParameterHasDefaultValues: valueParams.map(\.hasDefaultValue),
            valueParameterIsVararg: valueParams.map(\.isVararg),
            valueParameterAllowsNonLocalReturn: valueParams.map { !$0.isCrossinline && !$0.isNoinline },
            typeParameterSymbols: typeParameterSymbols,
            reifiedTypeParameterIndices: reifiedTypeParameterIndices,
            typeParameterUpperBoundsList: typeParameterUpperBoundsList
        )
        sema.symbols.setFunctionSignature(signature, for: funSymbol)

        let funType = sema.types.make(.functionType(FunctionType(
            contextReceivers: contextParameterDeclarations.map(\.type),
            receiver: receiverType,
            params: parameterTypes,
            returnType: resolvedReturnType,
            isSuspend: isSuspend,
            nullability: .nonNull
        )))

        // Local functions share the lexical call namespace, where same-named
        // declarations form an overload set. Keep them in scope separately
        // from local values, which use `LocalBindings` for value-position lookup.
        ctx.scope.insert(funSymbol)
        ctx.semaCacheContext?.invalidateScopeLookups()

        // Local functions introduce a new scope for control flow: reset loop/lambda stacks.
        let previousFunctionScope = ctx.dataFlow.localStability.currentLocalFunctionScope
        ctx.dataFlow.localStability.currentLocalFunctionScope = id
        defer { ctx.dataFlow.localStability.currentLocalFunctionScope = previousFunctionScope }
        var bodyLocals = locals
        // A deferred body cannot inherit mutable captures' flow facts from
        // the declaration site. Establish its own facts while checking it.
        for (name, local) in bodyLocals where local.isMutable {
            let declaredType = sema.symbols.propertyType(for: local.symbol) ?? local.type
            bodyLocals[name] = (declaredType, local.symbol, local.isMutable, local.isInitialized)
        }
        bodyLocals.memberFlow = [:]
        let bodyReceiverType: TypeID? = receiverType ?? ctx.implicitReceiverType
        var bodyCtx = driver.helpers.localFunctionOptInContext(ctx).copying(
            scope: localFunctionScope,
            implicitReceiverType: bodyReceiverType,
            loopDepth: 0,
            loopLabelStack: [],
            lambdaLabelStack: [],
            lambdaReturnScopes: [],
            lambdaDepth: 0,
            enclosingFunctionReturnType: resolvedReturnType,
            enclosingFunctionSymbol: funSymbol,
            enclosingFunctionProhibitsExpressionBodyReturn: body.isExpressionBody
                && returnTypeRef == nil,
            returnTargetIsInitBlock: false,
            enclosingLambdaExprIDs: [],
            flowState: DataFlowState(),
            currentDeclSymbol: receiverType != nil ? funSymbol : ctx.currentDeclSymbol
        )
        bodyCtx.isUnitCoercionContext = resolvedReturnType == sema.types.unitType
        bodyCtx = bodyCtx.with(
            contextReceiverTypes: ctx.contextReceiverTypes + contextParameterDeclarations.map(\.type)
        )
        bodyCtx.suspensionContext = SuspensionContext(function: funSymbol)
        if let receiverType {
            let receiverSymbol = SyntheticSymbolScheme.receiverParameterSymbol(for: funSymbol)
            bodyLocals[interner.intern("this")] = (receiverType, receiverSymbol, false, true)
            bodyCtx = bodyCtx.withOuterReceiver(label: name, type: receiverType, symbol: receiverSymbol)
        }

        var defaultBaseLocals = locals
        defaultBaseLocals[name] = (funType, funSymbol, false, true)
        driver.declChecker.typeCheckParameterDefaultValues(
            valueParams,
            signature: signature,
            ctx: bodyCtx,
            solver: driver.solver,
            diagnostics: sema.diagnostics,
            baseLocals: defaultBaseLocals
        )

        // The function's own name stays bound in value position for
        // recursion-relevant lookups, but a same-named parameter shadows it:
        // `fun a(a: Any) = a === 1.1` reads the parameter, not the function
        // (KUU-3210). Calls still see the function through `ctx.scope`.
        bodyLocals[name] = (funType, funSymbol, false, true)
        for (i, param) in valueParams.enumerated() {
            // Keep element types in the call signature while exposing the
            // source-level array type for reference varargs inside local bodies.
            let localType = driver.declChecker.localTypeForParameter(
                at: i, signature: signature, sema: sema, interner: interner,
                referenceVarargAsArray: true
            )
            sema.symbols.setPropertyType(localType, for: paramSymbols[i])
            bodyLocals[param.name] = (localType, paramSymbols[i], false, true)
        }
        for parameter in contextParameterDeclarations {
            if let parameterName = parameter.declaration.name {
                bodyLocals[parameterName] = (parameter.type, parameter.symbol, false, true)
            }
        }
        let inferredBodyType: TypeID
        switch body {
        case let .block(exprs, _):
            var lastType: TypeID = sema.types.unitType
            for (index, expr) in exprs.enumerated() {
                let isLast = index == exprs.count - 1
                let expected = isLast && returnTypeRef != nil ? resolvedReturnType : nil
                lastType = driver.inferExpr(
                    expr,
                    ctx: bodyCtx,
                    locals: &bodyLocals,
                    expectedType: expected,
                    isStatementContext: true
                )
            }
            inferredBodyType = lastType
        case let .expr(exprID, _):
            inferredBodyType = driver.inferExpr(
                exprID,
                ctx: bodyCtx,
                locals: &bodyLocals,
                expectedType: returnTypeRef != nil ? resolvedReturnType : nil
            )
            if returnTypeRef != nil, resolvedReturnType == sema.types.unitType,
               sema.types.makeNonNullable(inferredBodyType) == sema.types.unitType
            {
                sema.bindings.markUnitReturnCoercion(exprID)
            }
        case .unit:
            inferredBodyType = sema.types.unitType
        }

        // Propagate the expression body's value marks onto the local function
        // symbol so call results inherit them through bindCall — mirrors
        // typeCheckFunctionDecl (KUU-2942).
        if case let .expr(bodyExprID, _) = body {
            if sema.bindings.isRangeExpr(bodyExprID) {
                sema.bindings.markRangeSymbol(funSymbol)
                if sema.bindings.isCharRangeExpr(bodyExprID) {
                    sema.bindings.markCharRangeSymbol(funSymbol)
                }
                if sema.bindings.isUIntRangeExpr(bodyExprID) {
                    sema.bindings.markUIntRangeSymbol(funSymbol)
                }
                if sema.bindings.isULongRangeExpr(bodyExprID) {
                    sema.bindings.markULongRangeSymbol(funSymbol)
                }
                if sema.bindings.isFloatingPointRangeExpr(bodyExprID) {
                    sema.bindings.markFloatingPointRangeSymbol(funSymbol)
                    if let elementType = sema.bindings.floatingPointRangeElementType(forExpr: bodyExprID) {
                        sema.bindings.bindFloatingPointRangeElementType(
                            elementType,
                            forSymbol: funSymbol,
                            endExclusive: sema.bindings.isOpenFloatingPointRangeExpr(bodyExprID)
                        )
                    }
                }
            }
            if sema.bindings.isCollectionExpr(bodyExprID) {
                sema.bindings.markCollectionSymbol(funSymbol)
            }
            if sema.bindings.isFlowExpr(bodyExprID) {
                sema.bindings.markFlowSymbol(funSymbol)
                if let flowElementType = sema.bindings.flowElementType(forExpr: bodyExprID) {
                    sema.bindings.bindFlowElementType(flowElementType, forSymbol: funSymbol)
                }
            }
            if let deferredElementType = sema.bindings.deferredElementType(forExpr: bodyExprID) {
                sema.bindings.bindDeferredElementType(deferredElementType, forSymbol: funSymbol)
            }
        }

        if returnTypeRef == nil, case .expr = body, inferredBodyType != sema.types.errorType {
            let inferredSignature = FunctionSignature(
                receiverType: receiverType,
                contextReceiverTypes: contextReceiverTypes,
                contextParameterSymbols: contextParameterDeclarations.map(\.symbol),
                contextParameterTypes: contextParameterDeclarations.map(\.type),
                parameterTypes: parameterTypes,
                returnType: inferredBodyType,
                isSuspend: isSuspend,
                valueParameterSymbols: paramSymbols,
                valueParameterHasDefaultValues: valueParams.map(\.hasDefaultValue),
                valueParameterIsVararg: valueParams.map(\.isVararg),
                valueParameterAllowsNonLocalReturn: valueParams.map { !$0.isCrossinline && !$0.isNoinline },
                typeParameterSymbols: typeParameterSymbols,
                reifiedTypeParameterIndices: reifiedTypeParameterIndices,
                typeParameterUpperBoundsList: typeParameterUpperBoundsList
            )
            sema.symbols.setFunctionSignature(inferredSignature, for: funSymbol)
        }
        let finalReturnType = sema.symbols.functionSignature(for: funSymbol)?.returnType ?? resolvedReturnType
        let finalFunType = sema.types.make(.functionType(FunctionType(
            contextReceivers: contextParameterDeclarations.map(\.type),
            receiver: receiverType,
            params: parameterTypes,
            returnType: finalReturnType,
            isSuspend: isSuspend,
            nullability: .nonNull
        )))

        var localFunctionOuterSymbols = Set(locals.values.map(\.symbol))
        localFunctionOuterSymbols.formUnion(ctx.outerReceiverTypes.compactMap(\.symbol))
        localFunctionOuterSymbols.formUnion(ctx.implicitReceiverStack.map(\.symbol))
        localFunctionOuterSymbols.formUnion(driver.helpers.lexicalTypeParameterSymbols(in: ctx).filter {
            sema.symbols.symbol($0)?.flags.contains(.reifiedTypeParameter) == true
        })
        sema.bindings.bindLocalFunctionCaptureSymbols(
            funSymbol,
            symbols: driver.captureAnalyzer.collectCapturedOuterSymbols(
                inBody: body,
                ast: ast,
                sema: sema,
                outerSymbols: localFunctionOuterSymbols,
                skipNestedClosures: false
            )
        )

        let existingLocalIsValue: Bool = {
            guard let existingLocal = locals[name] else { return false }
            return sema.symbols.symbol(existingLocal.symbol)?.flags.contains(.localFunction) != true
        }()
        if !existingLocalIsValue {
            locals[name] = (finalFunType, funSymbol, false, true)
        }
        sema.bindings.bindIdentifier(id, symbol: funSymbol)
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
