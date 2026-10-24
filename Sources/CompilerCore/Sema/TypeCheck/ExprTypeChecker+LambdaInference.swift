
extension ExprTypeChecker {
    private func describe(_ type: TypeID, ctx: TypeInferenceContext) -> String {
        ctx.sema.types.displayName(of: type, symbols: ctx.sema.symbols, interner: ctx.interner)
    }

    /// Type parameters the expected type leaves unsubstituted carry no information,
    /// so annotations always win there. Otherwise only widening is allowed (function
    /// types are contravariant in their parameters).
    ///
    /// `expectedTypeIsSourceDeclared` tells the two kinds of `Any` apart: an
    /// `Any` written in source constrains the annotation, while an `Any` the
    /// compiler synthesized for a call whose type variable stayed unsolved
    /// (`Grouping<K, E>`'s accumulator) carries no information.
    func lambdaAnnotationIsCompatible(
        annotated: TypeID,
        declared: TypeID,
        expectedTypeIsSourceDeclared: Bool,
        sema: SemaModule
    ) -> Bool {
        if annotated == declared || declared == sema.types.errorType || annotated == sema.types.errorType {
            return true
        }
        if typeMentionsTypeParameter(declared, sema: sema) {
            return true
        }
        if !expectedTypeIsSourceDeclared, case .any = sema.types.kind(of: declared) {
            return true
        }
        return sema.types.isSubtype(declared, annotated)
    }

