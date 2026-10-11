// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Builder-style call interceptions from the `inferCallExpr` dispatch chain:
/// the stdlib `buildList`/`buildSet`/`buildMap` DSL functions, the `sequence {}`
/// and `iterator {}` builders, and the `memScoped` block helper. Each infers
/// its lambda argument with a synthetic receiver scope that generic overload
/// resolution cannot provide.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func inferBuilderDSLSpecialCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        // --- Builder DSL functions (STDLIB-002) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        if let calleeName {
            if let builderKind = builderDSLKind(for: calleeName, interner: interner),
               shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
            {
                let lambdaArgumentIndex: Int? = switch builderKind {
                case .buildList:
                    switch args.count {
                    case 1: 0
                    case 2: 1
                    default: nil
                    }
                case .buildSet, .buildMap:
                    args.count == 1 ? 0 : nil
                }
                guard let lambdaArgumentIndex else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if builderKind == .buildList,
                    args.count == 2
                {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                let argumentExprID = args[lambdaArgumentIndex].expr
                guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }

                let receiverType = builderDSLReceiverType(
                    kind: builderKind,
                    lambdaExprID: argumentExprID,
                    expectedType: expectedType,
                    ctx: ctx,
                    locals: locals,
                    sema: sema,
                    interner: interner
                )
                let returnType: TypeID = switch builderKind {
                case .buildList:
                    builderDSLBuildListReturnType(receiverType: receiverType, sema: sema, interner: interner)
                case .buildSet:
                    builderDSLBuildSetReturnType(receiverType: receiverType, sema: sema, interner: interner)
                case .buildMap:
                    builderDSLBuildMapReturnType(receiverType: receiverType, sema: sema, interner: interner)
                }
                // Infer the lambda argument with the builder receiver as implicit `this`.
                var builderCtx = ctx.with(implicitReceiverType: receiverType)
                builderCtx.isBuilderLambdaScope = true
                builderCtx.builderKind = builderKind
                _ = driver.inferExpr(argumentExprID, ctx: builderCtx, locals: &locals)
                sema.bindings.markBuilderDSLExpr(id, kind: builderKind)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
        }
        return nil
    }

    func inferSequenceBuilderCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        // --- sequence { ... } builder (STDLIB-330) ---
        // Intercept before eager argument inference so the lambda is inferred
        // with a SequenceScope<T> implicit receiver and T can be recovered from
        // expected type or nested yield()/yieldAll() calls.
        if let calleeName,
           calleeName == knownNames.sequenceFn,
           args.count == 1,
           shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let returnType = sequenceBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                explicitElementType: explicitTypeArgs.first,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = sequenceBuilderReceiverType(
                sequenceType: returnType,
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
            let refinedReturnType = sequenceBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                explicitElementType: explicitTypeArgs.first,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("sequence"),
            ]) {
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
            sema.bindings.markCollectionHOFLambdaExpr(argumentExprID)
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }
        return nil
    }

    func inferIteratorBuilderCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        // --- iterator { ... } builder (STDLIB-331/564) ---
        if let calleeName,
           calleeName == knownNames.iterator,
           args.count == 1,
           locals[calleeName] == nil
        {
            let argumentExprID = args[0].expr
            guard isValidBuilderLambdaArgument(argumentExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }

            let returnType = iteratorBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                explicitElementType: explicitTypeArgs.first,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            let receiverType = sequenceBuilderReceiverType(
                sequenceType: returnType,
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
            let refinedReturnType = iteratorBuilderReturnType(
                lambdaExprID: argumentExprID,
                expectedType: expectedType,
                explicitElementType: explicitTypeArgs.first,
                ctx: ctx,
                locals: locals,
                sema: sema,
                interner: interner
            )
            if let chosen = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("sequences"),
                interner.intern("iterator"),
            ]) {
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
            // KUU-1359: the iterator {} block is a receiver lambda invoked by
            // the runtime builder through the (closureRaw, receiver) suspend
            // entry ABI, same as sequence {}. Mark it so KIR lowering keeps the
            // raw lambda + captures instead of boxing a suspend function value
            // whose closure environment the build rewrite cannot recover.
            sema.bindings.markCollectionHOFLambdaExpr(argumentExprID)
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }
        return nil
    }

    // --- kotlinx.cinterop.memScoped { } (KUU-1375) ---
    // `inline fun <R> memScoped(block: MemScope.() -> R): R` needs the
    // receiver-function expected type pushed into the block so `alloc`,
    // `cstr`, and friends resolve against the MemScope implicit receiver,
    // and needs marking so KIR lowering emits the arena
    // create/invoke/clear try-finally instead of a phantom call.
    func inferMemScopedCall(
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

        let memScopedHelperName = interner.intern("memScoped")
        if let calleeName,
           calleeName == memScopedHelperName,
           args.count == 1,
           locals[calleeName] == nil,
           let memScopedSymbol = ctx.cachedScopeLookup(calleeName).first(where: { candidate in
               guard let signature = sema.symbols.functionSignature(for: candidate),
                     signature.receiverType == nil,
                     signature.parameterTypes.count == 1,
                     let info = sema.symbols.symbol(candidate),
                     info.fqName == [
                         interner.intern("kotlinx"),
                         interner.intern("cinterop"),
                         memScopedHelperName,
                     ]
               else {
                   return false
               }
               return true
           }),
           let memScopeSymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlinx"),
               interner.intern("cinterop"),
               interner.intern("MemScope"),
           ])
        {
            let memScopeType = sema.types.make(.classType(ClassType(
                classSymbol: memScopeSymbol,
                args: [],
                nullability: .nonNull
            )))
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: memScopeType,
                params: [],
                returnType: expectedType ?? sema.types.nullableAnyType
            )))
            // Lambda literals need the MemScope implicit receiver in scope;
            // declared function-typed values only need the expected type.
            let blockArgExpr = args[0].expr
            let lambdaCtx = isLambdaLiteralArg(blockArgExpr, ast: ast)
                ? ctx.with(implicitReceiverType: memScopeType)
                : ctx
            let lambdaType = driver.inferExpr(
                blockArgExpr, ctx: lambdaCtx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            // Non-function arguments fall through to normal resolution so the
            // standard diagnostics path reports the mismatch.
            if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                let returnType = fnType.returnType
                let refinedReturnType: TypeID = {
                    guard returnType == sema.types.nullableAnyType else { return returnType }
                    guard let lambdaExpr = ast.arena.expr(blockArgExpr),
                          case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr,
                          let bodyType = sema.bindings.exprTypes[bodyExprID],
                          bodyType != sema.types.anyType
                    else { return returnType }
                    if case .nothing = sema.types.kind(of: bodyType) { return returnType }
                    return bodyType
                }()
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: memScopedSymbol,
                        substitutedTypeArguments: [refinedReturnType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(memScopedSymbol))
                sema.bindings.markScopeFunctionExpr(id, kind: .scopeMemScoped)
                // Force the capturing-lambda lowering path so exception
                // propagation through the arena finally block works (mirrors
                // scopeUse/scopeUsePinned).
                sema.bindings.markCollectionHOFLambdaExpr(blockArgExpr)
                sema.bindings.bindExprType(id, type: refinedReturnType)
                return refinedReturnType
            }
        }

        // --- produce { ... } builder (CORO-075) ---
        return nil
    }
}
