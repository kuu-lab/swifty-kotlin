// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Interceptions for the `kotlin.context` / `kotlin.contextOf` bundled-stdlib
/// helpers: both are name-matched special cases that must run ahead of generic
/// overload resolution from the `inferCallExpr` dispatch chain.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func inferContextOfCall(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if let calleeName,
           calleeName == knownNames.contextOf,
           args.isEmpty,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               shadowsStdlibContextHelper(
                   candidate,
                   named: "contextOf",
                   argumentCount: 0,
                   explicitTypeArgumentCount: explicitTypeArgs.count,
                   ctx: ctx,
                   sema: sema,
                   interner: interner
               )
           })
        {
            let contextOfFQName = [interner.intern("kotlin"), calleeName]
            if let contextOfSymbol = sema.symbols.lookup(fqName: contextOfFQName) {
                let inferredType = explicitTypeArgs.first
                    ?? expectedType
                    ?? (ctx.contextReceiverTypes.count == 1 ? ctx.contextReceiverTypes[0] : sema.types.anyType)
                driver.helpers.checkOptIn(
                    for: contextOfSymbol,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                let nonNullInferredType = sema.types.makeNonNullable(inferredType)
                let hasMatchingContextReceiver = ctx.contextReceiverTypes.contains { receiverType in
                    let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
                    return sema.types.isSubtype(nonNullReceiverType, nonNullInferredType)
                        || sema.types.isSubtype(nonNullInferredType, nonNullReceiverType)
                }
                if !hasMatchingContextReceiver {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-CTX-001",
                        "No context receiver is available for contextOf<\(sema.types.renderType(inferredType))>().",
                        range: range
                    )
                }
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: contextOfSymbol,
                        substitutedTypeArguments: [inferredType],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(contextOfSymbol))
                sema.bindings.bindExprType(id, type: inferredType)
                return inferredType
            }
        }
        return nil
    }

    func inferContextHelperCall(
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


        // --- Context helper: context(with, block) (STDLIB-KOTLIN-ROOT-CTX-001) ---
        // The helper makes the first argument available as a context receiver
        // for the block type, but does not make it an implicit receiver.
        let contextHelperName = interner.intern("context")
        if let calleeName, args.count >= 2, args.count <= 23,
           calleeName == contextHelperName,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               shadowsStdlibContextHelper(
                   candidate,
                   named: "context",
                   argumentCount: args.count,
                   explicitTypeArgumentCount: explicitTypeArgs.count,
                   ctx: ctx,
                   sema: sema,
                   interner: interner
               )
           })
        {
            let contextValueArgs = Array(args.dropLast())
            let blockArg = args[args.count - 1]
            let contextValueTypes = contextValueArgs.map {
                driver.inferExpr($0.expr, ctx: ctx, locals: &locals)
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                contextReceivers: contextValueTypes,
                params: [],
                returnType: expectedType ?? sema.types.anyType
            )))
            let lambdaType = driver.inferExpr(
                blockArg.expr,
                ctx: ctx,
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[blockArg.expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            // Refine the call result type using the lambda body's concrete type,
            // but ONLY when no expected type was provided (i.e. expected was
            // anyType, the placeholder for "unconstrained") — mirrors the
            // `use`/`usePinned`/`useContents` refinement above. Needed when the
            // `context(...) { ... }` call itself isn't in a target-typed
            // position, e.g. as an operand of `+`:
            //   context("one") { contextOf<String>() } + context(...) { ... }
            let refinedReturnType: TypeID = {
                guard returnType == sema.types.anyType else { return returnType }
                guard let lambdaExpr = ast.arena.expr(blockArg.expr),
                      case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr,
                      let bodyType = sema.bindings.exprTypes[bodyExprID],
                      bodyType != sema.types.anyType
                else { return returnType }
                return bodyType
            }()
            if let contextSymbol = ctx.cachedScopeLookup(calleeName).first(where: { candidate in
                guard isStdlibContextHelper(candidate, named: "context", ctx: ctx, interner: interner),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count
                else {
                    return false
                }
                return true
            }) {
                driver.helpers.checkOptIn(
                    for: contextSymbol,
                    ctx: ctx,
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: contextSymbol,
                        substitutedTypeArguments: contextValueTypes + [refinedReturnType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(contextSymbol))
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeContext)
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }
        return nil
    }
}