    private func typeMentionsTypeParameter(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .typeParam:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return typeMentionsTypeParameter(inner, sema: sema)
                case .star:
                    return false
                }
            }
        case let .functionType(functionType):
            return functionType.params.contains { typeMentionsTypeParameter($0, sema: sema) }
                || typeMentionsTypeParameter(functionType.returnType, sema: sema)
                || (functionType.receiver.map { typeMentionsTypeParameter($0, sema: sema) } ?? false)
        case let .intersection(members):
            return members.contains { typeMentionsTypeParameter($0, sema: sema) }
        default:
            return false
        }
    }

    private func typeParameterSymbols(in type: TypeID, sema: SemaModule) -> Set<SymbolID> {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case let .typeParam(typeParam):
            return [typeParam.symbol]
        case let .classType(classType):
            return classType.args.reduce(into: Set<SymbolID>()) { symbols, argument in
                switch argument {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    symbols.formUnion(typeParameterSymbols(in: inner, sema: sema))
                case .star:
                    break
                }
            }
        case let .functionType(functionType):
            var symbols = Set<SymbolID>()
            for receiver in functionType.contextReceivers {
                symbols.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            if let receiver = functionType.receiver {
                symbols.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            for parameter in functionType.params {
                symbols.formUnion(typeParameterSymbols(in: parameter, sema: sema))
            }
            symbols.formUnion(typeParameterSymbols(in: functionType.returnType, sema: sema))
            return symbols
        case let .kClassType(kClassType):
            return typeParameterSymbols(in: kClassType.argument, sema: sema)
        case let .intersection(members):
            return members.reduce(into: Set<SymbolID>()) { symbols, member in
                symbols.formUnion(typeParameterSymbols(in: member, sema: sema))
            }
        default:
            return []
        }
    }

    func resolveLambdaParamAnnotations(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        paramCount: Int
    ) -> [TypeID?]? {
        let sema = ctx.sema
        guard let typeRefs = ctx.ast.arena.lambdaParamTypeRefs(for: id),
              typeRefs.count == paramCount
        else {
            return nil
        }
        var resolved: [TypeID?] = []
        resolved.reserveCapacity(typeRefs.count)
        for typeRef in typeRefs {
            guard let typeRef else {
                resolved.append(nil)
                continue
            }
            let type = driver.helpers.resolveTypeRef(
                typeRef,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope,
                inferenceContext: ctx
            )
            resolved.append(type == sema.types.errorType ? nil : type)
        }
        return resolved.contains(where: { $0 != nil }) ? resolved : nil
    }

    func inferLambdaLiteralExpr(
        _ id: ExprID,
        params: [InternedString],
        body: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        expectedTypeIsHintOnly: Bool = false
    ) -> TypeID {
        let previousFunctionScope = ctx.dataFlow.localStability.currentLocalFunctionScope
        ctx.dataFlow.localStability.currentLocalFunctionScope = nil
        defer { ctx.dataFlow.localStability.currentLocalFunctionScope = previousFunctionScope }
        let ast = ctx.ast
        let sema = ctx.sema

        let label: InternedString? = if case let .lambdaLiteral(_, _, lbl, _) = ast.arena.expr(id) { lbl } else { nil }
        let samConversion: Bool
        let expectedFunctionType: FunctionType?
        if let expectedType, case let .functionType(functionType) = sema.types.kind(of: expectedType) {
            expectedFunctionType = functionType
            samConversion = false
        } else if let expectedType, let functionType = sema.types.nominalFunctionType(for: expectedType) {
            expectedFunctionType = functionType
            samConversion = false
            sema.bindings.bindNominalFunctionExpectedType(id, type: expectedType)
        } else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
            expectedFunctionType = samFT
            samConversion = true
        } else {
            expectedFunctionType = nil
            samConversion = false
        }

        // A lambda's declared parameter count must match the expected function
        // type — the implicit `it` parameter exists only when the expected type
        // takes exactly one parameter, so `{ }` against `(Int, Int) -> Unit`
        // and `{ a, b -> }` against `(Int) -> Unit` are both errors. Hint-only
        // expected types (the elvis RHS hint) and the synthetic `() -> Any`
        // pushed to directly-invoked lambdas carry no arity contract.
        if !expectedTypeIsHintOnly,
           let expectedType,
           let expectedFunctionType,
           !sema.bindings.isDirectlyInvokedLambdaExpr(id)
        {
            let expectedCount = expectedFunctionType.params.count
            if params.isEmpty, expectedCount > 1 {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0433",
                    "Lambda literal has no declared parameters, but the expected type "
                        + "'\(describe(expectedType, ctx: ctx))' takes \(expectedCount) "
                        + "(an implicit 'it' parameter requires exactly one).",
                    range: ast.arena.exprRange(id)
                )
            } else if !params.isEmpty, params.count != expectedCount {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0433",
                    "Lambda literal declares \(params.count) parameter(s), "
                        + "but the expected type '\(describe(expectedType, ctx: ctx))' takes \(expectedCount).",
                    range: ast.arena.exprRange(id)
                )
            }
        }

        var lambdaLocals = locals
        // Outer receiver `this` symbols are reachable inside the lambda even
        // though the enclosing member's `this` shadows them in `locals` — the
        // enclosing context (e.g. an object literal) captured them, so the
        // lambda can capture them through the same chain.
        let outerSymbols = Set(locals.values.map(\.symbol) + ctx.implicitReceiverStack.map(\.symbol))
            .union(ctx.outerReceiverTypes.compactMap(\.symbol))
        let inferredImplicitItType = params.isEmpty
            ? inferItParameterType(ctx: ctx, id: id, sema: sema, locals: locals)
            : nil
        let inferredAssignmentItType: TypeID? = if !expectedTypeIsHintOnly, params.isEmpty,
                                                   let inferredImplicitItType
        {
            inferFromAssignmentContext(
                id,
                expectedParameterType: inferredImplicitItType,
                ctx: ctx,
                sema: sema,
                locals: locals
            )
        } else {
            nil
        }

        let effectiveParams: [InternedString] = if params.isEmpty {
            if let expectedFunctionType, expectedFunctionType.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
                    samFT.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            else if inferredImplicitItType != nil {
                [ctx.interner.intern("it")]
            } else {
                params
            }
        } else {
            params
        }

        // Parameter types the expected type actually declares, as opposed to the
        // `Any` fallback below; only these can contradict an explicit annotation.
        let declaredParameterTypes: [TypeID]? = {
            if let expectedFunctionType, expectedFunctionType.params.count == effectiveParams.count {
                return expectedFunctionType.params
            }
            if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
               samFT.params.count == effectiveParams.count
            {
                return samFT.params
            }
            return nil
        }()
        // Callable references satisfy the reflective `KFunction<R>` view of a
        // generic receiver, but that view erases the callable's parameter
        // types. When the HOF receiver supplies the concrete function type,
        // preserve it for implicit `it` so calls such as
        // `Boolean::not.let { it(true) }` remain invokable.
        let inferredCallableItType: TypeID? = {
            guard effectiveParams == [ctx.interner.intern("it")],
                  let inferredImplicitItType,
                  case .functionType = sema.types.kind(of: inferredImplicitItType),
                  let declaredParameterType = declaredParameterTypes?.first,
                  sema.types.nominalFunctionType(for: declaredParameterType) == nil,
                  sema.types.isSubtype(inferredImplicitItType, declaredParameterType)
            else {
                return nil
            }
            return inferredImplicitItType
        }()
        let inferredAssignmentParameterTypes: [TypeID]? = if effectiveParams == [ctx.interner.intern("it")],
                                                              let inferredAssignmentItType
        {
            [inferredAssignmentItType]
        } else {
            nil
        }
        let expectedParameterTypes: [TypeID] = if let inferredCallableItType {
            [inferredCallableItType]
        } else if let inferredAssignmentParameterTypes {
            inferredAssignmentParameterTypes
        } else if let declaredParameterTypes {
            declaredParameterTypes
        } else if effectiveParams.count == 1 && effectiveParams.contains(ctx.interner.intern("it")) {
            inferredImplicitItType.map { [$0] }
                ?? Array(repeating: sema.types.anyType, count: effectiveParams.count)
        } else {
            Array(repeating: sema.types.anyType, count: effectiveParams.count)
        }
        // Explicit `{ a: Int -> ... }` annotations win over the expected type's
        // parameter types, which may be unsubstituted type parameters when the
        // expected type is a raw functional interface (BUG-046). An annotation
        // that contradicts a concrete expected parameter type is an error.
        let annotatedParameterTypes = resolveLambdaParamAnnotations(id, ctx: ctx, paramCount: effectiveParams.count)
        let expectedTypeIsSourceDeclared = sema.bindings.hasSourceDeclaredExpectedType(id)
        let parameterTypes: [TypeID] = effectiveParams.indices.map { offset in
            let fallback = offset < expectedParameterTypes.count ? expectedParameterTypes[offset] : sema.types.anyType
            guard let annotated = annotatedParameterTypes?[offset] else {
                return fallback
            }
            guard let declared = declaredParameterTypes?[offset] else {
                return annotated
            }
            if lambdaAnnotationIsCompatible(
                annotated: annotated,
                declared: declared,
                expectedTypeIsSourceDeclared: expectedTypeIsSourceDeclared,
                sema: sema
            ) {
                return annotated
            }
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0025",
                "Lambda parameter '\(ctx.interner.resolve(effectiveParams[offset]))' is declared as "
                    + "'\(describe(annotated, ctx: ctx))' but '\(describe(declared, ctx: ctx))' is expected.",
                range: ast.arena.exprRange(id)
            )
            return declared
        }
        // Lowered receiver lambdas place the receiver in parameter slot 0
        // (`syntheticLambdaParamSymbol(exprID, 0)`), so a value parameter's
        // synthetic symbol index is shifted by one when the expected type
        // carries an extension receiver.
        let loweredReceiverSlot = expectedFunctionType?.receiver != nil
            && sema.bindings.coroutineScopeLambdaReceiverTypes[id] == nil ? 1 : 0
        for (offset, param) in effectiveParams.enumerated() {
            let syntheticSymbol = SymbolID(rawValue: Int32(clamping: Int64(-1_000_000) - Int64(id.rawValue) * 256 - Int64(offset + loweredReceiverSlot)))
            let parameterType = parameterTypes[offset]
            // Preserve the declaration type for checks that must ignore smart casts,
            // just as for local function parameters.
            sema.symbols.setPropertyType(parameterType, for: syntheticSymbol)
            lambdaLocals[param] = (
                type: parameterType,
                symbol: syntheticSymbol,
                isMutable: false,
                isInitialized: true
            )
        }

        // A type variable bounded by final Unit can only resolve to Unit. Treat
        // its lambda as Unit-returning so the body is coerced before inference
        // chooses the body's natural type for that variable.
        let expectedReturnHasUnitUpperBound: Bool = {
            guard !expectedTypeIsHintOnly,
                  let expectedReturnType = expectedFunctionType?.returnType,
                  case let .typeParam(typeParameter) = sema.types.kind(of: expectedReturnType)
            else {
                return false
            }
            return sema.symbols.typeParameterUpperBounds(for: typeParameter.symbol)
                .contains(sema.types.unitType)
        }()
        let lambdaUsesUnitCoercion = expectedFunctionType?.returnType == sema.types.unitType
            || expectedReturnHasUnitUpperBound

        var bodyCtx: TypeInferenceContext = if let label {
            // `foo@{ ... }()` binds `foo` to the postfix expression rather
            // than the lambda literal, so the label does not denote a function
            // as a `return@foo` target (kotlinc rejects with "target label
            // does not denote a function").
            ctx.withLambdaLabel(label, denotesFunction: !ast.arena.isNonFunctionLambdaLabel(id))
        } else {
            ctx
        }
        bodyCtx = bodyCtx.enteringLambdaBody(id)
        bodyCtx.isUnitCoercionContext = lambdaUsesUnitCoercion
        // The lambda body runs on its own `lambdaLocals` scope, so local
        // narrowing inside it cannot leak to the enclosing locals — the
        // conditional-evaluation suppression does not apply within the body.
        bodyCtx.isConditionallyEvaluated = false
        if let receiverType = ctx.implicitReceiverType,
           let receiverSymbol = locals[ctx.interner.intern("this")]?.symbol,
           bodyCtx.implicitReceiverStack.last?.symbol != receiverSymbol
        {
            bodyCtx.implicitReceiverStack.append((receiverType, receiverSymbol))
        }
        if let receiverType = expectedFunctionType?.receiver
            ?? sema.bindings.coroutineScopeLambdaReceiverTypes[id]
        {
            bodyCtx = bodyCtx.with(implicitReceiverType: receiverType)
            // The lambda's own receiver is its `this`: shadow the enclosing
            // function's receiver in `locals` (which `inferThisRefExpr` reads
            // first) and address it through a per-lambda symbol so that
            // `this@callee` from a nested lambda can capture it.
            let receiverSymbol = SyntheticSymbolScheme.lambdaReceiverSymbol(for: id)
            bodyCtx.implicitReceiverStack.append((receiverType, receiverSymbol))
            lambdaLocals[ctx.interner.intern("this")] = (
                type: receiverType,
                symbol: receiverSymbol,
                isMutable: false,
                isInitialized: true
            )
            if let label {
                bodyCtx = bodyCtx.withOuterReceiver(label: label, type: receiverType, symbol: receiverSymbol)
            }
        }
        if let expectedFunctionType, !expectedFunctionType.contextReceivers.isEmpty {
            bodyCtx = bodyCtx.with(
                contextReceiverTypes: ctx.contextReceiverTypes + expectedFunctionType.contextReceivers
            )
        }
        let expectedReturnHasUnresolvedOutputTypeParameter: Bool = {
            guard let expectedFunctionType else {
                return false
            }
            let returnTypeParameters = typeParameterSymbols(in: expectedFunctionType.returnType, sema: sema)
            guard !returnTypeParameters.isEmpty else {
                return false
            }
            var inputTypeParameters = Set<SymbolID>()
            for receiver in expectedFunctionType.contextReceivers {
                inputTypeParameters.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            if let receiver = expectedFunctionType.receiver {
                inputTypeParameters.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            for parameter in expectedFunctionType.params {
                inputTypeParameters.formUnion(typeParameterSymbols(in: parameter, sema: sema))
            }
            let lexicalParameters = driver.helpers.lexicalTypeParameterSymbols(in: ctx)
            return !returnTypeParameters.subtracting(inputTypeParameters).subtracting(lexicalParameters).isEmpty
        }()
        // Kotlin discards a Unit-expected lambda body's value rather than requiring
        // it to actually type as Unit (e.g. `repeat(3) { i -> someIntCall(i) }`).
        // Passing Unit down as the body's expectedType would incorrectly propagate
        // into the body's own call resolution -- e.g. rejecting `addOne(i): Int` as
        // "no viable overload" because Int isn't a subtype of the pushed-down Unit.
        // Only push the expected return type down when it isn't Unit. An unresolved
        // type parameter (the `T` of `fun <T> f(action: () -> T): T`) is treated the
        // same way: it cannot constrain the body's own resolution, and pushing it
        // down makes a Unit-valued body (e.g. `{ println() }`) fail to type-check.
        // The same applies when the unresolved output parameter is nested inside
        // a contextual return type such as `List<R>`. It is free at this call site
        // when it does not occur in the lambda's receiver or input parameters;
        // the concrete body result must infer it instead of being checked against
        // an outer placeholder.
        // Leaving it out lets the body infer its natural type so the caller can solve
        // the type variable from it.
        let bodyExpectedType: TypeID? = {
            guard !expectedTypeIsHintOnly else {
                return nil
            }
            guard let expectedReturnType = expectedFunctionType?.returnType,
                  !lambdaUsesUnitCoercion else {
                return nil
            }
            if case let .typeParam(parameter) = sema.types.kind(of: expectedReturnType),
               !driver.helpers.lexicalTypeParameterSymbols(in: ctx).contains(parameter.symbol) {
                return nil
            }
            if expectedReturnHasUnresolvedOutputTypeParameter {
                return nil
            }
            return expectedReturnType
        }()
        let expectedLambdaReturnType: TypeID? = if expectedTypeIsHintOnly {
            nil
        } else if lambdaUsesUnitCoercion {
            sema.types.unitType
        } else {
            bodyExpectedType
        }
        let returnScope = LambdaReturnInferenceScope(
            exprID: id,
            label: label,
            expectedReturnType: expectedLambdaReturnType
        )
        bodyCtx.lambdaReturnScopes.append(returnScope)
        // A bare `if` without `else` occupying the lambda body's tail is a
        // statement in Kotlin: the lambda simply returns Unit and any mismatch
        // is reported as a return-type mismatch on the lambda itself, not as
        // INVALID_IF_AS_EXPRESSION. Statement context here only reaches that
        // trailing `if` — block statements already infer as statements, and an
        // else-less `if` forces its own branches into statement context anyway.
        let lambdaTailIsElselessIf: Bool = {
            let tailExpr: ExprID = if case let .blockExpr(_, trailingExpr, _) = ast.arena.expr(body),
                                      let trailingExpr {
                trailingExpr
            } else {
                body
            }
            guard case let .ifExpr(_, _, elseExpr, _) = ast.arena.expr(tailExpr) else { return false }
            return elseExpr == nil
        }()
        // A non-exhaustive `when` at the end of a lambda is a statement in
        // Kotlin. Parentheses make it an expression, so leave that form on the
        // normal expression path and let exhaustiveness checking reject it.
        let lambdaTailIsWhenWithoutElse: Bool = {
            let tailExpr: ExprID = if case let .blockExpr(_, trailingExpr, _) = ast.arena.expr(body),
                                      let trailingExpr {
                trailingExpr
            } else {
                body
            }
            guard !ast.arena.isParenthesized(tailExpr),
                  case let .whenExpr(_, _, elseExpr, _) = ast.arena.expr(tailExpr)
            else {
                return false
            }
            return elseExpr == nil
        }()
        let fallthroughType = driver.inferExpr(
            body,
            ctx: bodyCtx,
            locals: &lambdaLocals,
            expectedType: bodyExpectedType,
            isStatementContext: lambdaUsesUnitCoercion || lambdaTailIsElselessIf || lambdaTailIsWhenWithoutElse
        )
        if expectedLambdaReturnType == sema.types.unitType,
           sema.types.makeNonNullable(fallthroughType) == sema.types.unitType
        {
            sema.bindings.markUnitReturnCoercion(body)
        }
        let inferredBodyType = sema.types.lub(
            [fallthroughType] + returnScope.returnValueTypes.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
        )
        // Range expressions use a scalar Sema type plus a marker, while Kotlin
        // lambdas expose their nominal range type to surrounding calls.
        let sourceLevelInferredBodyType = driver.callChecker.sourceLevelRangeArgumentType(
            body, inferredType: inferredBodyType, ctx: bodyCtx
        )
        // Record which outer-scope locals this lambda body unconditionally
        // initializes. `locals` itself is never mutated here -- the
        // lambda isn't known to run at this point -- but a caller whose contract
        // guarantees EXACTLY_ONCE/AT_LEAST_ONCE invocation (applyContractEffects)
        // can later fold this back into its own definite-assignment state.
        var callsInPlaceInitializedSymbols: [SymbolID] = []
        for (name, outerLocal) in locals where !outerLocal.isInitialized {
            if let lambdaLocal = lambdaLocals[name],
               lambdaLocal.symbol == outerLocal.symbol,
               lambdaLocal.isInitialized
            {
                callsInPlaceInitializedSymbols.append(outerLocal.symbol)
            }
        }
        if !callsInPlaceInitializedSymbols.isEmpty {
            sema.bindings.bindContractCallsInPlaceInitializedSymbols(id, symbols: callsInPlaceInitializedSymbols)
        }
        let captures = driver.captureAnalyzer.collectCapturedOuterSymbols(
            in: body,
            ast: ast,
            sema: sema,
            outerSymbols: outerSymbols
        )
        sema.bindings.bindCaptureSymbols(id, symbols: captures)

        // SAM conversion: bind the lambda to the interface type, but also
        // store the underlying function type so KIR lowering can generate
        // the correct callable.
        if samConversion, let expectedType, let expectedFunctionType {
            // Unit-returning SAM lambdas discard the body's value, just like
            // ordinary Unit-returning lambdas (e.g. a Boolean-valued CAS call).
            let expectedReturnIsTypeParam: Bool = {
                guard case .typeParam = sema.types.kind(of: expectedFunctionType.returnType) else {
                    return false
                }
                return true
            }()
            let deferReturnConstraint = expectedTypeIsHintOnly
                || expectedFunctionType.returnType == sema.types.unitType
                || expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
            if !deferReturnConstraint {
                driver.emitSubtypeConstraint(
                    left: sourceLevelInferredBodyType,
                    right: expectedFunctionType.returnType,
                    range: ast.arena.exprRange(body),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.sema.diagnostics
                )
            }
            sema.bindings.markSamConversion(id)
            let inferredReturnType = expectedTypeIsHintOnly
                || expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
                    ? inferOptimizedReturnType(
                        inferredBodyType: sourceLevelInferredBodyType,
                        expectedReturnType: lambdaUsesUnitCoercion
                            ? sema.types.unitType
                            : expectedFunctionType.returnType,
                        sema: sema
                    )
                    : expectedFunctionType.returnType
            let underlyingFunctionType = FunctionType(
                contextReceivers: expectedFunctionType.contextReceivers,
                receiver: expectedFunctionType.receiver,
                params: parameterTypes,
                returnType: inferredReturnType,
                isSuspend: expectedFunctionType.isSuspend,
                isCallableReference: expectedFunctionType.isCallableReference,
                nullability: expectedFunctionType.nullability,
                throws: expectedFunctionType.throws
            )
            let underlyingFuncType = sema.types.make(.functionType(underlyingFunctionType))
            sema.bindings.bindSamUnderlyingFunctionType(id, type: underlyingFuncType)
            sema.bindings.bindExprType(id, type: expectedType)
            return expectedType
        }

        if let expectedFunctionType {
            let inferenceReturnType = lambdaUsesUnitCoercion
                ? sema.types.unitType
                : expectedFunctionType.returnType
            if !expectedTypeIsHintOnly,
               let session = ctx.builderInference,
               inferenceReturnType != sema.types.unitType,
               session.mentionsVariable(inferenceReturnType, types: sema.types)
                || session.mentionsVariable(sourceLevelInferredBodyType, types: sema.types)
            {
                session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: sourceLevelInferredBodyType,
                    supertype: inferenceReturnType,
                    typeVarBySymbol: session.typeVarBySymbol,
                    typeSystem: sema.types,
                    blameRange: ast.arena.exprRange(body)
                ))
                let functionType = sema.types.make(.functionType(expectedFunctionType))
                sema.bindings.bindExprType(id, type: functionType)
                return functionType
            }
            let optimizedReturnType = expectedTypeIsHintOnly
                ? sourceLevelInferredBodyType
                : inferOptimizedReturnType(
                    inferredBodyType: sourceLevelInferredBodyType,
                    expectedReturnType: inferenceReturnType,
                    sema: sema
                )

            // Skip the local subtype constraint when the expected return is Unit
            // (Kotlin allows any body type) or when it is a generic type variable.
            // For Unit there is nothing to constrain. For a type variable the
            // local solver cannot bind it; the concrete inferred function type
            // returned below lets the call resolver infer it instead.
            let expectedReturnIsTypeParam: Bool = {
                guard case .typeParam = sema.types.kind(of: expectedFunctionType.returnType) else {
                    return false
                }
                return true
            }()
            // A bounded type parameter (`fun <R : Any> f(g: () -> R)`) cannot be
            // constrained locally either — `Int <: R` is never satisfiable while
            // `R` is still a placeholder, and the upper bound is verified by the
            // overload resolver once `R` is inferred (`checkTypeParameterBounds`).
            let shouldSkipSubtypeConstraint =
                expectedTypeIsHintOnly
                || lambdaUsesUnitCoercion
                || expectedFunctionType.returnType == sema.types.unitType
                || expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
            if !shouldSkipSubtypeConstraint {
                driver.emitSubtypeConstraint(
                    left: optimizedReturnType,
                    right: expectedFunctionType.returnType,
                    range: ast.arena.exprRange(body),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.sema.diagnostics
                )
            }
            // When the expected return type is an unresolved type parameter,
            // returning `expectedType` verbatim leaks that type variable back
            // out as the lambda's own type. The overload resolver then
            // decomposes it against the same signature's parameter type and
            // produces a self-referential `T <: T` bound instead of a real
            // constraint derived from the body's actual type (e.g. `lazy { 1 }`
            // or `box.run2 { myValue }` fails to infer `R`). Substitute the
            // concrete, inferred return type in those cases so the caller can
            // solve the type parameter from it.
            // Synthesized `Any`/`Any?` expected returns are placeholders too:
            // `inferCallExpr` synthesizes `() -> Any` as the contextual type
            // when a lambda literal is invoked directly (`{ ... }()`) with no
            // caller-supplied expected type. Adopting it verbatim would type
            // the call result as `Any` (e.g. `true && { 1; true }()` then
            // fails `&&`'s Boolean constraint), so the concrete body return
            // must flow through here too. Coroutine builders likewise declare
            // their `block` result as `Any?` and recover the real `T` from the
            // body; leaving the placeholder bound to `Any?` costs overload
            // specificity against the synthetic stubs. A real parameter type
            // like `(T, T) -> Any` (the erased-R placeholder used by the
            // synthetic collection-HOF paths) must keep the expected `Any`
            // return, though: the emitted thunk's declared return drives
            // boxing at the erased ABI boundary, and a concrete
            // `Boolean`/`Char` would be stored raw into `List<R>` and print
            // as `1`/`97`. Source-declared Any returns also drive ABI boxing:
            // `check(block: () -> Any) { text.toULong() }` must return an
            // unsigned box rather than a raw word (KUU-1982).
            let expectedReturnIsErasedNonHOFPlaceholder =
                (expectedFunctionType.returnType == sema.types.anyType
                    || expectedFunctionType.returnType == sema.types.nullableAnyType)
                && !sema.bindings.isCollectionHOFLambdaExpr(id)
                && !expectedTypeIsSourceDeclared
            // A Unit callback still supplies input constraints. Returning the
            // contextual `(T) -> Unit` would erase an explicit String input and
            // leave the constructor's T constrained only by itself. Preserve
            // that input so the call resolver can collect `T <: String`, while
            // keeping the body's value coerced to Unit.
            let hasAnnotatedUnresolvedUnitInput =
                lambdaUsesUnitCoercion
                && annotatedParameterTypes != nil
                && zip(parameterTypes, expectedFunctionType.params).contains { actual, expected in
                    actual != expected && typeMentionsTypeParameter(expected, sema: sema)
                }
            let hasInferredUnresolvedUnitInput =
                lambdaUsesUnitCoercion
                && inferredAssignmentItType != nil
                && zip(parameterTypes, expectedFunctionType.params).contains { actual, expected in
                    actual != expected && typeMentionsTypeParameter(expected, sema: sema)
                }
            let shouldReturnResolvedFunctionType = expectedTypeIsHintOnly
                || expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
                || expectedReturnIsErasedNonHOFPlaceholder
                || hasAnnotatedUnresolvedUnitInput
                || hasInferredUnresolvedUnitInput
                || sema.bindings.isDirectlyInvokedLambdaExpr(id)
            let resultType: TypeID = if shouldReturnResolvedFunctionType {
                sema.types.make(.functionType(FunctionType(
                    contextReceivers: expectedFunctionType.contextReceivers,
                    receiver: expectedFunctionType.receiver,
                    params: parameterTypes,
                    returnType: optimizedReturnType,
                    isSuspend: expectedFunctionType.isSuspend,
                    nullability: expectedFunctionType.nullability,
                    throws: expectedFunctionType.throws
                )))
            } else {
                sema.types.make(.functionType(expectedFunctionType))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        let inferredFunctionType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: sourceLevelInferredBodyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        sema.bindings.bindExprType(id, type: inferredFunctionType)
        return inferredFunctionType
    }

    private enum ParentLambdaCallContext {
        case topLevel(calleeName: InternedString, argIndex: Int, typeArgs: [TypeRefID])
        case member(receiverType: TypeID?, calleeName: InternedString, argIndex: Int, typeArgs: [TypeRefID])
    }

    private func findParentCallContext(for lambdaId: ExprID, ctx: TypeInferenceContext, sema _: SemaModule) -> ParentLambdaCallContext? {
        let ast = ctx.ast
        for expr in ast.arena.exprs {
            switch expr {
            case let .call(callee, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }),
                      let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    continue
                }
                return .topLevel(calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            case let .memberCall(receiver, calleeName, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            case let .safeMemberCall(receiver, calleeName, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            default:
                continue
            }
        }
        return nil
    }

    private func inferItParameterType(
        ctx: TypeInferenceContext,
        id: ExprID,
        sema: SemaModule,
        locals: LocalBindings
    ) -> TypeID? {
        if let parentCall = findParentCallContext(for: id, ctx: ctx, sema: sema) {
            return inferTypeFromHOFContext(parentCall, ctx: ctx, sema: sema, locals: locals)
        }
        return nil
    }

    private func inferTypeFromHOFContext(
        _ callContext: ParentLambdaCallContext,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        locals: LocalBindings
    ) -> TypeID? {
        var candidateSymbols: [SymbolID]
        let argIndex: Int
        let explicitTypeArgRefs: [TypeRefID]
        var memberReceiverType: TypeID? = nil

        switch callContext {
        case let .topLevel(calleeName, index, typeArgs):
            argIndex = index
            explicitTypeArgRefs = typeArgs
            candidateSymbols = ctx.filterByVisibility(
                ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .function || symbol.kind == .constructor
                }
            ).visible

        case let .member(receiverType, calleeName, index, typeArgs):
            guard let receiverType else {
                return nil
            }
            argIndex = index
            explicitTypeArgRefs = typeArgs
            memberReceiverType = receiverType
            candidateSymbols = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            )
            if !candidateSymbols.contains(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      argIndex < signature.parameterTypes.count
                else {
                    return false
                }
                let parameterType = signature.parameterTypes[argIndex]
                if case let .functionType(functionType) = sema.types.kind(of: parameterType) {
                    return functionType.params.count == 1
                }
                return driver.helpers.samFunctionType(for: parameterType, sema: sema)?.params.count == 1
            }) {
                let extensionCandidates = driver.callChecker.collectExtensionCallCandidates(
                    named: calleeName,
                    memberLookupType: receiverType,
                    isSuperCall: false,
                    supertypeSymbols: [],
                    ctx: ctx,
                    locals: locals,
                    sema: sema,
                    interner: ctx.interner
                )
                var seen = Set(candidateSymbols)
                candidateSymbols.append(contentsOf: extensionCandidates.filter { seen.insert($0).inserted })
            }
        }

        let explicitTypeArgs = explicitTypeArgRefs.map { typeArgRef in
            guard !driver.helpers.isExplicitTypeInferencePlaceholder(
                typeArgRef, ast: ctx.ast, interner: ctx.interner
            ) else {
                return TypeID.invalid
            }
            return driver.helpers.resolveTypeRef(
                typeArgRef,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope,
                inferenceContext: ctx
            )
        }

        var inferredParameterTypes: [TypeID] = []
        for candidate in candidateSymbols {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  argIndex < signature.parameterTypes.count
            else {
                continue
            }
            var parameterType = signature.parameterTypes[argIndex]
            parameterType = driver.callChecker.applyReceiverClassTypeArgs(
                to: parameterType,
                signature: signature,
                candidate: candidate,
                receiverType: memberReceiverType,
                sema: sema
            )
            parameterType = driver.callChecker.applyFunctionReceiverTypeArgs(
                to: parameterType,
                signature: signature,
                receiverType: memberReceiverType,
                sema: sema
            )
            if case let .functionType(functionType) = sema.types.kind(of: parameterType),
               functionType.params.count == 1
            {
                inferredParameterTypes.append(substituteExplicitTypeArgument(
                    functionType.params[0],
                    signature: signature,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                ))
                continue
            }
            if let samFunctionType = driver.helpers.samFunctionType(for: parameterType, sema: sema),
               samFunctionType.params.count == 1
            {
                inferredParameterTypes.append(substituteExplicitTypeArgument(
                    samFunctionType.params[0],
                    signature: signature,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                ))
            }
        }

        guard let firstType = inferredParameterTypes.first else {
            return nil
        }
        let allSame = inferredParameterTypes.dropFirst().allSatisfy { $0 == firstType }
        return allSame ? firstType : nil
    }

    /// Replaces a candidate's own type parameter with the explicit type argument
    /// written at the call site. Overloads of the same generic function declare
    /// distinct type parameter symbols, so without this substitution the candidate
    /// parameter types never agree and the implicit `it` type stays unresolved for
    /// every argument of a call such as `compareBy<Row>({ it.a }, { it.b })`.
    private func substituteExplicitTypeArgument(
        _ type: TypeID,
        signature: FunctionSignature,
        explicitTypeArgs: [TypeID],
        sema: SemaModule
    ) -> TypeID {
        guard !explicitTypeArgs.isEmpty,
              case let .typeParam(typeParam) = sema.types.kind(of: type)
        else {
            return type
        }
        let ownTypeParameters = signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
        guard let offset = ownTypeParameters.firstIndex(of: typeParam.symbol) else {
            return type
        }
        let argOffset = offset - ownTypeParameters.startIndex
        guard argOffset < explicitTypeArgs.count else {
            return type
        }
        let explicitType = explicitTypeArgs[argOffset]
        guard explicitType != TypeID.invalid, explicitType != sema.types.errorType else {
            return type
        }
        return typeParam.nullability == .nullable
            ? sema.types.makeNullable(explicitType)
            : explicitType
    }

    private func inferFromAssignmentContext(
        _ lambdaID: ExprID,
        expectedParameterType: TypeID,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        locals: LocalBindings
    ) -> TypeID? {
        guard typeMentionsTypeParameter(expectedParameterType, sema: sema),
              case let .lambdaLiteral(_, body, _, _) = ctx.ast.arena.expr(lambdaID)
        else {
            return nil
        }

        let implicitIt = ctx.interner.intern("it")
        var targetTypes: [TypeID] = []
        var visited: Set<ExprID> = []
        func collectAssignmentTargets(in expressionID: ExprID) {
            guard visited.insert(expressionID).inserted,
                  let expression = ctx.ast.arena.expr(expressionID)
            else {
                return
            }
            if case let .localAssign(name, value, _) = expression,
               case let .nameRef(valueName, _) = ctx.ast.arena.expr(value),
               valueName == implicitIt,
               let local = locals[name]
            {
                let targetType = sema.symbols.propertyType(for: local.symbol) ?? local.type
                if targetType != sema.types.errorType {
                    targetTypes.append(targetType)
                }
            }
            for child in assignmentContextChildren(of: expression) {
                collectAssignmentTargets(in: child)
            }
        }
        collectAssignmentTargets(in: body)
        guard var targetType = targetTypes.first else {
            return nil
        }
        for candidateType in targetTypes.dropFirst() {
            if sema.types.isSubtype(candidateType, targetType) {
                targetType = candidateType
            } else if !sema.types.isSubtype(targetType, candidateType) {
                return nil
            }
        }

        var substitutions: [SymbolID: TypeID] = [:]
        guard inferAssignmentTypeParameters(
            in: expectedParameterType,
            from: targetType,
            substitutions: &substitutions,
            sema: sema
        ), !substitutions.isEmpty else {
            return nil
        }
        let inferredType = substitutingAssignmentTypeParameters(
            in: expectedParameterType,
            substitutions: substitutions,
            sema: sema
        )
        guard inferredType != expectedParameterType,
              sema.types.isSubtype(inferredType, targetType)
        else {
            return nil
        }
        return inferredType
    }

    private func inferAssignmentTypeParameters(
        in template: TypeID,
        from target: TypeID,
        substitutions: inout [SymbolID: TypeID],
        sema: SemaModule
    ) -> Bool {
        switch sema.types.kind(of: template) {
        case let .typeParam(parameter):
            guard parameter.capture == nil, target != sema.types.errorType else {
                return false
            }
            if let previous = substitutions[parameter.symbol] {
                return previous == target
            }
            substitutions[parameter.symbol] = target
            return true

        case let .classType(templateClass):
            guard case let .classType(targetClass) = sema.types.kind(of: sema.types.makeNonNullable(target)),
                  templateClass.classSymbol == targetClass.classSymbol,
                  templateClass.args.count == targetClass.args.count
            else {
                return false
            }
            for (templateArgument, targetArgument) in zip(templateClass.args, targetClass.args) {
                func projectedType(_ argument: TypeArg) -> TypeID? {
                    switch argument {
                    case let .invariant(type), let .out(type), let .in(type): type
                    case .star: nil
                    }
                }
                guard let templateType = projectedType(templateArgument),
                      let targetType = projectedType(targetArgument)
                else {
                    return false
                }
                guard inferAssignmentTypeParameters(
                    in: templateType,
                    from: targetType,
                    substitutions: &substitutions,
                    sema: sema
                ) else {
                    return false
                }
            }
            return true

        case let .functionType(templateFunction):
            guard case let .functionType(targetFunction) = sema.types.kind(of: target),
                  templateFunction.params.count == targetFunction.params.count,
                  templateFunction.isSuspend == targetFunction.isSuspend
            else {
                return false
            }
            for (templateParameter, targetParameter) in zip(templateFunction.params, targetFunction.params) {
                guard inferAssignmentTypeParameters(
                    in: templateParameter,
                    from: targetParameter,
                    substitutions: &substitutions,
                    sema: sema
                ) else {
                    return false
                }
            }
            return inferAssignmentTypeParameters(
                in: templateFunction.returnType,
                from: targetFunction.returnType,
                substitutions: &substitutions,
                sema: sema
            )

        case let .kClassType(templateKClass):
            guard case let .kClassType(targetKClass) = sema.types.kind(of: target) else {
                return false
            }
            return inferAssignmentTypeParameters(
                in: templateKClass.argument,
                from: targetKClass.argument,
                substitutions: &substitutions,
                sema: sema
            )

        default:
            return !typeMentionsTypeParameter(template, sema: sema)
                && sema.types.isSubtype(target, template)
        }
    }

    private func substitutingAssignmentTypeParameters(
        in type: TypeID,
        substitutions: [SymbolID: TypeID],
        sema: SemaModule
    ) -> TypeID {
        if case let .typeParam(parameter) = sema.types.kind(of: type),
           parameter.capture == nil,
           let replacement = substitutions[parameter.symbol]
        {
            switch parameter.nullability {
            case .nonNull:
                return replacement
            case .nullable:
                return sema.types.makeNullable(replacement)
            case .platformType:
                return sema.types.withNullability(.platformType, for: replacement)
            }
        }
        return sema.types.make(sema.types.kind(of: type).mapTypes { nestedType in
            substitutingAssignmentTypeParameters(in: nestedType, substitutions: substitutions, sema: sema)
        })
    }

    private func assignmentContextChildren(of expression: Expr) -> [ExprID] {
        switch expression {
        case .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .nullLiteral,
             .boolLiteral, .stringLiteral, .nameRef, .breakExpr, .continueExpr,
             .superRef, .thisRef, .lambdaLiteral, .localFunDecl,
             .localNominalDecl, .objectLiteral:
            []
        case let .stringTemplate(parts, _):
            parts.compactMap { part in
                if case let .expression(child) = part { return child }
                return nil
            }
        case let .forExpr(_, iterable, body, _, _),
             let .forDestructuringExpr(_, iterable, body, _, _):
            [iterable, body]
        case let .whileExpr(condition, body, _, _):
            [condition, body]
        case let .doWhileExpr(body, condition, _, _):
            [body, condition]
        case let .localDecl(_, _, _, initializer, _, _, _):
            initializer.map { [$0] } ?? []
        case let .localAssign(_, value, _), let .compoundAssign(_, _, value, _),
             let .throwExpr(value, _):
            [value]
        case let .memberAssign(receiver, _, value, _),
             let .safeMemberAssign(receiver, _, value, _),
             let .memberCompoundAssign(_, receiver, _, value, _):
            [receiver, value]
        case let .indexedAssign(receiver, indices, value, _),
             let .indexedCompoundAssign(_, receiver, indices, value, _):
            [receiver] + indices + [value]
        case let .call(callee, _, args, _):
            [callee] + args.map(\.expr)
        case let .memberCall(receiver, _, _, args, _),
             let .safeMemberCall(receiver, _, _, args, _):
            [receiver] + args.map(\.expr)
        case let .indexedAccess(receiver, indices, _):
            [receiver] + indices
        case let .binary(_, lhs, rhs, _), let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            [lhs, rhs]
        case let .whenExpr(subject, branches, elseExpr, _):
            (subject.map { [$0] } ?? [])
                + branches.flatMap { $0.conditions + ($0.guard_.map { [$0] } ?? []) + [$0.body] }
                + (elseExpr.map { [$0] } ?? [])
        case let .returnExpr(value, _, _):
            value.map { [$0] } ?? []
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            [condition, thenExpr] + (elseExpr.map { [$0] } ?? [])
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            [body] + catchClauses.map(\.body) + (finallyExpr.map { [$0] } ?? [])
        case let .unaryExpr(_, operand, _), let .isCheck(operand, _, _, _),
             let .asCast(operand, _, _, _), let .nullAssert(operand, _):
            [operand]
        case let .callableRef(receiver, _, _):
            receiver.map { [$0] } ?? []
        case let .blockExpr(statements, trailingExpr, _):
            statements + (trailingExpr.map { [$0] } ?? [])
        case let .destructuringDecl(_, _, initializer, _):
            [initializer]
        }
    }

    private func inferOptimizedReturnType(
        inferredBodyType: TypeID,
        expectedReturnType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        if expectedReturnType == sema.types.unitType {
            return sema.types.unitType
        }

        if sema.types.isSubtype(inferredBodyType, expectedReturnType) {
            return inferredBodyType
        }

        return inferredBodyType
    }
}
