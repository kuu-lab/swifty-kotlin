
extension ExprTypeChecker {
    private func describe(_ type: TypeID, ctx: TypeInferenceContext) -> String {
        ctx.sema.types.displayName(of: type, symbols: ctx.sema.symbols, interner: ctx.interner)
    }

    /// Whether an explicit lambda parameter annotation agrees with the parameter
    /// type the expected type declares. Type parameters the expected type leaves
    /// unsubstituted carry no information, so annotations always win there.
    /// Otherwise only widening is allowed (function types are contravariant in
    /// their parameters): `(String) -> Int = { s: Any -> ... }` is fine, while
    /// `(Any) -> Int = { s: String -> ... }` is a mismatch.
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

    /// Resolves the explicit parameter type annotations recorded for a lambda
    /// literal (`{ a: Int, b: String -> ... }`). Returns nil when the lambda has
    /// no annotations or the recorded arity does not match the parameter list.
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
        // SAM conversion: when the expected type is a functional interface,
        // extract the SAM method's function type so the lambda's parameters
        // and return type can be inferred from it.
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

        var lambdaLocals = locals
        // Outer receiver `this` symbols are reachable inside the lambda even
        // though the enclosing member's `this` shadows them in `locals` — the
        // enclosing context (e.g. an object literal) captured them, so the
        // lambda can capture them through the same chain.
        let outerSymbols = Set(locals.values.map(\.symbol) + ctx.implicitReceiverStack.map(\.symbol))
            .union(ctx.outerReceiverTypes.compactMap(\.symbol))
        let inferredImplicitItType = params.isEmpty
            ? inferItParameterType(ctx: ctx, id: id, sema: sema)
            : nil

