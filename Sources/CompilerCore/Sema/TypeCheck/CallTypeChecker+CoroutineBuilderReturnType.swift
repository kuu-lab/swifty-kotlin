
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
    /// Source-backed `Deferred<out T>` needs a matching `ClassType.args` list
    /// or `.await()` cannot find the member (KSWIFTK-SEMA-0002). Residual
    /// `async` may still be stored as a raw `Deferred`; rebuild a well-kinded
    /// `Deferred<out Body>` here. The source `CoroutineScope.async` builder
    /// already returns `Deferred<Any>` (#7517). The element type is also
    /// tracked out-of-band via `bindDeferredElementType` so `await(): T` can
    /// be narrowed off the residual `Any` fallback.
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
            return launcherName == "async"
                ? wellKindedDeferredReturnType(fallback: fallback, elementType: nil, sema: sema)
                : fallback
        }
        guard launcherName == "async" else {
            return bodyReturnType
        }
        sema.bindings.bindDeferredElementType(bodyReturnType, forExpr: id)
        return wellKindedDeferredReturnType(
            fallback: fallback,
            elementType: bodyReturnType,
            sema: sema
        )
    }

    /// Fill `Deferred`'s class type argument when the residual `async` return
    /// type was stored without one. No-op when the fallback is already
    /// well-kinded or `Deferred` is still the parameterless synthetic handle.
    func wellKindedDeferredReturnType(
        fallback: TypeID,
        elementType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard case let .classType(classType) = sema.types.kind(of: fallback) else {
            return fallback
        }
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: classType.classSymbol)
        guard !typeParameters.isEmpty, classType.args.count != typeParameters.count else {
            return fallback
        }
        let filledElement = elementType ?? sema.types.anyType
        return sema.types.make(.classType(ClassType(
            classSymbol: classType.classSymbol,
            args: typeParameters.map { _ in .out(filledElement) },
            nullability: classType.nullability
        )))
    }

    /// `Deferred.await()` is the source member `await(): T` after KSP-1564.
    /// When the receiver expression (or the local symbol it was assigned to)
    /// carries a tracked element type from `coroutineBuilderNarrowedReturnType`
    /// above, use that instead of always widening to `Any?`.
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
