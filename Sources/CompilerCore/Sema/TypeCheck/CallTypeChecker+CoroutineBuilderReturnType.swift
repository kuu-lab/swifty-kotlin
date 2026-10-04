
extension CallTypeChecker {
    func coroutineScopeType(sema: SemaModule, interner: StringInterner) -> TypeID? {
        let symbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlinx"),
            interner.intern("coroutines"),
            interner.intern("CoroutineScope"),
        ])
        guard let symbol else { return nil }
        return sema.types.make(.classType(ClassType(
            classSymbol: symbol,
            args: [],
            nullability: .nonNull
        )))
    }

    func isCoroutineScopeType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let expected = coroutineScopeType(sema: sema, interner: interner) else {
            return false
        }
        return sema.types.isSubtype(
            sema.types.makeNonNullable(type),
            sema.types.makeNonNullable(expected)
        )
    }

    func markCoroutineScopeImplicitReceiverCallIfNeeded(
        _ expr: ExprID,
        chosenCallee: SymbolID,
        receiverType: TypeID,
        ctx: TypeInferenceContext
    ) {
        guard ctx.isCoroutineBuilderLambdaScope,
              isCoroutineScopeType(receiverType, sema: ctx.sema, interner: ctx.interner),
              let signature = ctx.sema.symbols.functionSignature(for: chosenCallee),
              signature.receiverType != nil
        else {
            return
        }
        ctx.sema.bindings.markCoroutineScopeImplicitReceiverCall(expr)
    }

    /// `async`/`coroutineScope`/`supervisorScope` are registered with an
    /// `Any`-returning signature (STDLIB-CORO builders don't get real generic
    /// dispatch). Narrow the call's bound type using the trailing lambda's
    /// already-inferred body type instead, mirroring the Flow `.map` element-type
    /// readback in CallTypeChecker+MemberCallInferenceRegularNoCandidateFallbacks.swift.
    ///
    /// For `async`, preserve the declared `Deferred` shape: the source-backed
    /// builder uses `Deferred<Any>`, while a synthetic-only fallback may still
    /// be non-generic. Track the actual element type via `bindDeferredElementType`
    /// without changing `ClassType.args`.
    func coroutineBuilderNarrowedReturnType(
        id: ExprID,
        launcherName: String,
        lambdaArgExpr: ExprID,
        fallback: TypeID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID {
        // The lambda literal's own function-type signature mirrors the *expected*
        // type it was inferred against (usually `Any`, see
        // coroutineLauncherExpectedLambdaType above), not the body's actual
        // tightest type. Dig into the AST for the body expression's own bound
        // type instead, same as the Flow `.map` element-type readback.
        guard case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(lambdaArgExpr),
              let bodyReturnType = sema.bindings.exprType(for: bodyExpr)
        else {
            return fallback
        }
        guard launcherName == "async" else {
            return bodyReturnType
        }
        sema.bindings.bindDeferredElementType(bodyReturnType, forExpr: id)
        return fallback
    }

    /// `Deferred.await()` resolves as a normal member candidate. When an async
    /// receiver expression (or the local symbol it was
    /// assigned to) carries a tracked element type from
    /// `coroutineBuilderNarrowedReturnType` above, use that instead of always
    /// widening to `Any?`.
    func deferredAwaitResultType(
        receiverID: ExprID,
        fallback: TypeID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID {
        if let elementType = sema.bindings.deferredElementType(forExpr: receiverID) {
            return elementType
        }
        if case .nameRef = ast.arena.expr(receiverID),
           let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
           let elementType = sema.bindings.deferredElementType(forSymbol: receiverSymbol)
        {
            return elementType
        }
        return fallback
    }
}
