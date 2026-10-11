// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Coroutine call interceptions from the `inferCallExpr` dispatch chain:
/// `produce`/`actor`-family builder calls, the `suspendCoroutine` intrinsics
/// (fully qualified and unqualified), and the `withContext`/`withTimeout`
/// trailing-lambda expected-type helper.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func inferBundledProduceCall(
        _ id: ExprID,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        if let calleeName,
           calleeName == knownNames.produce,
           !args.isEmpty,
           args.count <= 2,
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
                ast: ast
            ) {
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
           args.count == 1,
           locals[calleeName] == nil,
           let argumentExprID = args.first?.expr,
           isValidBuilderLambdaArgument(argumentExprID, ast: ast)
        {
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

        // --- kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn ---
        // Special intrinsic used by coroutine lowering. The block is type-checked
        // as a regular function taking the current Continuation<T>.
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
            let resultType = explicitTypeArgs.first ?? expectedType ?? sema.types.anyType
            let continuationType: TypeID = if let continuationSymbol = sema.symbols.lookup(fqName: knownNames.kotlinCoroutinesFQName + [knownNames.continuation]) {
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

        // --- suspendCoroutine(block) ---
        // Keep this path separate from generic overload resolution so the
        // lambda parameter can be inferred from the coroutine result type.
        if let calleeName,
           calleeName == knownNames.suspendCoroutine,
           args.count == 1
        {
            let resultType = expectedType ?? explicitTypeArgs.first ?? sema.types.anyType
            let continuationType: TypeID = if let continuationSymbol = sema.symbols.lookup(fqName: knownNames.kotlinContinuationFQName) {
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

    /// Returns the synthesized `CoroutineScope.() -> T` expected type for the
    ///     /// trailing lambda of `withContext`/`withTimeout`/`withTimeoutOrNull`, or nil.
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