        // Implicit `it` parameter for no-arrow lambdas with single expected param.
        // Enhanced to support complex type inference contexts and generic types.
        let effectiveParams: [InternedString] = if params.isEmpty {
            // Check for expected function type first
            if let expectedFunctionType, expectedFunctionType.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            // Check for SAM conversion with single parameter method
            else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
                    samFT.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            // Check for common HOF patterns (map, filter, etc.) through context
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
        let expectedParameterTypes: [TypeID] = if let declaredParameterTypes {
            declaredParameterTypes
        } else if effectiveParams.count == 1 && effectiveParams.contains(ctx.interner.intern("it")) {
            // For implicit `it` parameter, try to infer type from context
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
            ctx.semaCtx.diagnostics.error(
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
        if let receiverType = ctx.implicitReceiverType,
           let receiverSymbol = locals[ctx.interner.intern("this")]?.symbol,
           bodyCtx.implicitReceiverStack.last?.symbol != receiverSymbol
        {
            bodyCtx.implicitReceiverStack.append((receiverType, receiverSymbol))
        }
        // When the expected function type has a receiver (e.g. StringBuilder.() -> Unit),
        // set the implicit receiver so that unqualified member calls resolve correctly.
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
            return !returnTypeParameters.subtracting(inputTypeParameters).isEmpty
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
                  expectedReturnType != sema.types.unitType else {
                return nil
            }
            if case .typeParam = sema.types.kind(of: expectedReturnType) {
                return nil
            }
            if expectedReturnHasUnresolvedOutputTypeParameter {
                return nil
            }
            return expectedReturnType
        }()
        let expectedLambdaReturnType: TypeID? = if expectedTypeIsHintOnly {
            nil
        } else if expectedFunctionType?.returnType == sema.types.unitType {
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
        let fallthroughType = driver.inferExpr(
            body,
            ctx: bodyCtx,
            locals: &lambdaLocals,
            expectedType: bodyExpectedType,
            isStatementContext: expectedFunctionType?.returnType == sema.types.unitType
        )
        let inferredBodyType = sema.types.lub(
            [fallthroughType] + returnScope.returnValueTypes.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
        )
        // STDLIB-592 definite assignment: record which outer-scope locals this
        // lambda body unconditionally initializes, mirroring the blockExpr merge
        // in ExprTypeChecker.swift. `locals` itself is never mutated here -- the
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
            if expectedFunctionType.returnType != sema.types.unitType {
                driver.emitSubtypeConstraint(
                    left: inferredBodyType,
                    right: expectedFunctionType.returnType,
                    range: ast.arena.exprRange(body),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.markSamConversion(id)
            let underlyingFuncType = sema.types.make(.functionType(expectedFunctionType))
            sema.bindings.bindSamUnderlyingFunctionType(id, type: underlyingFuncType)
            sema.bindings.bindExprType(id, type: expectedType)
            return expectedType
        }

        if let expectedFunctionType {
            if !expectedTypeIsHintOnly,
               let session = ctx.builderInference,
               expectedFunctionType.returnType != sema.types.unitType,
               session.mentionsVariable(expectedFunctionType.returnType, types: sema.types)
            {
                session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: inferredBodyType,
                    supertype: expectedFunctionType.returnType,
                    typeVarBySymbol: session.typeVarBySymbol,
                    typeSystem: sema.types,
                    blameRange: ast.arena.exprRange(body)
                ))
                let functionType = sema.types.make(.functionType(expectedFunctionType))
                sema.bindings.bindExprType(id, type: functionType)
                return functionType
            }
            // Enhanced return type inference with Unit optimization
            let optimizedReturnType = expectedTypeIsHintOnly
                ? inferredBodyType
                : inferOptimizedReturnType(
                    inferredBodyType: inferredBodyType,
                    expectedReturnType: expectedFunctionType.returnType,
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
                    diagnostics: ctx.semaCtx.diagnostics
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
            // `Any`/`Any?` expected returns are placeholders the same way:
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
            // as `1`/`97`.
            let expectedReturnIsErasedNonHOFPlaceholder =
                (expectedFunctionType.returnType == sema.types.anyType
                    || expectedFunctionType.returnType == sema.types.nullableAnyType)
                && !sema.bindings.isCollectionHOFLambdaExpr(id)
            let shouldReturnResolvedFunctionType = expectedTypeIsHintOnly
                || expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
                || expectedReturnIsErasedNonHOFPlaceholder
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
            returnType: inferredBodyType,
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

    /// Finds the parent call context for a lambda expression by scanning the arena.
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

    /// Infers the type for an implicit `it` parameter based on context
    private func inferItParameterType(ctx: TypeInferenceContext, id: ExprID, sema: SemaModule) -> TypeID? {
        if let parentCall = findParentCallContext(for: id, ctx: ctx, sema: sema) {
            return inferTypeFromHOFContext(parentCall, ctx: ctx, sema: sema)
        }

        if let assignmentType = inferFromAssignmentContext() {
            return assignmentType
        }

        return nil
    }

    /// Infers lambda parameter type from HOF call context
    private func inferTypeFromHOFContext(
        _ callContext: ParentLambdaCallContext,
        ctx: TypeInferenceContext,
        sema: SemaModule
    ) -> TypeID? {
        let candidateSymbols: [SymbolID]
        let argIndex: Int
        let explicitTypeArgRefs: [TypeRefID]

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
            candidateSymbols = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            )
        }

        let explicitTypeArgs = explicitTypeArgRefs.map { typeArgRef in
            driver.helpers.resolveTypeRef(
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
            let parameterType = signature.parameterTypes[argIndex]
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
        guard explicitType != sema.types.errorType else {
            return type
        }
        return typeParam.nullability == .nullable
            ? sema.types.makeNullable(explicitType)
            : explicitType
    }

    /// Infers lambda parameter type from assignment context
    private func inferFromAssignmentContext() -> TypeID? {
        // This would analyze assignments like `val x: (Int) -> String = { it.toString() }`
        return nil
    }

    /// Optimizes return type inference for lambda expressions
    private func inferOptimizedReturnType(
        inferredBodyType: TypeID,
        expectedReturnType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        // Unit optimization: if expected type is Unit, always return Unit
        if expectedReturnType == sema.types.unitType {
            return sema.types.unitType
        }

        // If the body is already compatible with expected type, use it
        if sema.types.isSubtype(inferredBodyType, expectedReturnType) {
            return inferredBodyType
        }

        // Fall back to inferred type
        return inferredBodyType
    }
}
