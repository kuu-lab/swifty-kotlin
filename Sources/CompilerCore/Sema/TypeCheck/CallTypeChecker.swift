// swiftlint:disable file_length

// swiftlint:disable type_body_length
final class CallTypeChecker {
    unowned let driver: TypeCheckDriver

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    // swiftlint:disable:next cyclomatic_complexity function_body_length
    func inferCallExpr(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        let calleeExpr = ast.arena.expr(calleeID)
        let calleeName: InternedString? = if case let .nameRef(name, _) = calleeExpr {
            name
        } else {
            nil
        }
        let calleePath = qualifiedCalleePath(for: calleeID, ast: ast)
        if let calleeName,
           calleeName == interner.intern("contextOf"),
           args.isEmpty,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               guard let sym = ctx.cachedSymbol(candidate) else { return false }
               return !sym.flags.contains(.synthetic)
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
        if let customBuilderType = inferExperimentalBuilderCallExpr(
            id,
            calleeName: calleeName,
            args: args,
            ctx: ctx,
            locals: &locals,
            expectedType: expectedType,
            explicitTypeArgs: explicitTypeArgs
        ) {
            return customBuilderType
        }
        // --- Builder DSL functions (STDLIB-002) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        if let calleeName {
            if let builderKind = builderDSLKind(for: calleeName, interner: interner),
               shouldUseBuilderDSLSpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
            {
                let lambdaArgumentIndex: Int? = switch builderKind {
                case .buildString, .buildStringBuilder:
                    switch args.count {
                    case 1: 0
                    case 2: 1
                    default: nil
                    }
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
                if builderKind == .buildList
                    || builderKind == .buildString
                    || builderKind == .buildStringBuilder,
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
                case .buildString:
                    sema.types.stringType
                case .buildStringBuilder:
                    receiverType
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

        // --- sequence { ... } builder (STDLIB-330) ---
        // Intercept before eager argument inference so the lambda is inferred
        // with a SequenceScope<T> implicit receiver and T can be recovered from
        // expected type or nested yield()/yieldAll() calls.
        if let calleeName,
           interner.resolve(calleeName) == "sequence",
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
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }

        // --- iterator { ... } builder (STDLIB-331/564) ---
        if let calleeName,
           interner.resolve(calleeName) == "iterator",
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
            sema.bindings.bindExprType(id, type: refinedReturnType)
            return refinedReturnType
        }

        // --- Scope function: with(receiver, block) (STDLIB-004, STDLIB-061) ---
        // Must intercept BEFORE eager arg inference so the lambda argument
        // is inferred with the correct implicit receiver type.
        // Intercept when no local or user-defined (non-synthetic) `with` shadows the stdlib helper.
        if let calleeName, args.count == 2,
           calleeName == knownNames.with,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               guard let sym = ctx.cachedSymbol(candidate) else { return false }
               return !sym.flags.contains(.synthetic)
           })
        {
            // First arg is the receiver object
            let withReceiverType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            // Second arg is the lambda with receiver
            let receiverCtx = ctx.with(implicitReceiverType: withReceiverType)
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: withReceiverType,
                params: [],
                returnType: expectedType ?? sema.types.anyType
            )))
            let lambdaType = driver.inferExpr(
                args[1].expr, ctx: receiverCtx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[1].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeWith)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- Context helper: context(with, block) (STDLIB-KOTLIN-ROOT-CTX-001) ---
        // The helper makes the first argument available as a context receiver
        // for the block type, but does not make it an implicit receiver.
        let contextHelperName = interner.intern("context")
        if let calleeName, args.count >= 2, args.count <= 7,
           calleeName == contextHelperName,
           locals[calleeName] == nil,
           !ctx.cachedScopeLookup(calleeName).contains(where: { candidate in
               guard let sym = ctx.cachedSymbol(candidate) else { return false }
               return !sym.flags.contains(.synthetic)
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
            if let contextSymbol = ctx.cachedScopeLookup(calleeName).first(where: { candidate in
                guard let sym = ctx.cachedSymbol(candidate),
                      sym.flags.contains(.synthetic),
                      sym.fqName.map({ interner.resolve($0) }) == ["kotlin", "context"],
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
                        substitutedTypeArguments: contextValueTypes + [returnType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(contextSymbol))
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeContext)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- produce { ... } builder (CORO-075) ---
        if let calleeName,
           calleeName == knownNames.produce,
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

        // --- Scope function: top-level run(block) (STDLIB-401) ---
        // `run { expr }` simply executes the block lambda and returns the result.
        // Intercept when no local or user-defined (non-synthetic) `run` shadows the stdlib helper.
        // The single argument must be a lambda literal or callable reference;
        // otherwise (e.g. `run(123)`) fall through to normal call resolution.
        if isTopLevelRunCandidate(
            calleeName: calleeName,
            args: args,
            knownNames: knownNames,
            ast: ast,
            ctx: ctx,
            locals: locals
        ) {
            let lambdaExpectedType: TypeID? = if let expectedType {
                sema.types.make(.functionType(FunctionType(
                    params: [],
                    returnType: expectedType
                )))
            } else {
                nil
            }
            let lambdaType = driver.inferExpr(
                args[0].expr, ctx: ctx, locals: &locals,
                expectedType: lambdaExpectedType
            )
            let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            sema.bindings.markScopeFunctionExpr(id, kind: .scopeTopLevelRun)
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }

        // --- runCatching(block) (STDLIB-590) ---
        // `runCatching { expr }` executes the block lambda and wraps the result
        // in a Result<T>.  Similar to top-level `run`, but returns Result<T>.
        if let calleeName, args.count == 1,
           calleeName == knownNames.runCatching,
           locals[calleeName] == nil,
           isLambdaOrCallableRefArg(args[0].expr, ast: ast),
           let runCatchingSymbol = sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "runCatching"],
               ctx: ctx
           )
        {
            let lambdaType = driver.inferExpr(
                args[0].expr, ctx: ctx, locals: &locals, expectedType: nil
            )
            let innerType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                fnType.returnType
            } else {
                sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                    if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                        return fnType.returnType
                    }
                    return nil
                } ?? sema.types.anyType
            }
            // Build Result<T> type
            let resultType: TypeID = if let resultClassSymbol = sema.symbols.lookup(fqName: knownNames.kotlinResultFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: resultClassSymbol,
                    args: [.invariant(innerType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            // Mark the lambda for closure ABI expansion in KIR
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            // Bind the call to the stdlib runCatching function symbol.
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: runCatchingSymbol,
                substitutedTypeArguments: [innerType],
                parameterMapping: [0: 0]
            ))
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn ---
        // Special intrinsic used by coroutine lowering. The block is type-checked
        // as a regular function taking the current Continuation<T>.
        let suspendCoroutineIntrinsicFQName = knownNames.kotlinCoroutinesIntrinsicsFQName + [knownNames.suspendCoroutineUninterceptedOrReturn]
        let isSuspendCoroutineIntrinsic = if let calleeName {
            calleeName == knownNames.suspendCoroutineUninterceptedOrReturn
                && !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
                && isSyntheticStdlibSymbol(
                    calleeName,
                    fqComponents: ["kotlin", "coroutines", "intrinsics", "suspendCoroutineUninterceptedOrReturn"],
                    ctx: ctx
                )
        } else {
            calleePath == suspendCoroutineIntrinsicFQName
        }
        let isSuspendCoroutineShadowed = calleeName.map {
            isShadowedByNonSyntheticSymbol($0, locals: locals, ctx: ctx)
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

        // --- Flow builder function (CORO-003) ---
        // `flow { emit(...) }` is treated as a builtin cold stream factory.
        // We infer the lambda with a flow-builder scope so unqualified `emit`
        // resolves in Sema fallback.
        let flowFactoryNames: Set<InternedString> = [
            knownNames.flow,
            interner.intern("channelFlow"),
            interner.intern("callbackFlow"),
        ]
        if let calleeName,
           flowFactoryNames.contains(calleeName),
           args.count == 1,
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            let flowLambdaExprID = args[0].expr
            guard isValidBuilderLambdaArgument(flowLambdaExprID, ast: ast) else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for call.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var flowBuilderCtx = ctx.with(implicitReceiverType: sema.types.anyType)
            flowBuilderCtx.isFlowBuilderLambdaScope = true
            let flowLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: true,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                flowLambdaExprID,
                ctx: flowBuilderCtx,
                locals: &locals,
                expectedType: flowLambdaExpectedType
            )
            sema.bindings.markFlowExpr(id)
            if let explicitElementType = explicitTypeArgs.first {
                sema.bindings.bindFlowElementType(explicitElementType, forExpr: id)
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    sema.bindings.bindFlowElementType(type, forExpr: id)
                case .star:
                    break
                }
            }
            let flowElementType = sema.bindings.flowElementType(forExpr: id) ?? sema.types.anyType
            let flowExprType = driver.helpers.makeFlowType(
                elementType: flowElementType, sema: sema, interner: interner
            ) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: flowExprType)
            return flowExprType
        }

        let fixedFlowFactoryNames: Set<InternedString> = [
            interner.intern("flowOf"),
            interner.intern("emptyFlow"),
        ]
        if let calleeName,
           fixedFlowFactoryNames.contains(calleeName),
           shouldUseBuiltinFlowFactorySpecialHandling(calleeName: calleeName, ctx: ctx, locals: locals)
        {
            sema.bindings.markFlowExpr(id)
            if let explicitElementType = explicitTypeArgs.first {
                sema.bindings.bindFlowElementType(explicitElementType, forExpr: id)
            } else if calleeName == interner.intern("flowOf"), !args.isEmpty {
                let inferredArgTypes = args.map { driver.inferExpr($0.expr, ctx: ctx, locals: &locals) }
                let lub = sema.types.lub(inferredArgTypes)
                sema.bindings.bindFlowElementType(lub == sema.types.errorType ? sema.types.anyType : lub, forExpr: id)
            }
            let flowElementType = sema.bindings.flowElementType(forExpr: id) ?? sema.types.anyType
            let flowExprType = driver.helpers.makeFlowType(
                elementType: flowElementType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
            sema.bindings.bindExprType(id, type: flowExprType)
            return flowExprType
        }

        // --- Flow builder lambda calls (CORO-003) ---
        // Inside `flow { ... }`, unqualified `emit` resolves as a builtin
        // effect call and returns Unit.
        if ctx.isFlowBuilderLambdaScope,
           let calleeName,
           calleeName == knownNames.emit,
           args.count == 1,
           ctx.cachedScopeLookup(calleeName).isEmpty,
           locals[calleeName] == nil
        {
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        let generateSequenceName = interner.intern("generateSequence")
        let sequencesPackageFQName = [interner.intern("kotlin"), interner.intern("sequences")]
        let hasSourceGenerateSequence = sema.bundledIndex.contains(
            owner: sequencesPackageFQName,
            name: generateSequenceName,
            arity: args.count
        )
        if let calleeName,
           calleeName == generateSequenceName,
           args.count == 2
        {
            let rawSeedType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
            let seedType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(rawSeedType)),
                                      functionType.params.isEmpty
            {
                sema.types.makeNonNullable(functionType.returnType)
            } else {
                rawSeedType
            }
            let nextExpectedType = sema.types.make(.functionType(FunctionType(
                params: [seedType],
                returnType: sema.types.makeNullable(seedType),
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: nextExpectedType)
            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            sema.bindings.markCollectionExpr(id)
            let sequenceType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: seedType
            )
            if hasSourceGenerateSequence,
               let generateSequenceSymbol = sourceGenerateSequenceSymbol(
                   sema: sema,
                   interner: interner,
                   arity: 2
               )
            {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: generateSequenceSymbol,
                        substitutedTypeArguments: [seedType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(generateSequenceSymbol))
            }
            sema.bindings.bindExprType(id, type: sequenceType)
            return sequenceType
        }

        // STDLIB-SEQ-002: 1-arg form generateSequence(nextFunction: () -> T?)
        if let calleeName,
           calleeName == generateSequenceName,
           args.count == 1
        {
            // Infer the no-arg function type; deduce element type T from its return type.
            let rawNextType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
            let elementType: TypeID = if case let .functionType(functionType) = sema.types.kind(of: sema.types.makeNonNullable(rawNextType)) {
                sema.types.makeNonNullable(functionType.returnType)
            } else {
                sema.types.anyType
            }
            let nextExpectedType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.makeNullable(elementType),
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nextExpectedType)
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            sema.bindings.markCollectionExpr(id)
            let sequenceType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: elementType
            )
            if hasSourceGenerateSequence,
               let generateSequenceSymbol = sourceGenerateSequenceSymbol(
                   sema: sema,
                   interner: interner,
                   arity: 1
               )
            {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: generateSequenceSymbol,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(generateSequenceSymbol))
            }
            sema.bindings.bindExprType(id, type: sequenceType)
            return sequenceType
        }

        // --- Stdlib repeat(times) { ... } (STDLIB-008) ---
        // Infer the lambda argument with the expected `(Int) -> Unit` type so
        // implicit `it` resolves to the loop index.
        if let calleeName,
           args.count == 2,
           shouldUseRepeatSpecialHandling(calleeName: calleeName, locals: locals),
           topLevelStdlibSpecialCallKind(
               calleeName: calleeName,
               argCount: args.count,
               locals: locals,
               ctx: ctx,
               rejectNonSyntheticShadow: false
           ) == .repeatLoop
        {
            let intType = sema.types.intType
            let unitType = sema.types.unitType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let actionExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: unitType
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: actionExpectedType
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .repeatLoop)
            sema.bindings.bindExprType(id, type: unitType)
            return unitType
        }

        // --- Stdlib system timing calls: measureTimeMillis / measureTimeMicros / measureNanoTime ---
        if let calleeName,
           args.count == 1,
           let timingKind = topLevelStdlibSpecialCallKind(
               calleeName: calleeName,
               argCount: args.count,
               locals: locals,
               ctx: ctx,
               rejectNonSyntheticShadow: true
           ),
           timingKind == .measureTimeMillis
               || timingKind == .measureTimeMicros
               || timingKind == .measureNanoTime
        {
            let longType = sema.types.longType
            // Intentionally passing expectedType:nil: KIR lowering discards the
            // lambda result and the synthetic stub enforces the () -> Unit shape.
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )
            sema.bindings.markStdlibSpecialCallExpr(id, kind: timingKind)
            sema.bindings.bindExprType(id, type: longType)
            return longType
        }

        // --- Stdlib kotlin.time.measureTime { ... } (STDLIB-585) ---
        // Verify both the name and that the resolved symbol is the synthetic
        // kotlin.time.measureTime (not a user-defined function with the same name).
        if let calleeName,
           interner.resolve(calleeName) == "measureTime",
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTime"], ctx: ctx)
        {
            // Infer the block argument with an expected function type () -> Unit
            // so non-callable arguments are caught during type checking.
            let blockType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockType
            )
            // Look up the synthetic Duration class to build the return type.
            let durationFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("Duration")]
            let durationType: TypeID
            if let durationSymbol = sema.symbols.lookup(fqName: durationFQName) {
                durationType = sema.types.make(.classType(ClassType(
                    classSymbol: durationSymbol, args: [], nullability: .nonNull
                )))
            } else {
                durationType = sema.types.anyType
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTime)
            sema.bindings.bindExprType(id, type: durationType)
            return durationType
        }

        // --- Stdlib kotlin.time.measureTimedValue { ... } (STDLIB-660) ---
        if let calleeName,
           calleeName == interner.intern("measureTimedValue"),
           args.count == 1,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(calleeName, fqComponents: ["kotlin", "time", "measureTimedValue"], ctx: ctx)
        {
            // Infer the block argument with an expected function type () -> T
            // so non-callable arguments are caught during type checking.
            let blockType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: blockType
            )

            // Look up the TimedValue class to build the return type.
            let timedValueFQName = [interner.intern("kotlin"), interner.intern("time"), interner.intern("TimedValue")]
            let timedValueType: TypeID
            if let timedValueSymbol = sema.symbols.lookup(fqName: timedValueFQName) {
                timedValueType = sema.types.make(.classType(ClassType(
                    classSymbol: timedValueSymbol, args: [], nullability: .nonNull
                )))
            } else {
                timedValueType = sema.types.anyType
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .measureTimedValue)
            sema.bindings.bindExprType(id, type: timedValueType)
            return timedValueType
        }

        // --- Stdlib Array(size) { init } constructor (STDLIB-085/086, TYPE-103) ---
        if let calleeName,
           knownNames.isPrimitiveArrayConstructorTypeName(calleeName),
           args.count == 2 || (args.count == 1 && calleeName != knownNames.array),
           locals[calleeName] == nil
        {
            let intType = sema.types.intType
            let calleeNameStr = interner.resolve(calleeName)
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            if args.count == 1 {
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
                sema.bindings.markCollectionExpr(id)
                let resultType: TypeID = if calleeNameStr == "Array" {
                    makeSyntheticArrayType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: explicitTypeArgs.first ?? expectedType ?? sema.types.anyType
                    )
                } else {
                    makeSyntheticPrimitiveArrayType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        arrayName: calleeNameStr
                    )
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            // Determine the element type from the expected type annotation or
            // the init lambda's return type, avoiding erasure to Any.
            //
            // Only extract the generic argument from the expected type when:
            //   1. The callee is "Array" (not a primitive array like IntArray), AND
            //   2. The expected type is actually kotlin.Array<...> (not some unrelated
            //      generic type like List<String>).
            // Primitive arrays (IntArray, LongArray, etc.) have fixed element types
            // that must not be overridden by contextual expected types.
            let arrayFQName: [InternedString] = [
                interner.intern("kotlin"),
                interner.intern("Array"),
            ]
            let kotlinArraySymbol = sema.symbols.lookup(fqName: arrayFQName)
            let isKotlinArray = calleeNameStr == "Array"
            let inferLambdaOnce: Bool
            let elementReturnType: TypeID
            if isKotlinArray,
               let explicitTypeArg = explicitTypeArgs.first
            {
                elementReturnType = explicitTypeArg
                inferLambdaOnce = true
            } else if isKotlinArray,
               let kotlinArraySymbol,
               let expectedType, expectedType != sema.types.errorType,
               case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
               expectedClassType.classSymbol == kotlinArraySymbol,
               let firstArg = expectedClassType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    elementReturnType = type
                case .star:
                    elementReturnType = sema.types.anyType
                }
                inferLambdaOnce = true
            } else if isKotlinArray {
                // No expected type and no explicit type argument for Array(size) { init }.
                // Infer the lambda with `it` constrained to Int, then extract the
                // actual body return type from bindings to avoid erasing to Any.
                let lambdaExpected = sema.types.make(.functionType(FunctionType(
                    params: [intType],
                    returnType: sema.types.makeNullable(sema.types.anyType)
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: lambdaExpected
                )
                // Read back the lambda body's actual inferred type.
                let bodyType: TypeID? = if case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(args[1].expr) {
                    sema.bindings.exprTypes[body]
                } else {
                    nil
                }
                let inferred = bodyType ?? sema.types.anyType
                elementReturnType = (inferred != sema.types.errorType) ? inferred : sema.types.anyType
                inferLambdaOnce = false
            } else {
                // For primitive array constructors, the element type is fixed.
                elementReturnType = switch calleeNameStr {
                case "IntArray": sema.types.intType
                case "LongArray": sema.types.longType
                case "ShortArray": sema.types.intType
                case "ByteArray": sema.types.intType
                case "UShortArray": sema.types.ushortType
                case "UByteArray": sema.types.ubyteType
                case "UIntArray": sema.types.uintType
                case "DoubleArray": sema.types.make(.primitive(.double, .nonNull))
                case "FloatArray": sema.types.make(.primitive(.float, .nonNull))
                case "BooleanArray": sema.types.booleanType
                case "CharArray": sema.types.make(.primitive(.char, .nonNull))
                default: sema.types.anyType
                }
                inferLambdaOnce = false
            }
            let initExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: elementReturnType
            )))
            if !inferLambdaOnce {
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: initExpectedType
                )
            }
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .arrayConstructor)
            sema.bindings.markCollectionExpr(id)
            let resultType: TypeID
            if calleeNameStr == "Array" {
                resultType = makeSyntheticArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: elementReturnType
                )
            } else {
                resultType = makeSyntheticPrimitiveArrayType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    arrayName: calleeNameStr
                )
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        if let calleeName,
           args.count == 2,
           interner.resolve(calleeName) == "AtomicIntArray",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(
               calleeName,
               fqComponents: ["kotlin", "concurrent", "atomics", "AtomicIntArray"],
               ctx: ctx
           )
        {
            let intType = sema.types.intType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let initExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: intType
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: initExpectedType
            )
            let resultType = sema.symbols.lookupAll(fqName: [
                interner.intern("kotlin"),
                interner.intern("concurrent"),
                interner.intern("atomics"),
                interner.intern("AtomicIntArray"),
            ]).first(where: { candidate in
                sema.symbols.symbol(candidate)?.kind == .class
            }).map { symbol in
                sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
            } ?? sema.types.anyType
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .atomicIntArrayFactory)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        if let calleeName,
           args.count == 2,
           interner.resolve(calleeName) == "AtomicLongArray",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           isSyntheticStdlibSymbol(
               calleeName,
               fqComponents: ["kotlin", "concurrent", "atomics", "AtomicLongArray"],
               ctx: ctx
           )
        {
            let intType = sema.types.intType
            let longType = sema.types.longType
            let countType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: intType
            )
            driver.emitSubtypeConstraint(
                left: countType,
                right: intType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let initExpectedType = sema.types.make(.functionType(FunctionType(
                params: [intType],
                returnType: longType
            )))
            _ = driver.inferExpr(
                args[1].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: initExpectedType
            )
            let resultType = sema.symbols.lookupAll(fqName: [
                interner.intern("kotlin"),
                interner.intern("concurrent"),
                interner.intern("atomics"),
                interner.intern("AtomicLongArray"),
            ]).first(where: { candidate in
                sema.symbols.symbol(candidate)?.kind == .class
            }).map { symbol in
                sema.types.make(.classType(ClassType(
                    classSymbol: symbol,
                    args: [],
                    nullability: .nonNull
                )))
            } ?? sema.types.anyType
            sema.bindings.markStdlibSpecialCallExpr(id, kind: .atomicLongArrayFactory)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- STDLIB-REFLECT-066: typeOf<T>() — inline reified reflection ---
        if let calleeName,
           args.isEmpty,
           interner.resolve(calleeName) == "typeOf",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            // Resolve the KType return type from the stub.
            let candidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
            if let stubSymbol = candidates.first(where: { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                return signature.reifiedTypeParameterIndices.contains(0)
            }), let signature = sema.symbols.functionSignature(for: stubSymbol) {
                let typeArg = explicitTypeArgs.first ?? sema.types.anyType
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [typeArg],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .typeOf)
                sema.bindings.bindExprType(id, type: signature.returnType)
                return signature.returnType
            }
        }

        // --- Stdlib enumValues<T>() / enumValueOf<T>(name) (STDLIB-171) ---
        if let calleeName,
           let enumSpecialKind = enumStdlibSpecialCallKind(
               calleeName: calleeName,
               args: args,
               explicitTypeArgs: explicitTypeArgs,
               ctx: ctx,
               locals: locals,
               interner: interner,
               sema: sema,
               range: range
           )
        {
            switch enumSpecialKind {
            case let .enumValues(_, arrayType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValues)
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: arrayType)
                return arrayType
            case let .enumValueOf(enumType, stubSymbol):
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.stringType)
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumValueOf)
                sema.bindings.bindExprType(id, type: enumType)
                return enumType
            case let .enumEntries(enumType, entriesType, stubSymbol):
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: stubSymbol,
                        substitutedTypeArguments: [enumType],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(stubSymbol))
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .enumEntries)
                sema.bindings.bindExprType(id, type: entriesType)
                return entriesType
            }
        }

        if let calleeName,
           args.count == 2 || args.count == 3
        {
            // Infer the first argument without an expected type to determine the overload.
            let firstArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: nil
            )

            // Resolve which numeric type this overload targets.
            let supportedNumericTypes = [sema.types.longType, sema.types.doubleType, sema.types.floatType, sema.types.intType]
            if let resolvedParamType = supportedNumericTypes.first(where: { firstArgType == $0 }) {
                var shouldUsePrimitiveComparisonFastPath = true
                if args.count == 3 {
                    var tentativeLocals = locals
                    let secondArgType = driver.inferExpr(
                        args[1].expr,
                        ctx: ctx,
                        locals: &tentativeLocals,
                        expectedType: nil
                    )
                    let thirdArgType = driver.inferExpr(
                        args[2].expr,
                        ctx: ctx,
                        locals: &tentativeLocals,
                        expectedType: nil
                    )
                    shouldUsePrimitiveComparisonFastPath = secondArgType == resolvedParamType && thirdArgType == resolvedParamType
                }

                if shouldUsePrimitiveComparisonFastPath,
                   let specialKind = comparisonSpecialCallKind(
                    for: calleeName,
                    argCount: args.count,
                    resolvedParamType: resolvedParamType,
                    ctx: ctx,
                    locals: locals
                ) {
                    let expectedType = resolvedParamType

                    // Emit subtype constraint for the first argument.
                    driver.emitSubtypeConstraint(
                        left: firstArgType,
                        right: expectedType,
                        range: ast.arena.exprRange(args[0].expr) ?? range,
                        solver: ConstraintSolver(),
                        sema: sema,
                        diagnostics: ctx.semaCtx.diagnostics
                    )

                    // Infer remaining arguments with the resolved type.
                    for i in 1 ..< args.count {
                        let argType = driver.inferExpr(
                            args[i].expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: expectedType
                        )
                        driver.emitSubtypeConstraint(
                            left: argType,
                            right: expectedType,
                            range: ast.arena.exprRange(args[i].expr) ?? range,
                            solver: ConstraintSolver(),
                            sema: sema,
                            diagnostics: ctx.semaCtx.diagnostics
                        )
                    }

                    let paramTypes = Array(repeating: expectedType, count: args.count)
                    let matchingCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible.filter { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else {
                            return false
                        }
                        return signature.parameterTypes == paramTypes
                    }
                    // Prefer the fixed-arity overload over a vararg one declaring the same
                    // parameter types (e.g. minOf(Int, Int) vs minOf(Int, vararg Int)), matching
                    // Kotlin's preference for non-vararg signatures during overload resolution.
                    let chosen = matchingCandidates.first(where: { candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate) else {
                            return false
                        }
                        return !signature.valueParameterIsVararg.contains(true)
                    }) ?? matchingCandidates.first
                    if let chosen,
                       let signature = sema.symbols.functionSignature(for: chosen)
                    {
                        var paramMapping: [Int: Int] = [:]
                        for i in 0 ..< args.count {
                            paramMapping[i] = i
                        }
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [],
                                parameterMapping: paramMapping
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                        sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                        sema.bindings.bindExprType(id, type: signature.returnType)
                        return signature.returnType
                    }
                    sema.bindings.markStdlibSpecialCallExpr(id, kind: specialKind)
                    sema.bindings.bindExprType(id, type: expectedType)
                    return expectedType
                }
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "contract",
           args.count == 1
        {
            let builderSymbol = sema.symbols.lookup(fqName: [
                interner.intern("kotlin"),
                interner.intern("contracts"),
                interner.intern("ContractBuilder"),
            ])
            let builderType = builderSymbol.map {
                sema.types.make(.classType(ClassType(classSymbol: $0, args: [], nullability: .nonNull)))
            } ?? sema.types.anyType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                receiver: builderType,
                params: [],
                returnType: sema.types.unitType
            )))
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx.with(implicitReceiverType: builderType),
                locals: &locals,
                expectedType: lambdaExpectedType
            )
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // --- kotlin.DeepRecursiveFunction<T, R> { ... } ---
        // Infer the block with a DeepRecursiveScope<T, R> implicit receiver so
        // unqualified callRecursive(...) resolves inside the lambda body.
        if let calleeName,
           interner.resolve(calleeName) == "DeepRecursiveFunction",
           args.count == 1
        {
            let functionFQName = [interner.intern("kotlin"), interner.intern("DeepRecursiveFunction")]
            let scopeFQName = [interner.intern("kotlin"), interner.intern("DeepRecursiveScope")]
            let inferredTypeArgs: [TypeID]?
            if explicitTypeArgs.count == 2 {
                inferredTypeArgs = explicitTypeArgs
            } else if let expectedType,
                      let (classType, symbol) = resolveClassTypeSymbol(expectedType, sema: sema),
                      symbol.fqName == functionFQName,
                      classType.args.count == 2
            {
                let unpacked = classType.args.compactMap { arg -> TypeID? in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type):
                        type
                    case .star:
                        nil
                    }
                }
                inferredTypeArgs = unpacked.count == 2 ? unpacked : nil
            } else {
                inferredTypeArgs = nil
            }

            let functionSymbol = sema.symbols.lookup(fqName: functionFQName)
            let scopeSymbol = sema.symbols.lookup(fqName: scopeFQName)
            let ctorSymbol = sema.symbols.lookup(fqName: functionFQName + [interner.intern("<init>")])

            if let typeArgs = inferredTypeArgs,
               let functionSymbol,
               let scopeSymbol,
               let ctorSymbol
            {
                let argumentExprID = args[0].expr
                // DeepRecursiveFunction's block has signature DeepRecursiveScope<T,R>.(T) -> R,
                // so the lambda may declare 0 params (implicit `it`) or 1 explicit param.
                guard isValidLambdaArgument(argumentExprID, ast: ast, maxParams: 1) else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }

                let scopeType = sema.types.make(.classType(ClassType(
                    classSymbol: scopeSymbol,
                    args: [.invariant(typeArgs[0]), .invariant(typeArgs[1])],
                    nullability: .nonNull
                )))
                let resultType = sema.types.make(.classType(ClassType(
                    classSymbol: functionSymbol,
                    args: [.invariant(typeArgs[0]), .invariant(typeArgs[1])],
                    nullability: .nonNull
                )))
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    receiver: scopeType,
                    params: [typeArgs[0]],
                    returnType: typeArgs[1],
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(
                    argumentExprID,
                    ctx: ctx.with(implicitReceiverType: scopeType),
                    locals: &locals,
                    expectedType: lambdaExpectedType
                )
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: ctorSymbol,
                        substitutedTypeArguments: typeArgs,
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(ctorSymbol))
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        // --- compareBy(selector1, selector2, ...) multi-selector overloads (STDLIB-613) ---
        if let calleeName,
           args.count == 2 || args.count == 3,
           interner.resolve(calleeName) == "compareBy",
           args.allSatisfy({ isLambdaOrCallableRefArg($0.expr, ast: ast) }),
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareBy"],
               ctx: ctx
           ) != nil
        {
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            for arg in args {
                sema.bindings.markCollectionHOFLambdaExpr(arg.expr)
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
            }
            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            let expectedExternalLink = args.count == 2
                ? "kk_comparator_from_multi_selectors"
                : "kk_comparator_from_multi_selectors3"
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                return sig.parameterTypes.count == args.count &&
                    sema.symbols.externalLinkName(for: candidate) == expectedExternalLink
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- compareBy/compareByDescending(comparator, selector) (STDLIB-COMP-004/005) ---
        if let calleeName,
           args.count == 2,
           ["compareBy", "compareByDescending"].contains(interner.resolve(calleeName)),
           !isLambdaOrCallableRefArg(args[0].expr, ast: ast),
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", interner.resolve(calleeName)],
               ctx: ctx
           ) != nil
        {
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let keyType: TypeID = if explicitTypeArgs.count >= 2 {
                explicitTypeArgs[1]
            } else {
                sema.types.anyType
            }
            let keyComparatorType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(keyType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: keyComparatorType)

            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: keyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), case .lambdaLiteral = lambdaExpr {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                return sig.parameterTypes.count == 2
                    && sema.symbols.externalLinkName(for: candidate) == nil
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType, keyType],
                        parameterMapping: [0: 0, 1: 1]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- compareBy(vararg selectors) (STDLIB-COMP-006) ---
        if let calleeName,
           args.count >= 4,
           interner.resolve(calleeName) == "compareBy",
           locals[calleeName] == nil,
           sourceOrSyntheticStdlibFunctionSymbol(
               calleeName,
               fqComponents: ["kotlin", "comparisons", "compareBy"],
               ctx: ctx
           ) != nil
        {
            let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                explicitT
            } else if let expectedType,
                      case let .classType(classType) = sema.types.kind(of: expectedType),
                      let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                params: [elementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            for arg in args {
                if let lambdaExpr = ast.arena.expr(arg.expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(arg.expr)
                }
                _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
            }

            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
            let resultType: TypeID = if let comparatorSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(elementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }

            let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
            let funcFQName = comparisonsPkg + [calleeName]
            if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                sema.symbols.externalLinkName(for: candidate) == "kk_comparator_from_multi_selectors_vararg"
            }) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // --- Comparator factory functions: compareBy, compareByDescending (STDLIB-649) ---
        if let calleeName,
           args.count == 1,
           locals[calleeName] == nil
        {
            let calleeNameStr = interner.resolve(calleeName)
            if (calleeNameStr == "compareBy" || calleeNameStr == "compareByDescending"),
               sourceOrSyntheticStdlibFunctionSymbol(
                   calleeName,
                   fqComponents: ["kotlin", "comparisons", calleeNameStr],
                   ctx: ctx
               ) != nil {
                // Resolve the Comparator<T> return type.
                // The lambda selector has signature (T) -> Comparable<*>.
                // T is inferred from explicit type args, calling context, or defaults to Any.
                let elementType: TypeID = if let explicitT = explicitTypeArgs.first {
                    explicitT
                } else if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: sema.types.nullableAnyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                // Bind to the bundled Kotlin source symbol.
                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.count == 1
                        && sig.valueParameterIsVararg != [true]
                        && sema.symbols.externalLinkName(for: candidate) == nil
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        // --- Comparator factory functions: naturalOrder, reverseOrder (STDLIB-649) ---
        if let calleeName,
           args.isEmpty,
           locals[calleeName] == nil
        {
            let calleeNameStr = interner.resolve(calleeName)
            if (calleeNameStr == "naturalOrder" || calleeNameStr == "reverseOrder"),
               sourceOrSyntheticStdlibFunctionSymbol(
                   calleeName,
                   fqComponents: ["kotlin", "comparisons", calleeNameStr],
                   ctx: ctx
               ) != nil {
                let elementType: TypeID = if let explicitTypeArg = explicitTypeArgs.first {
                    explicitTypeArg
                } else if let expectedType,
                    case let .classType(classType) = sema.types.kind(of: expectedType),
                    let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }

                let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName)
                let resultType: TypeID = if let comparatorSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }

                let comparisonsPkg: [InternedString] = [interner.intern("kotlin"), interner.intern("comparisons")]
                let funcFQName = comparisonsPkg + [calleeName]
                if let chosen = sema.symbols.lookupAll(fqName: funcFQName).first(where: { candidate in
                    guard let sig = sema.symbols.functionSignature(for: candidate) else { return false }
                    return sig.parameterTypes.isEmpty
                        && sema.symbols.externalLinkName(for: candidate) == nil
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: [:]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        if let calleeName,
           calleeName == knownNames.channel,
           args.isEmpty
        {
            let visibleCandidates = ctx.cachedScopeLookup(calleeName)
            let channelSymbol = visibleCandidates.first { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function
                else {
                    return false
                }
                return sema.symbols.externalLinkName(for: candidate) == "kk_channel_create"
            } ?? visibleCandidates.compactMap { candidate -> SymbolID? in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .class,
                      sema.symbols.externalLinkName(for: candidate) == nil
                else {
                    return nil
                }
                let ctorFQName = symbol.fqName + [interner.intern("<init>")]
                return sema.symbols.lookupAll(fqName: ctorFQName).first { ctorID in
                    sema.symbols.externalLinkName(for: ctorID) == "kk_channel_create"
                }
            }.first
            if let channelSymbol {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: channelSymbol,
                        substitutedTypeArguments: explicitTypeArgs,
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(channelSymbol))
                let resultType: TypeID = if let explicitTypeArg = explicitTypeArgs.first,
                                            let signature = sema.symbols.functionSignature(for: channelSymbol),
                                            case let .classType(classType) = sema.types.kind(of: signature.returnType)
                {
                    sema.types.make(.classType(ClassType(
                        classSymbol: classType.classSymbol,
                        args: [.invariant(explicitTypeArg)],
                        nullability: classType.nullability
                    )))
                } else {
                    sema.symbols.functionSignature(for: channelSymbol)?.returnType ?? sema.types.anyType
                }
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "delay",
           args.count == 1
        {
            let delayArgType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.longType
            )
            if delayArgType == sema.types.intType,
               let argumentExpr = ast.arena.expr(args[0].expr),
               case .intLiteral = argumentExpr
            {
                sema.bindings.bindExprType(args[0].expr, type: sema.types.longType)
            } else {
                driver.emitSubtypeConstraint(
                    left: delayArgType,
                    right: sema.types.longType,
                    range: ast.arena.exprRange(args[0].expr) ?? range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        let coroutineLauncherName = calleeName.map { interner.resolve($0) }
        let coroutineLauncherExpectedLambdaType: TypeID?
        // STDLIB-CORO-072: Support launch(dispatcher) { } by checking both first and
        // second argument for a trailing lambda. When the first argument is a dispatcher
        // (non-lambda) and the second is a lambda, treat it as the block argument.
        let coroutineLauncherLambdaArgIndex: Int? = {
            guard let name = coroutineLauncherName,
                  ["runBlocking", "launch", "async", "coroutineScope", "supervisorScope"].contains(name)
            else { return nil }
            if let firstArgExpr = args.first.flatMap({ ast.arena.expr($0.expr) }),
               case .lambdaLiteral = firstArgExpr {
                return 0
            }
            if args.count >= 2,
               let secondArgExpr = ast.arena.expr(args[1].expr),
               case .lambdaLiteral = secondArgExpr {
                return 1
            }
            return nil
        }()
        if let coroutineLauncherName,
           let lambdaIndex = coroutineLauncherLambdaArgIndex,
           lambdaIndex < args.count
        {
            let lambdaReturnType: TypeID = switch coroutineLauncherName {
            case "launch":
                sema.types.unitType
            default:
                expectedType ?? sema.types.anyType
            }
            coroutineLauncherExpectedLambdaType = sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: lambdaReturnType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            coroutineLauncherExpectedLambdaType = nil
        }
        let withContextExpectedLambdaType: TypeID? = if let calleeName,
                                                        calleeName == knownNames.withContext
                                                            || calleeName == knownNames.withTimeout
                                                            || calleeName == knownNames.withTimeoutOrNull,
                                                        args.count >= 2,
                                                        let secondArgExpr = ast.arena.expr(args[1].expr),
                                                        case .lambdaLiteral = secondArgExpr
        {
            sema.types.make(.functionType(FunctionType(
                params: [],
                returnType: expectedType ?? sema.types.anyType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            nil
        }

        if let calleeName,
           let samCallType = inferSamConvertedCallExpr(
               id,
               calleeName: calleeName,
               args: args,
               range: range,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs
           )
        {
            sema.bindings.bindExprType(id, type: samCallType)
            return samCallType
        }

        var candidates: [SymbolID]
        var callInvisible: [SemanticSymbol] = []
        if let calleeName {
            let allCallCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            // @DslMarker restriction: filter out candidates that belong to an
            // outer receiver class that shares a DslMarker annotation with the
            // current implicit receiver.
            let dslBlockedCandidates = allCallCandidates.filter { ctx.isCandidateBlockedByDslMarker($0) }
            let dslFiltered = allCallCandidates.filter { !ctx.isCandidateBlockedByDslMarker($0) }
            let (vis, invis) = ctx.filterByVisibility(dslFiltered)
            candidates = vis
            callInvisible = invis
            // If all candidates were blocked by DslMarker, emit a specific diagnostic.
            if candidates.isEmpty, !dslBlockedCandidates.isEmpty {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-DSLMARKER",
                    "'@DslMarker' implicit access to '\(interner.resolve(calleeName))' from outer receiver is restricted. Use explicit receiver.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            var resolvedFromLocalShadow = false
            if candidates.isEmpty, let local = locals[calleeName] {
                if let sym = ctx.cachedSymbol(local.symbol), sym.kind == .function {
                    candidates = [local.symbol]
                    resolvedFromLocalShadow = true
                }
            }
            // KSP-CAP-006: a class/enum/annotation-class/object may coexist
            // with a top-level function of the same name (e.g. `class Random`
            // + top-level `fun Random(seed: Long): Random`, the real
            // kotlin-stdlib factory-function idiom). Merge that type's
            // constructors into the candidate set instead of only using them
            // as an empty-candidates fallback, so overload resolution can
            // choose between the function(s) and the constructor(s) by
            // argument type -- the same way it already does between two
            // overloaded functions of the same name. Skipped when a local
            // variable already shadows the name (resolvedFromLocalShadow).
            if !resolvedFromLocalShadow {
                let classSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass || symbol.kind == .annotationClass || symbol.kind == .object
                }
                if let classSym = classSymbols.first, let classSymbol = ctx.cachedSymbol(classSym) {
                    if classSymbol.flags.contains(.abstractType) {
                        // P5-112: Prohibit direct instantiation of abstract classes,
                        // but only when there is no other viable candidate (e.g. a
                        // coexisting top-level factory function): an abstract
                        // class's own constructor is never itself a usable call
                        // target, so it must not blot out a real candidate.
                        if candidates.isEmpty {
                            let className = classSymbol.fqName.map { interner.resolve($0) }.joined(separator: ".")
                            ctx.semaCtx.diagnostics.error(
                                "KSWIFTK-SEMA-ABSTRACT",
                                "Cannot create an instance of abstract class '\(className)'.",
                                range: range
                            )
                            sema.bindings.bindExprType(id, type: sema.types.errorType)
                            return sema.types.errorType
                        }
                    } else {
                        let initName = interner.intern("<init>")
                        let ctorFQName = classSymbol.fqName + [initName]
                        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                        if !ctorSymbols.isEmpty {
                            let (ctorVis, ctorInvis) = ctx.filterByVisibility(ctorSymbols)
                            // Some synthetic stdlib types register a class
                            // constructor whose signature exactly duplicates a
                            // coexisting top-level factory function's signature
                            // (e.g. kotlin.io.path.Path's synthetic
                            // `<init>(String)` alongside the top-level `fun
                            // Path(pathString: String): Path`). Without this
                            // filter the duplicate becomes a second,
                            // indistinguishable overload candidate and every
                            // call to that name falsely resolves as ambiguous.
                            let newCtorVis = ctorVis.filter { ctorID in
                                guard let ctorSignature = sema.symbols.functionSignature(for: ctorID) else {
                                    return true
                                }
                                return !candidates.contains { existingID in
                                    sema.symbols.functionSignature(for: existingID)?.parameterTypes == ctorSignature.parameterTypes
                                }
                            }
                            candidates.append(contentsOf: newCtorVis)
                            callInvisible.append(contentsOf: ctorInvis)
                        }
                    }
                }
            }
            if candidates.isEmpty,
               calleeName == knownNames.suspendCoroutine,
               let suspendCoroutineSymbol = sema.symbols.lookup(fqName: knownNames.kotlinSuspendCoroutineFQName) {
                candidates = [suspendCoroutineSymbol]
            }
            // --- Typealias constructor calls ---
            // If the callee is a typealias (e.g. `typealias IntPair = Pair<Int, Int>`),
            // expand it to the underlying class and resolve its constructor.
            if candidates.isEmpty {
                let aliasSymbols = ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .typeAlias
                }
                if let aliasSym = aliasSymbols.first {
                    let aliasTypeParameters = sema.symbols.typeAliasTypeParameters(for: aliasSym)
                    let aliasTypeArgs: [TypeArg] = if !explicitTypeArgs.isEmpty {
                        explicitTypeArgs.map { TypeArg.invariant($0) }
                    } else if !aliasTypeParameters.isEmpty,
                              let expectedType,
                              case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
                    {
                        Array(expectedClassType.args.prefix(aliasTypeParameters.count))
                    } else if !aliasTypeParameters.isEmpty {
                        Array(repeating: TypeArg.invariant(sema.types.anyType), count: aliasTypeParameters.count)
                    } else {
                        []
                    }
                    if let expanded = driver.helpers.expandTypeAlias(
                        aliasSym,
                        typeArgs: aliasTypeArgs,
                        sema: sema,
                        visited: [],
                        depth: 0,
                        diagnostics: ctx.semaCtx.diagnostics
                    ),
                       case let .classType(classType) = sema.types.kind(of: expanded),
                       let underlyingSymbol = ctx.cachedSymbol(classType.classSymbol)
                    {
                        let initName = interner.intern("<init>")
                        let ctorFQName = underlyingSymbol.fqName + [initName]
                        let ctorSymbols = sema.symbols.lookupAll(fqName: ctorFQName)
                        if !ctorSymbols.isEmpty {
                            let (vis, invis) = ctx.filterByVisibility(ctorSymbols)
                            candidates = vis
                            callInvisible.append(contentsOf: invis)
                        }
                    }
                }
            }
        } else if let calleePath, calleePath.count > 1 {
            // FQN call: e.g. kotlin.math.abs(x) — look up directly by fully qualified name
            let fqnCandidates = sema.symbols.lookupAll(fqName: calleePath).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
            let (vis, invis) = ctx.filterByVisibility(fqnCandidates)
            candidates = vis
            callInvisible.append(contentsOf: invis)
        } else {
            candidates = []
        }

        if let calleeName,
           interner.resolve(calleeName) == "callRecursive",
           args.count == 1,
           let receiverType = ctx.implicitReceiverType,
           let (scopeClass, scopeSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
           scopeSymbol.fqName.count == 2,
           interner.resolve(scopeSymbol.fqName[0]) == "kotlin",
           interner.resolve(scopeSymbol.fqName[1]) == "DeepRecursiveScope",
           scopeClass.args.count == 2
        {
            let inputType: TypeID?
            let returnType: TypeID?
            switch (scopeClass.args[0], scopeClass.args[1]) {
            case let (.invariant(input), .invariant(output)):
                inputType = input
                returnType = output
            case let (.out(input), .out(output)):
                inputType = input
                returnType = output
            case let (.out(input), .invariant(output)):
                inputType = input
                returnType = output
            case let (.invariant(input), .out(output)):
                inputType = input
                returnType = output
            default:
                inputType = nil
                returnType = nil
            }
            if let inputType, let returnType {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: inputType)
                let fqName = [interner.intern("kotlin"), interner.intern("DeepRecursiveScope"), interner.intern("callRecursive")]
                if let chosen = sema.symbols.lookupAll(fqName: fqName).first(where: { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                        return false
                    }
                    return signature.typeParameterSymbols.count == signature.classTypeParameterCount
                        && sema.symbols.externalLinkName(for: symbolID) == "kk_deep_recursive_scope_callRecursive"
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [inputType, returnType],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "compareValuesBy",
           args.count == 4 || args.count >= 6,
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx)
        {
            let firstType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let secondType = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
            let comparatorArgType = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals)
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                let nonNullComparatorArgType = sema.types.makeNonNullable(comparatorArgType)
                let inferredKeyType: TypeID? = if case let .classType(classType) = sema.types.kind(of: nonNullComparatorArgType),
                                                  classType.classSymbol == comparatorSymbol,
                                                  let firstArg = classType.args.first
                {
                    switch firstArg {
                    case let .invariant(type), let .out(type), let .in(type): type
                    case .star: sema.types.anyType
                    }
                } else {
                    nil
                }

                if let inferredKeyType {
                    let elementCandidates = [firstType, secondType].filter { $0 != sema.types.errorType }.map {
                        sema.types.makeNonNullable($0)
                    }
                    let elementType = explicitTypeArgs.first
                        ?? (elementCandidates.isEmpty ? sema.types.anyType : sema.types.lub(elementCandidates))
                    let keyType = explicitTypeArgs.count >= 2 ? explicitTypeArgs[1] : inferredKeyType
                    let comparatorType = sema.types.make(.classType(ClassType(
                        classSymbol: comparatorSymbol,
                        args: [.invariant(keyType)],
                        nullability: .nonNull
                    )))
                    let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [elementType],
                        returnType: keyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: comparatorType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[3].expr)
                    _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)

                    if let chosen = candidates.first(where: { candidate in
                        sema.symbols.externalLinkName(for: candidate) == "kk_compareValuesByComparator"
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [elementType, keyType],
                                parameterMapping: [0: 0, 1: 1, 2: 2, 3: 3]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
            }
            if args.count >= 6 {
                let elementCandidates = [firstType, secondType].filter { $0 != sema.types.errorType }.map {
                    sema.types.makeNonNullable($0)
                }
                let elementType = explicitTypeArgs.first
                    ?? (elementCandidates.isEmpty ? sema.types.anyType : sema.types.lub(elementCandidates))
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                for index in 2..<args.count {
                    sema.bindings.markCollectionHOFLambdaExpr(args[index].expr)
                    _ = driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
                }

                if let chosen = candidates.first(where: { candidate in
                    sema.symbols.externalLinkName(for: candidate) == "kk_compareValuesByVararg"
                }) {
                    var mapping: [Int: Int] = [0: 0, 1: 1]
                    for index in 2..<args.count {
                        mapping[index] = 2
                    }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [elementType],
                            parameterMapping: mapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                }
                sema.bindings.bindExprType(id, type: sema.types.intType)
                return sema.types.intType
            }
        }

        var expectedTypeOverrides: [Int: TypeID] = [:]
        if let launcherIndex = coroutineLauncherLambdaArgIndex,
           let coroutineLauncherExpectedLambdaType
        {
            expectedTypeOverrides[launcherIndex] = coroutineLauncherExpectedLambdaType
        }
        if let withContextExpectedLambdaType, args.count > 1 {
            expectedTypeOverrides[1] = withContextExpectedLambdaType
        }
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            expectedTypeOverrides: expectedTypeOverrides,
            explicitTypeArgs: explicitTypeArgs,
            ctx: ctx,
            locals: &locals
        )
        let argTypes = preparedArgs.argTypes

        func sourceBackedCollectionFactoryType(
            name: String
        ) -> (type: TypeID, typeArgs: [TypeID])? {
            func typeArgs(from type: TypeID) -> [TypeID] {
                guard case let .classType(classType) = sema.types.kind(of: type) else {
                    return []
                }
                return classType.args.map { arg in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type):
                        type
                    case .star:
                        sema.types.anyType
                    }
                }
            }

            func expectedCollectionType(withArity arity: Int) -> TypeID? {
                guard let expectedType,
                      expectedType != sema.types.errorType,
                      case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                      expectedClassType.args.count >= arity
                else {
                    return nil
                }
                return expectedType
            }

            switch name {
            case "emptyList", "listOf", "listOfNotNull", "mutableListOf", "arrayListOf":
                if let expectedType = expectedCollectionType(withArity: 1) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let elementTypes = name == "listOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let elementType = explicitTypeArgs.first
                    ?? (elementTypes.isEmpty ? sema.types.nothingType : sema.types.lub(elementTypes))
                let resultType = name == "mutableListOf" || name == "arrayListOf"
                    ? makeSyntheticMutableListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                    : makeSyntheticListType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                return (resultType, [elementType])

            case "emptySet", "setOf", "setOfNotNull", "mutableSetOf", "hashSetOf", "linkedSetOf":
                if let expectedType = expectedCollectionType(withArity: 1) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let elementTypes = name == "setOfNotNull"
                    ? argTypes.compactMap { type -> TypeID? in
                        type == sema.types.nullableNothingType ? nil : sema.types.makeNonNullable(type)
                    }
                    : argTypes
                let elementType = explicitTypeArgs.first
                    ?? (elementTypes.isEmpty ? sema.types.nothingType : sema.types.lub(elementTypes))
                let resultType: TypeID
                if name == "linkedSetOf" {
                    resultType = makeSyntheticLinkedHashSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else if name == "mutableSetOf" || name == "hashSetOf" {
                    resultType = makeSyntheticMutableSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                } else {
                    resultType = makeSyntheticSetType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: elementType
                    )
                }
                return (resultType, [elementType])

            case "emptyMap", "mapOf", "mutableMapOf", "hashMapOf", "linkedMapOf":
                if let expectedType = expectedCollectionType(withArity: 2) {
                    return (expectedType, typeArgs(from: expectedType))
                }
                let keyType: TypeID
                let valueType: TypeID
                if explicitTypeArgs.count == 2 {
                    keyType = explicitTypeArgs[0]
                    valueType = explicitTypeArgs[1]
                } else if let inferred = inferSyntheticMapKeyValueTypes(from: args, ctx: ctx, locals: &locals) {
                    keyType = inferred.keyType
                    valueType = inferred.valueType
                } else {
                    keyType = sema.types.nothingType
                    valueType = sema.types.nothingType
                }
                let resultType = name == "mapOf" || name == "emptyMap"
                    ? makeSyntheticMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                    : makeSyntheticMutableMapType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        keyType: keyType,
                        valueType: valueType
                    )
                return (resultType, [keyType, valueType])

            default:
                return nil
            }
        }

        func isKotlinCollectionsFactorySymbol(_ symbol: SemanticSymbol, named name: InternedString) -> Bool {
            guard symbol.kind == .function,
                  symbol.name == name,
                  symbol.fqName.count >= 3
            else {
                return false
            }
            return interner.resolve(symbol.fqName[0]) == "kotlin"
                && interner.resolve(symbol.fqName[1]) == "collections"
        }

        func hasNonStdlibCollectionFactoryShadow(
            _ name: InternedString,
            locals: LocalBindings,
            ctx: TypeInferenceContext
        ) -> Bool {
            if locals[name] != nil {
                return true
            }
            return ctx.cachedScopeLookup(name).contains { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      !symbol.flags.contains(.synthetic)
                else {
                    return false
                }
                return !isKotlinCollectionsFactorySymbol(symbol, named: name)
            }
        }

        if let calleeName {
            let resolvedName = interner.resolve(calleeName)
            if let sourceBackedFactory = sourceBackedCollectionFactoryType(name: resolvedName),
               !hasNonStdlibCollectionFactoryShadow(calleeName, locals: locals, ctx: ctx),
               let chosen = candidates.first(where: { candidate in
                   guard let symbol = ctx.cachedSymbol(candidate) else {
                       return false
                   }
                   guard isKotlinCollectionsFactorySymbol(symbol, named: calleeName) else {
                       return false
                   }
                   return args.isEmpty || (sema.symbols.functionSignature(for: candidate)?.parameterTypes.isEmpty == false)
               })
            {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: sourceBackedFactory.typeArgs,
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, 0) })
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: sourceBackedFactory.type)
                return sourceBackedFactory.type
            }

            // Type aliases and concrete collection classes are represented by
            // synthetic type symbols rather than source-backed factory
            // functions. Keep their constructor typing available while the
            // bundled stdlib is bootstrapped; CollectionLiteralLoweringPass
            // rewrites the resulting calls to the matching runtime bridge.
            let expectedCollectionArgs: [TypeID] = if let expectedType,
                                                       expectedType != sema.types.errorType,
                                                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
            {
                expectedClassType.args.map { arg in
                    switch arg {
                    case let .invariant(type), let .in(type), let .out(type): type
                    case .star: sema.types.anyType
                    }
                }
            } else {
                []
            }
            let constructorElementType = explicitTypeArgs.first
                ?? expectedCollectionArgs.first
                ?? sema.types.anyType
            switch resolvedName {
            case "ArrayList":
                let resultType = makeSyntheticListConstructorType(
                    name: resolvedName,
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "HashSet":
                let resultType = makeSyntheticMutableSetType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "LinkedHashSet":
                let resultType = makeSyntheticLinkedHashSetType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: constructorElementType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            case "HashMap", "LinkedHashMap":
                let keyType = explicitTypeArgs.first ?? expectedCollectionArgs.first ?? sema.types.anyType
                let valueType = explicitTypeArgs.dropFirst().first
                    ?? expectedCollectionArgs.dropFirst().first
                    ?? sema.types.anyType
                let resultType = makeSyntheticMutableMapType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    keyType: keyType,
                    valueType: valueType
                )
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            default:
                break
            }
        }

        if let calleeName,
           interner.resolve(calleeName) == "LinkedHashSet",
           args.isEmpty,
           explicitTypeArgs.isEmpty,
           let expectedType,
           expectedType != sema.types.errorType,
           case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
           expectedClassType.args.count == 1,
           let expectedSymbol = ctx.cachedSymbol(expectedClassType.classSymbol),
           knownNames.isMutableSetSymbol(expectedSymbol),
           let chosen = candidates.first(where: { candidate in
               guard let symbol = ctx.cachedSymbol(candidate),
                     symbol.kind == .constructor,
                     sema.symbols.externalLinkName(for: candidate) == "kk_emptySet",
                     let parent = sema.symbols.parentSymbol(for: candidate),
                     let parentSymbol = ctx.cachedSymbol(parent)
               else {
                   return false
               }
               return parentSymbol.name == interner.intern("LinkedHashSet")
           })
        {
            let elementType = driver.helpers.typeArgInnerTypeForCheck(expectedClassType.args[0])
            if elementType != TypeID.invalid {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: [elementType],
                        parameterMapping: [:]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                sema.bindings.markCollectionExpr(id)
                sema.bindings.bindExprType(id, type: expectedType)
                return expectedType
            }
        }
        if let calleeName,
           interner.resolve(calleeName) == "atomicArrayOf",
           !isShadowedByNonSyntheticSymbol(calleeName, locals: locals, ctx: ctx),
           let chosen = candidates.first(where: { candidate in
               sema.symbols.externalLinkName(for: candidate) == "kk_atomic_ref_array_of"
           }),
           let atomicArraySymbol = sema.symbols.lookup(fqName: [
               interner.intern("kotlin"),
               interner.intern("concurrent"),
               interner.intern("atomics"),
               interner.intern("AtomicArray"),
           ])
        {
            let expectedElementType: TypeID? = if let expectedType,
                                                  expectedType != sema.types.errorType,
                                                  case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                                                  expectedClassType.classSymbol == atomicArraySymbol,
                                                  let firstArg = expectedClassType.args.first
            {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                nil
            }
            func arrayElementType(from type: TypeID) -> TypeID {
                let nonNullType = sema.types.makeNonNullable(type)
                guard let (classType, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema),
                      symbol.name == knownNames.array,
                      let firstArg = classType.args.first
                else {
                    return sema.types.anyType
                }
                return switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            }
            let argumentElementTypes = zip(args, argTypes).map { argument, type in
                argument.isSpread ? arrayElementType(from: type) : type
            }
            let inferredElementType: TypeID
            if let explicitTypeArg = explicitTypeArgs.first {
                inferredElementType = explicitTypeArg
            } else if let expectedElementType {
                inferredElementType = expectedElementType
            } else if !argumentElementTypes.isEmpty {
                let lub = sema.types.lub(argumentElementTypes)
                inferredElementType = lub == sema.types.errorType ? sema.types.anyType : lub
            } else {
                inferredElementType = sema.types.anyType
            }
            let returnType = sema.types.make(.classType(ClassType(
                classSymbol: atomicArraySymbol,
                args: [.invariant(inferredElementType)],
                nullability: .nonNull
            )))
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: sema,
                interner: interner,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: [inferredElementType],
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, 0) })
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            sema.bindings.bindExprType(id, type: returnType)
            return returnType
        }
        if !candidates.isEmpty {
            // STDLIB-CORO-BUG-02: withContext is registered with a hardcoded
            // Any return type (see HeaderHelpers+SyntheticCoroutineRegistry.swift)
            // rather than made generic over the block's return type, because a
            // real type parameter there hangs the constraint solver. When the
            // call site
            // has a concrete expectedType (e.g. a declared function return
            // type), Any fails the return-type-vs-expectedType compatibility
            // check and every candidate is rejected ("no viable overload").
            // Resolve with expectedType relaxed to nil instead -- the same path
            // already picks the right overload correctly via argument matching
            // when there is no expected type -- then restore expectedType as
            // the call's result type below. The lambda body itself was already
            // checked against expectedType via coroutineLauncherExpectedLambdaType
            // / withContextExpectedLambdaType above.
            //
            // Matched by FQName + the synthetic flag (not just the short name)
            // so a user-defined function that happens to also be named
            // "withContext" doesn't get its return type silently overridden --
            // registerSyntheticCoroutineTopLevelFunction doesn't set an
            // externalLinkName for withContext (the runtime callee swap happens
            // later, in CoroutineLoweringPass, purely by name), so externalLinkName
            // isn't available here to disambiguate instead.
            let coroutinesWithContextFQName = [
                interner.intern("kotlinx"), interner.intern("coroutines"), interner.intern("withContext"),
            ]
            let isCoroutineBuilderWithHardcodedAnyReturn = !candidates.isEmpty && candidates.allSatisfy { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.flags.contains(.synthetic) && symbol.fqName == coroutinesWithContextFQName
            }
            let resolved = resolveCallRespectingLambdaReturnType(
                candidates: candidates,
                args: args,
                argTypes: argTypes,
                range: range,
                calleeName: calleeName ?? InternedString(),
                explicitTypeArgs: explicitTypeArgs,
                expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                ctx: ctx
            )
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0023",
                    "Unresolved function '\(nameStr)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            // ANNO-001: Check for @Deprecated annotation on the resolved callee.
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: sema,
                interner: interner,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            var adjustedReturnType: TypeID = if let coroutineLauncherName,
                let launcherIndex = coroutineLauncherLambdaArgIndex,
                ["async", "coroutineScope", "supervisorScope"].contains(coroutineLauncherName),
                args.indices.contains(launcherIndex)
            {
                coroutineBuilderNarrowedReturnType(
                    id: id,
                    launcherName: coroutineLauncherName,
                    lambdaArgExpr: args[launcherIndex].expr,
                    fallback: returnType,
                    ast: ast,
                    sema: sema
                )
            } else if let externalLinkName = sema.symbols.externalLinkName(for: chosen) {
                switch externalLinkName {
                case "kk_emptyList":
                    if let expectedType, expectedType != sema.types.errorType,
                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                       !expectedClassType.args.isEmpty
                    {
                        expectedType
                    } else if let explicitTypeArg = explicitTypeArgs.first,
                              let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                    {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.out(explicitTypeArg)],
                            nullability: .nonNull
                        )))
                    } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.out(sema.types.nothingType)],
                            nullability: .nonNull
                        )))
                    } else {
                        returnType
                    }

                case "kk_emptySet":
                    if let expectedType, expectedType != sema.types.errorType,
                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                       !expectedClassType.args.isEmpty
                    {
                        expectedType
                    } else if let explicitTypeArg = explicitTypeArgs.first,
                              let setSymbol = sema.symbols.lookupByShortName(interner.intern("Set")).first
                    {
                        sema.types.make(.classType(ClassType(
                            classSymbol: setSymbol,
                            args: [.out(explicitTypeArg)],
                            nullability: .nonNull
                        )))
                    } else if let setSymbol = sema.symbols.lookupByShortName(interner.intern("Set")).first {
                        sema.types.make(.classType(ClassType(
                            classSymbol: setSymbol,
                            args: [.out(sema.types.nothingType)],
                            nullability: .nonNull
                        )))
                    } else {
                        returnType
                    }

                case "kk_emptyMap":
                    if let expectedType, expectedType != sema.types.errorType,
                       case let .classType(expectedClassType) = sema.types.kind(of: expectedType),
                       expectedClassType.args.count == 2
                    {
                        expectedType
                    } else if explicitTypeArgs.count == 2,
                              let mapSymbol = sema.symbols.lookupByShortName(interner.intern("Map")).first
                    {
                        sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(explicitTypeArgs[0]), .out(explicitTypeArgs[1])],
                            nullability: .nonNull
                        )))
                    } else if let mapSymbol = sema.symbols.lookupByShortName(interner.intern("Map")).first {
                        sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(sema.types.nothingType), .out(sema.types.nothingType)],
                            nullability: .nonNull
                        )))
                    } else {
                        returnType
                    }

                default:
                    returnType
                }
            } else {
                returnType
            }
            // STDLIB-CORO-BUG-02: restore the real expectedType as the result
            // of withContext calls -- see the matching comment above
            // resolveCallRespectingLambdaReturnType.
            if isCoroutineBuilderWithHardcodedAnyReturn,
               let expectedType, expectedType != sema.types.errorType
            {
                adjustedReturnType = expectedType
            }
            if args.count == 2,
               let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               ["kk_require_lazy", "kk_check_lazy", "kk_precondition_assert_lazy"].contains(externalLinkName)
            {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            applyContractEffects(
                chosen: chosen,
                args: args,
                argTypes: argTypes,
                ctx: ctx,
                locals: &locals
            )
            if let calleeName {
                let resolvedName = interner.resolve(calleeName)
                if KnownCompilerNames.stdlibCollectionFactoryNames.contains(resolvedName),
                   !KnownCompilerNames.arrayFactoryFunctionNames.contains(resolvedName)
                {
                    sema.bindings.markCollectionExpr(id)
                }
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               [
                   "kk_op_rangeTo",
                   "kk_op_rangeUntil",
                   "kk_uint_rangeTo",
                   "kk_char_rangeTo",
                   "kk_int_progression_fromClosedRange",
                   "kk_long_progression_fromClosedRange",
                   "kk_uint_progression_fromClosedRange",
                   "kk_ulong_progression_fromClosedRange",
                   "kk_op_ulong_rangeUntil",
               ].contains(externalLinkName)
            {
                markRangeCallBindings(id, chosen: chosen, returnType: adjustedReturnType, sema: sema)
            }
            sema.bindings.bindExprType(id, type: adjustedReturnType)
            return adjustedReturnType
        }

        var callableTarget: CallableTarget?
        var callableCalleeType: TypeID?
        if let calleeName,
           let local = locals[calleeName]
        {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(calleeName))' must be initialized before use.",
                    range: range
                )
            }
            sema.bindings.bindIdentifier(calleeID, symbol: local.symbol)
            sema.bindings.bindExprType(calleeID, type: local.type)
            let localSymbolKind = ctx.cachedSymbol(local.symbol)?.kind
            if localSymbolKind != .function {
                callableTarget = .localValue(local.symbol)
                callableCalleeType = local.type
            }
        } else if let calleeName {
            if !ctx.cachedScopeLookup(calleeName).isEmpty {
                callableCalleeType = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: nil
                )
                callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
            }
        } else if calleeName == nil {
            let contextualCalleeType: TypeID?
            if let calleeExpr {
                switch calleeExpr {
                case .lambdaLiteral, .callableRef:
                    let contextualReturnType = expectedType ?? sema.types.anyType
                    contextualCalleeType = sema.types.make(.functionType(FunctionType(
                        params: argTypes,
                        returnType: contextualReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                default:
                    contextualCalleeType = nil
                }
            } else {
                contextualCalleeType = nil
            }
            callableCalleeType = driver.inferExpr(
                calleeID,
                ctx: ctx,
                locals: &locals,
                expectedType: contextualCalleeType
            )
            callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
        }

        if callableCalleeType == sema.types.errorType {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        if let callableCalleeType,
           let result = inferCallableValueInvocation(
               id, calleeType: callableCalleeType, callableTarget: callableTarget,
               args: args, argTypes: argTypes, range: range, ctx: ctx, expectedType: expectedType
           )
        {
            return result
        }

        // Invoke operator fallback: if callee is not a function type, check if
        // its type has an `operator fun invoke(...)` member and resolve through
        // the overload resolver as a member call.
        if let callableCalleeType {
            let invokeName = interner.intern("invoke")
            let invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: invokeName,
                receiverType: callableCalleeType,
                sema: sema,
                interner: interner
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            if !invokeCandidates.isEmpty {
                let resolvedArgs = zip(args, argTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                let resolved = ctx.resolver.resolveCall(
                    candidates: invokeCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: invokeName,
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: callableCalleeType,
                    ctx: ctx.semaCtx
                )
                if let diagnostic = resolved.diagnostic {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if let chosen = resolved.chosenCallee {
                    let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                    applyContractEffects(
                        chosen: chosen,
                        args: args,
                        argTypes: argTypes,
                        ctx: ctx,
                        locals: &locals
                    )
                    sema.bindings.markInvokeOperatorCall(id)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
            }
        }

        if let builtinType = driver.helpers.kxMiniCoroutineBuiltinReturnType(
            calleeName: calleeName,
            argumentCount: args.count,
            sema: sema,
            interner: interner
        ) {
            sema.bindings.bindExprType(id, type: builtinType)
            return builtinType
        }
        // Builder DSL member functions (STDLIB-002).
        // Inside builder lambdas, unqualified `append`/`add`/`put` resolve as
        // implicit-receiver member calls that return Unit.
        if let calleeName, ctx.isBuilderLambdaScope, let activeBuilderKind = ctx.builderKind {
            let name = interner.resolve(calleeName)
            let isBuilderMember: Bool = switch activeBuilderKind {
            case .buildString, .buildStringBuilder:
                (name == "append" && args.count == 1)
                    || (name == "appendLine" && args.count <= 1)
                    || (name == "appendRange" && args.count == 3)
            case .buildList, .buildSet:
                (name == "add" && args.count == 1) || (name == "addAll" && args.count == 1)
            case .buildMap: name == "put" && args.count == 2
            }
            if isBuilderMember {
                for argument in args {
                    _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                sema.bindings.markBuilderDSLExpr(id, kind: activeBuilderKind)
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }
        // STDLIB-004: Inside receiver lambdas (run/apply/with), unqualified
        // function calls resolve as member calls on the implicit receiver.
        if let calleeName, let receiverType = ctx.implicitReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let name = interner.resolve(calleeName)
            if name == "callRecursive",
               args.count == 1,
               let (scopeClass, scopeSymbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema),
               scopeSymbol.fqName.count == 2,
               interner.resolve(scopeSymbol.fqName[0]) == "kotlin",
               interner.resolve(scopeSymbol.fqName[1]) == "DeepRecursiveScope",
               scopeClass.args.count == 2
            {
                let inputType: TypeID?
                let returnType: TypeID?
                switch (scopeClass.args[0], scopeClass.args[1]) {
                case let (.invariant(input), .invariant(output)):
                    inputType = input
                    returnType = output
                case let (.out(input), .out(output)):
                    inputType = input
                    returnType = output
                case let (.out(input), .invariant(output)):
                    inputType = input
                    returnType = output
                case let (.invariant(input), .out(output)):
                    inputType = input
                    returnType = output
                default:
                    inputType = nil
                    returnType = nil
                }
                if let inputType, let returnType {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: inputType)
                    let fqName = [interner.intern("kotlin"), interner.intern("DeepRecursiveScope"), interner.intern("callRecursive")]
                    if let chosen = sema.symbols.lookupAll(fqName: fqName).first(where: { symbolID in
                        guard let signature = sema.symbols.functionSignature(for: symbolID) else {
                            return false
                        }
                        return signature.typeParameterSymbols.count == signature.classTypeParameterCount
                            && sema.symbols.externalLinkName(for: symbolID) == "kk_deep_recursive_scope_callRecursive"
                    }) {
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [inputType, returnType],
                                parameterMapping: [0: 0]
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    }
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
            }

            if sema.types.isSubtype(nonNullReceiver, sema.types.charType),
               args.isEmpty,
               let member = syntheticCharMemberSpec(named: name)
            {
                let resultType = member.returnKind.typeID(
                    in: sema.types,
                    symbols: sema.symbols,
                    interner: interner
                )
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }

            // Boolean.not() / Boolean.and(other) / Boolean.or(other) / Boolean.xor(other) (STDLIB-308)
            if sema.types.isSubtype(nonNullReceiver, sema.types.booleanType) {
                let resultType = sema.types.booleanType
                let finalType = receiverType == nonNullReceiver
                    ? resultType
                    : sema.types.makeNullable(resultType)
                switch name {
                case "not" where args.isEmpty:
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                case "and" where args.count == 1,
                     "or" where args.count == 1,
                     "xor" where args.count == 1:
                    for arg in args {
                        _ = driver.inferExpr(arg.expr, ctx: ctx, locals: &locals, expectedType: sema.types.booleanType)
                    }
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                default:
                    break
                }
            }

            if let resultType = inferSequenceScopeYieldAllImplicitReceiverCall(
                id,
                calleeName: calleeName,
                args: args,
                ctx: ctx,
                locals: &locals,
                explicitTypeArgs: explicitTypeArgs
            ) {
                return resultType
            }

            // General member function lookup via implicit receiver
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: nonNullReceiver,
                sema: sema,
                interner: interner
            )
            if !memberCandidates.isEmpty {
                // Eagerly infer argument types for overload resolution.
                let memberArgTypes = args.map { argument in
                    driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                }
                let resolvedArgs = zip(args, memberArgTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                let resolved = ctx.resolver.resolveCall(
                    candidates: memberCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs
                    ),
                    expectedType: overloadResolutionExpectedType(from: expectedType, sema: sema),
                    implicitReceiverType: receiverType,
                    ctx: ctx.semaCtx
                )
                if let chosen = resolved.chosenCallee {
                    let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                } else if memberCandidates.count == 1,
                          let bestCandidate = memberCandidates.first,
                          let sig = sema.symbols.functionSignature(for: bestCandidate)
                {
                    // Fallback: bind directly if resolver could not pick (single candidate).
                    var mapping: [Int: Int] = [:]
                    for i in args.indices { mapping[i] = i }
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: bestCandidate,
                            substitutedTypeArguments: [],
                            parameterMapping: mapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(bestCandidate))
                    sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                    let resultType = sig.returnType
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
            }
            if let fallbackType = tryBindImplicitReceiverSyntheticExtensionCall(
                id, calleeName: calleeName, receiverType: nonNullReceiver, args: args,
                range: range, ctx: ctx, locals: &locals, expectedType: expectedType,
                explicitTypeArgs: explicitTypeArgs
            ) { return fallbackType }
        }

        if let firstInvisible = callInvisible.first, let calleeName {
            driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(calleeName), range: range, diagnostics: ctx.semaCtx.diagnostics)
        } else {
            let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0023",
                "Unresolved function '\(nameStr)'.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    /// Build `List<elementType>` for synthetic stdlib member-call inference.
    /// Falls back to `Any` when `kotlin.collections.List` is not registered.

    func inferMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: false
        )
    }

    func inferSafeMemberCallExpr(
        _ id: ExprID, receiverID: ExprID, calleeName: InternedString,
        args: [CallArgument], range: SourceRange, ctx: TypeInferenceContext,
        locals: inout LocalBindings, expectedType: TypeID?, explicitTypeArgs: [TypeID] = []
    ) -> TypeID {
        inferMemberCallImpl(
            id, receiverID: receiverID, calleeName: calleeName,
            args: args, range: range, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs,
            safeCall: true
        )
    }

    /// Locate a bundled-source `kotlin.sequences.generateSequence` overload with the
    /// given arity. Returns nil when no source declaration is available, letting the
    /// caller fall back to the runtime `kk_sequence_generate` path.
    private func sourceGenerateSequenceSymbol(
        sema: SemaModule,
        interner: StringInterner,
        arity: Int
    ) -> SymbolID? {
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern("generateSequence")
        ]
        return sema.symbols.lookupAll(fqName: fqName).first { symbol in
            guard let info = sema.symbols.symbol(symbol),
                  info.declSite != nil,
                  (sema.symbols.externalLinkName(for: symbol) ?? "").isEmpty,
                  let sig = sema.symbols.functionSignature(for: symbol),
                  sig.parameterTypes.count == arity
            else {
                return false
            }
            if arity == 2, sig.parameterTypes.count == 2,
               case .functionType = sema.types.kind(of: sig.parameterTypes[1])
            {
                return true
            }
            return arity != 2
        }
    }

}

// swiftlint:enable type_body_length
