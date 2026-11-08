// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    private func bundledProduceIsVisible(_ name: InternedString, ctx: TypeInferenceContext) -> Bool {
        guard let file = ctx.currentASTFile else { return false }
        let fqName = KnownCompilerNames(interner: ctx.interner).kotlinxCoroutinesProduceFQName
        let package = Array(fqName.dropLast())
        if file.packageFQName == package { return true }
        return file.imports.contains { declaration in
            if declaration.isWildcard { return declaration.path == package }
            return declaration.path == fqName && (declaration.alias ?? fqName.last) == name
        }
    }

    func continuationNominalSymbol(
        for fqName: [InternedString],
        in sema: SemaModule
    ) -> SymbolID? {
        sema.symbols.lookupAll(fqName: fqName).first { candidate in
            guard let kind = sema.symbols.symbol(candidate)?.kind else {
                return false
            }
            return kind == .class || kind == .interface
        }
    }

    func inferBundledProduceCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if let calleeName,
           calleeName == knownNames.produce,
           bundledProduceIsVisible(calleeName, ctx: ctx),
           !args.isEmpty,
           locals[calleeName] == nil,
           let lastArgumentExprID = args.last?.expr,
           isLambdaLiteralArg(lastArgumentExprID, ast: ast)
        {
            // KSP-1573: prefer the bundled `CoroutineScope.produce` extension
            // when it is visible; it composes channel + kk_coroutine_scope_launch
            // in real Kotlin source, and its block is a boxed suspend lambda.
            if let boundProduceResult = tryBindSourceBackedProduceCall(
                id,
                calleeName: calleeName,
                args: args,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedType,
                explicitTypeArgs: explicitTypeArgs) {
                return boundProduceResult
            }
        }
        return nil
    }

    func inferProduceCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // Function *values* (named `suspend ProducerScope<E>.() -> Unit`
        // bindings, callable references, members) fall through to generic
        // overload resolution: the send-scan element inference is only needed
        // for literals, and a declared value already pins E for the solver.
        // The same holds for `actor`, which is generic-only here.
        if let calleeName,
           calleeName == knownNames.produce,
           bundledProduceIsVisible(calleeName, ctx: ctx),
           args.count == 1,
           locals[calleeName] == nil,
           let argumentExprID = args.first?.expr,
           isValidBuilderLambdaArgument(argumentExprID, ast: ast)
        {
            // Leave arity-compatible nearer callables to ordinary resolution.
            // Type-incompatible candidates require separate handling (KUU-3720).
            if ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      symbol.fqName != knownNames.kotlinxCoroutinesProduceFQName,
                      let signature = sema.symbols.functionSignature(for: candidate)
                else { return false }
                return isCallableArityCompatible(signature: signature, argCount: args.count)
            }) {
                return nil
            }
            // See the coroutineLauncherLambdaExprIDs doc comment: produce{}'s
            // captures are forwarded via CoroutineLoweringPass+LauncherSupport's
            // launcher-continuation rewrite (BUG-049), not the generic
            // escaping-callable-value (kk_function_create_N) ABI.
            sema.bindings.markCoroutineLauncherLambdaExpr(argumentExprID)

            let channelType = produceBuilderChannelType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = produceBuilderReceiverType(
                channelType: channelType,
                sema: sema,
                interner: interner
            )
            let lambdaExpectedType = sequenceBuilderLambdaType(
                receiverType: receiverType,
                sema: sema
            )
            _ = driver.inferExpr(
                argumentExprID,
                ctx: ctx.with(implicitReceiverType: receiverType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let refinedChannelType = produceBuilderChannelType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: knownNames.kotlinxCoroutinesProduceFQName) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: refinedChannelType)
            return refinedChannelType
        }
        return nil
    }

    func inferSuspendCoroutineIntrinsicCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        calleePath: [InternedString]?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        let suspendCoroutineIntrinsicFQName = knownNames.kotlinCoroutinesIntrinsicsFQName + [knownNames.suspendCoroutineUninterceptedOrReturn]
        let isSuspendCoroutineIntrinsic = if let calleeName {
            calleeName == knownNames.suspendCoroutineUninterceptedOrReturn
                && locals[calleeName] == nil
                && sourceOrSyntheticStdlibFunctionSymbol(
                    calleeName,
                    fqComponents: ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"],
                    ctx: ctx
                ) != nil
        } else {
            calleePath == suspendCoroutineIntrinsicFQName
        }
        let isSuspendCoroutineShadowed = calleeName.map {
            locals[$0] != nil
        } ?? false
        if isSuspendCoroutineIntrinsic,
           args.count == 1,
           !isSuspendCoroutineShadowed
        {
            let resultType = resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) ?? expectedType ?? sema.types.anyType
            let continuationType: TypeID = if let continuationSymbol = continuationNominalSymbol(
                for: knownNames.kotlinCoroutinesFQName + [knownNames.continuation],
                in: sema
            ) {
                sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(resultType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let blockExpectedType = sema.types.make(.functionType(FunctionType(
                params: [continuationType],
                returnType: sema.types.nullableAnyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockExpectedType
            )
            if let chosen = sema.symbols.lookup(fqName: knownNames.kotlinCoroutinesIntrinsicsFQName + [knownNames.suspendCoroutineUninterceptedOrReturn]) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [resultType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .suspendCoroutineUninterceptedOrReturn)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }

    func inferSuspendCoroutineCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // Keep this path separate from generic overload resolution so the
        // lambda parameter can be inferred from the coroutine result type.
        if let calleeName,
           calleeName == knownNames.suspendCoroutine,
           args.count == 1
        {
            let resultType = expectedType ?? resolvedExplicitTypeArgument(at: 0, in: explicitTypeArgs) ?? sema.types.anyType
            let continuationType: TypeID = if let continuationSymbol = continuationNominalSymbol(
                for: knownNames.kotlinContinuationFQName,
                in: sema
            ) {
                sema.types.make(.classType(ClassType(
                    classSymbol: continuationSymbol,
                    args: [.invariant(resultType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [continuationType],
                returnType: sema.types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            if let suspendCoroutineSymbol = sema.symbols.lookup(fqName: knownNames.kotlinSuspendCoroutineFQName) {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: suspendCoroutineSymbol,
                    substitutedTypeArguments: [resultType],
                    parameterMapping: [0: 0]
                ))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }
        return nil
    }

    /// `suspend { p: T -> body }` is a suspend function *literal*: the
    /// `suspend` keyword modifies the lambda, so the declared parameter list
    /// shapes the resulting `suspend (T) -> R` type. The bundled
    /// `kotlin.suspend(noinline block: suspend () -> R)` only models the
    /// zero-parameter form, so a literal that declares value parameters is
    /// otherwise rejected for arity mismatch against `suspend () -> R`
    /// (KUU-4475). Intercept the literal shape, infer the lambda against a
    /// suspend function type of matching arity, and mark the call for
    /// transparent lowering — the expression's value is the lambda itself,
    /// not a call to `kotlin.suspend`.
    func inferSuspendLambdaLiteralCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        guard let calleeName,
              calleeName == interner.intern("suspend"),
              explicitTypeArgs.isEmpty,
              args.count == 1,
              let lambdaExprID = args.first?.expr,
              !ast.arena.isParenthesized(lambdaExprID),
              case let .lambdaLiteral(params, _, _, _) = ast.arena.expr(lambdaExprID),
              locals[calleeName] == nil
        else {
            return nil
        }

        let expectedSuspendFunctionType: FunctionType? = expectedType.flatMap { expected in
            guard case let .functionType(functionType) = sema.types.kind(
                of: sema.types.makeNonNullable(expected)
            ), functionType.isSuspend else {
                return nil
            }
            return functionType
        }

        let lambdaExpectedType: TypeID
        if params.isEmpty {
            // The zero-parameter literal stays on the bundled arity-0 call
            // path unless an expected suspend function type supplies a
            // receiver or the single implicit `it` parameter.
            guard let expectedSuspendFunctionType,
                  expectedSuspendFunctionType.params.count == 1
                      || expectedSuspendFunctionType.receiver != nil,
                  let expectedType
            else {
                return nil
            }
            lambdaExpectedType = expectedType
        } else if let expectedSuspendFunctionType,
                  expectedSuspendFunctionType.params.count == params.count,
                  let expectedType
        {
            lambdaExpectedType = expectedType
        } else {
            // Declared annotations pin the parameter types; the synthesized
            // `Any?` return is a placeholder so the body's inferred type
            // flows through (matching the erased-placeholder rule in
            // `inferLambdaLiteralExpr`).
            guard let typeRefs = ast.arena.lambdaParamTypeRefs(for: lambdaExprID),
                  typeRefs.count == params.count
            else {
                return nil
            }
            var declaredParameterTypes: [TypeID] = []
            declaredParameterTypes.reserveCapacity(params.count)
            for typeRef in typeRefs {
                guard let typeRef else { return nil }
                let resolved = driver.helpers.resolveTypeRef(
                    typeRef,
                    ast: ast,
                    sema: sema,
                    interner: interner,
                    scope: ctx.scope,
                    inferenceContext: ctx
                )
                guard resolved != sema.types.errorType else { return nil }
                declaredParameterTypes.append(resolved)
            }
            lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: declaredParameterTypes,
                returnType: sema.types.nullableAnyType,
                isSuspend: true,
                nullability: .nonNull
            )))
        }

        let lambdaType = driver.inferExpr(
            lambdaExprID,
            ctx: ctx,
            locals: &locals,
            expectedType: lambdaExpectedType
        )
        let lambdaReturnType: TypeID = if case let .functionType(functionType) = sema.types.kind(
            of: sema.types.makeNonNullable(lambdaType)
        ) {
            functionType.returnType
        } else {
            sema.types.nullableAnyType
        }
        if let suspendSymbol = sema.symbols.lookup(
            fqName: [interner.intern("kotlin"), calleeName]
        ) {
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: suspendSymbol,
                substitutedTypeArguments: [lambdaReturnType],
                parameterMapping: [0: 0]
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(suspendSymbol))
        }
        sema.bindings.markStdlibSpecialCallExpr(id, kind: .suspendLambdaLiteral)
        sema.bindings.bindExprType(id, type: lambdaType)
        return lambdaType
    }

    func resolveWithContextExpectedLambdaType(
        calleeName: InternedString?,
        args: [CallArgument],
        expectedType: TypeID?,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        let withContextExpectedLambdaType: TypeID? = if let calleeName,
                                                        calleeName == knownNames.withContext
                                                            || calleeName == knownNames.withTimeout
                                                            || calleeName == knownNames.withTimeoutOrNull,
                                                        args.count >= 2,
                                                        let secondArgExpr = ast.arena.expr(args[1].expr),
                                                        case .lambdaLiteral = secondArgExpr
        {
            sema.types.make(.functionType(FunctionType(
                receiver: coroutineScopeType(sema: sema, interner: interner),
                params: [],
                returnType: expectedType ?? sema.types.nullableAnyType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            nil
        }

        return withContextExpectedLambdaType
    }
}
