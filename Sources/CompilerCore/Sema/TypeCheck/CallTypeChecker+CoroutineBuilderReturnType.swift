
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

    /// Recover erased builder results from the block's inferred return type.
    /// Source-backed Deferred has a type argument; the synthetic fallback does
    /// not, so also retain the out-of-band element binding for that fallback.
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
        let bodyReturnType: TypeID?
        if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(lambdaArgExpr) {
            bodyReturnType = sema.bindings.exprType(for: bodyExpr)
        } else if let type = sema.bindings.exprType(for: lambdaArgExpr),
                  case let .functionType(function) = sema.types.kind(of: type) {
            bodyReturnType = function.returnType
        } else {
            bodyReturnType = nil
        }
        guard let bodyReturnType else {
            return fallback
        }
        guard launcherName == "async" else {
            return launcherName == "withTimeoutOrNull"
                ? sema.types.makeNullable(bodyReturnType) : bodyReturnType
        }
        sema.bindings.bindDeferredElementType(bodyReturnType, forExpr: id)
        if case let .classType(deferredType) = sema.types.kind(of: fallback),
           sema.types.nominalTypeParameterSymbols(for: deferredType.classSymbol).count == 1
        {
            return sema.types.make(.classType(ClassType(
                classSymbol: deferredType.classSymbol,
                args: [.invariant(bodyReturnType)],
                nullability: deferredType.nullability
            )))
        }
        return fallback
    }

    /// Recover the element type when Deferred's fallback signature erases it.
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
