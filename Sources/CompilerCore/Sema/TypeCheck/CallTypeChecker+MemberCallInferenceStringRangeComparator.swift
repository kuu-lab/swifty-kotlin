// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallStringRangeComparatorSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        // Range forEach/map need lambda inference with expectedType so the
        // implicit `it` parameter gets bound correctly.
        // Must run before argument pre-inference below to avoid resolving
        // lambdas without the expected function type.
        if request.sema.bindings.isRangeExpr(request.receiverID),
           !request.args.isEmpty
        {
            if let fallbackType = tryRangeMemberFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: false,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx,
                locals: &locals
            ) {
                return fallbackType
            }
        }

        let stringHOFReceiverType = request.safeCall
            ? request.sema.types.makeNonNullable(receiverType)
            : receiverType
        if request.calleeName == request.knownNames.toCollection,
           request.args.count == 1,
           isSyntheticStringLikeType(stringHOFReceiverType, sema: request.sema)
        {
            // `CharSequence.toCollection` bounds its destination with
            // `C : MutableCollection<in Char>` — offer it as the expected
            // type so a nested `ArrayDeque()`/factory infers Char instead of
            // failing or collapsing to Nothing (KUU-4100).
            let destinationExpectedType = mutableCollectionDestinationExpectedType(
                argumentExpr: request.args[0].expr,
                elementType: request.sema.types.make(.primitive(.char, .nonNull)),
                expectedType: request.expectedType,
                sema: request.sema,
                interner: request.interner,
                ast: request.ast
            )
            let destinationType = driver.inferExpr(
                request.args[0].expr,
                ctx: request.ctx,
                locals: &locals,
                expectedType: destinationExpectedType
            )
            bindSyntheticStringMemberDirectlyIfAvailable(
                request.id,
                calleeName: request.calleeName,
                argumentCount: request.args.count,
                receiverType: stringHOFReceiverType,
                sema: request.sema,
                interner: request.interner
            )
            let finalType = request.safeCall ? request.sema.types.makeNullable(destinationType) : destinationType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }
        if let boundType = tryBindStringWindowedTransform(
            request.id,
            calleeName: request.calleeName,
            receiverType: stringHOFReceiverType,
            args: request.args,
            safeCall: request.safeCall,
            ast: request.ast,
            ctx: request.ctx,
            locals: &locals,
            explicitTypeArgs: request.explicitTypeArgs
        ) {
            return boundType
        }

        if request.args.count == 1 {
            let stringHOFCalleeStr = request.interner.resolve(request.calleeName)
            let isStringHOFReceiver = request.sema.types.isSubtype(stringHOFReceiverType, request.sema.types.stringType)
                || (stringHOFCalleeStr == "zipWithNext"
                    && isSyntheticStringLikeType(stringHOFReceiverType, sema: request.sema))
            if isStringHOFReceiver,
               [
                   "indexOfFirst", "indexOfLast",
                   "map", "mapIndexed", "mapNotNull",
                   "takeWhile", "dropWhile",
                   "trim", "trimStart", "trimEnd",
                   "zipWithNext",
               ].contains(stringHOFCalleeStr)
            {
                let charType = request.sema.types.make(.primitive(.char, .nonNull))
                let intType = request.sema.types.intType
                if stringHOFCalleeStr != "zipWithNext" {
                    if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    }
                    let lambdaExpectedType: TypeID = switch stringHOFCalleeStr {
                    case "map", "mapNotNull":
                        request.sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: request.sema.types.nullableAnyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    case "mapIndexed":
                        request.sema.types.make(.functionType(FunctionType(
                            params: [intType, charType],
                            returnType: request.sema.types.nullableAnyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    default:
                        request.sema.types.make(.functionType(FunctionType(
                            params: [charType],
                            returnType: request.sema.types.booleanType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                }
                var resolvedArgTypes = request.args.map { arg in
                    request.sema.bindings.exprType(for: arg.expr) ?? request.sema.types.anyType
                }
                // KUU-4125: the placeholder `(Char) -> Any?` expected type
                // above pins the bound lambda type's return to `Any?`.
                // Feeding that to overload resolution gives map's `R` a
                // lower bound of `Any?` that conflicts with the upper bound
                // coming from an expected `List<R>` (Conflicting bounds,
                // TYPE-0001). Substitute the lambda body's inferred return
                // type so `R` unifies the way regular resolution does. When
                // the body really is `Any?` the refinement is a no-op, so a
                // genuine `List<Any?>`-vs-`List<X>` mismatch still surfaces.
                if stringHOFCalleeStr == "map" || stringHOFCalleeStr == "mapIndexed"
                    || stringHOFCalleeStr == "mapNotNull",
                   case let .functionType(boundFunctionType) = request.sema.types.kind(of: resolvedArgTypes[0]),
                   boundFunctionType.returnType == request.sema.types.nullableAnyType
                {
                    let inferredReturnType = inferredLambdaReturnType(
                        argExpr: request.args[0].expr,
                        ast: request.ast,
                        sema: request.sema
                    )
                    if inferredReturnType != boundFunctionType.returnType {
                        resolvedArgTypes[0] = request.sema.types.make(.functionType(FunctionType(
                            contextReceivers: boundFunctionType.contextReceivers,
                            receiver: boundFunctionType.receiver,
                            params: boundFunctionType.params,
                            returnType: inferredReturnType,
                            isSuspend: boundFunctionType.isSuspend,
                            isCallableReference: boundFunctionType.isCallableReference,
                            nullability: boundFunctionType.nullability,
                            throws: boundFunctionType.`throws`
                        )))
                    }
                }
                let stringMapResultElementType: TypeID? = if request.explicitTypeArgs.count <= 1 {
                    switch stringHOFCalleeStr {
                    case "map", "mapIndexed":
                        request.explicitTypeArgs.first
                            ?? inferredLambdaReturnType(argExpr: request.args[0].expr, ast: request.ast, sema: request.sema)
                    case "mapNotNull":
                        request.explicitTypeArgs.first
                            ?? request.sema.types.makeNonNullable(
                                inferredLambdaReturnType(argExpr: request.args[0].expr, ast: request.ast, sema: request.sema)
                            )
                    default:
                        nil
                    }
                } else {
                    nil
                }
                if stringHOFCalleeStr == "zipWithNext" {
                    // Re-run inference with the transform overload so the result type
                    // comes from the lambda body rather than the placeholder `Any`.
                    if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    }
                    guard request.explicitTypeArgs.count <= 1 else {
                        request.sema.bindings.bindExprType(request.id, type: request.sema.types.anyType)
                        return request.sema.types.anyType
                    }
                    let lambdaReturnType = resolvedExplicitTypeArgument(at: 0, in: request.explicitTypeArgs) ?? request.sema.types.anyType
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [charType, charType],
                        returnType: lambdaReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let bodyType = resolvedExplicitTypeArgument(at: 0, in: request.explicitTypeArgs)
                        ?? inferredLambdaReturnType(argExpr: request.args[0].expr, ast: request.ast, sema: request.sema)
                    if let chosen = request.sema.symbols.lookupAll(fqName: [
                        request.interner.intern("kotlin"),
                        request.interner.intern("text"),
                        request.calleeName,
                    ]).first(where: { candidate in
                        isSyntheticStringMemberCandidate(
                            candidate,
                            named: request.calleeName,
                            receiverType: stringHOFReceiverType,
                            sema: request.sema,
                            interner: request.interner
                        )
                            && (request.sema.symbols.functionSignature(for: candidate)?.parameterTypes.count ?? Int.max) == request.args.count
                    }) {
                        request.sema.bindings.bindCall(
                            request.id,
                            binding: CallBinding(
                                chosenCallee: chosen,
                                substitutedTypeArguments: [bodyType],
                                parameterMapping: [0: 0]
                            )
                        )
                        request.sema.bindings.bindCallableTarget(request.id, target: .symbol(chosen))
                    }
                    let resultType = makeSyntheticListType(
                        symbols: request.sema.symbols,
                        types: request.sema.types,
                        interner: request.interner,
                        elementType: bodyType
                    )
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
                if let boundType = tryBindSyntheticStringMemberFallback(
                    request.id,
                    calleeName: request.calleeName,
                    receiverType: stringHOFReceiverType,
                    args: request.args,
                    argTypes: resolvedArgTypes,
                    range: request.range,
                    ctx: request.ctx,
                    expectedType: request.expectedType,
                    explicitTypeArgs: request.explicitTypeArgs,
                    safeCall: request.safeCall
                ) {
                    // The placeholder lambda type above can leave the generic
                    // result as Any? even when the body has a concrete type.
                    // Reapply the body type when no explicit or expected type
                    // constrains the call, so a following collection operator
                    // sees the correct List element type.
                    if request.explicitTypeArgs.isEmpty,
                       request.expectedType == nil,
                       boundType != request.sema.types.errorType,
                       let resultElementType = stringMapResultElementType,
                       let binding = request.sema.bindings.callBinding(for: request.id),
                       let signature = request.sema.symbols.functionSignature(for: binding.chosenCallee),
                       signature.typeParameterSymbols.count == 1
                    {
                        request.sema.bindings.bindCall(
                            request.id,
                            binding: CallBinding(
                                chosenCallee: binding.chosenCallee,
                                substitutedTypeArguments: [resultElementType],
                                parameterMapping: binding.parameterMapping,
                                defaultArgumentOwner: binding.defaultArgumentOwner,
                                isCallableReferenceAdapter: binding.isCallableReferenceAdapter,
                                hidesKCallable: binding.hidesKCallable
                            )
                        )
                        let resultType = makeSyntheticListType(
                            symbols: request.sema.symbols,
                            types: request.sema.types,
                            interner: request.interner,
                            elementType: resultElementType
                        )
                        let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                        request.sema.bindings.bindExprType(request.id, type: finalType)
                        return finalType
                    }
                    return boundType
                }
                bindSyntheticStringMemberDirectlyIfAvailable(
                    request.id,
                    calleeName: request.calleeName,
                    argumentCount: request.args.count,
                    receiverType: stringHOFReceiverType,
                    sema: request.sema,
                    interner: request.interner
                )
                let sequenceStringType: TypeID = {
                    let knownNames = KnownCompilerNames(interner: request.interner)
                    guard let sequenceSymbol = request.sema.symbols.lookupAll(fqName: knownNames.kotlinSequenceFQName).first else {
                        return request.sema.types.anyType
                    }
                    return request.sema.types.make(.classType(ClassType(
                        classSymbol: sequenceSymbol,
                        args: [.out(request.sema.types.stringType)],
                        nullability: .nonNull
                    )))
                }()
                // KUU-2331: the synthetic String-HOF fallback can miss the
                // source-backed CharSequence.map candidate. Keep its list
                // result type so chained collection calls bind normally.
                let resultType: TypeID = switch stringHOFCalleeStr {
                case "indexOfFirst", "indexOfLast": request.sema.types.intType
                case "takeWhile", "dropWhile",
                     "trim", "trimStart", "trimEnd": request.sema.types.stringType
                case "map", "mapIndexed": makeSyntheticListType(
                    symbols: request.sema.symbols,
                    types: request.sema.types,
                    interner: request.interner,
                    elementType: stringMapResultElementType ?? request.sema.types.anyType
                )
                case "mapNotNull": makeSyntheticListType(
                    symbols: request.sema.symbols,
                    types: request.sema.types,
                    interner: request.interner,
                    elementType: stringMapResultElementType ?? request.sema.types.anyType
                )
                case "splitToSequence": sequenceStringType
                default: request.sema.types.anyType
                }
                let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        // thenBy/thenByDescending/thenDescending/thenComparator need the
        // Comparator<T> receiver type so the lambda gets the correct
        // contextual function signature before the general resolution path runs.
        if request.args.count == 2,
           ["thenBy", "thenByDescending"].contains(request.interner.resolve(request.calleeName)),
           let comparatorElementType = resolvedComparatorElementType(
               of: receiverType,
               sema: request.sema,
               interner: request.interner
           )
        {
            let keyComparatorType = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals)
            if let keyType = resolvedComparatorElementType(of: keyComparatorType, sema: request.sema, interner: request.interner) {
                if let lambdaExpr = request.ast.arena.expr(request.args[1].expr),
                   lambdaExpr.isLambdaOrCallableRef
                {
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[1].expr)
                }
                let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                    params: [comparatorElementType],
                    returnType: keyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                _ = driver.inferExpr(request.args[1].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
            }
        }
        if request.args.count == 1 {
            let calleeStr = request.interner.resolve(request.calleeName)
            if let comparatorElementType = resolvedComparatorElementType(
                of: receiverType,
                sema: request.sema,
                interner: request.interner
            ) {
                guard let lambdaExpr = request.ast.arena.expr(request.args[0].expr),
                      lambdaExpr.isLambdaOrCallableRef
                else {
                    return nil
                }
                request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                switch calleeStr {
                case "thenBy", "thenByDescending":
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [comparatorElementType],
                        returnType: request.sema.types.nullableAnyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                case "thenComparator", "thenDescending":
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [comparatorElementType, comparatorElementType],
                        returnType: request.sema.types.intType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                default:
                    break
                }
            }
        }
        return nil
    }
}
