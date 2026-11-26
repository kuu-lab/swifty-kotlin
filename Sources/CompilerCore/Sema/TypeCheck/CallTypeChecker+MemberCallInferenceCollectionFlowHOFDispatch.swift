// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {

    func inferCollectionHOFSpecial(locals: inout LocalBindings) -> TypeID? {
        if isCollectionHOF, !isSourceBackedGenericOnEach {
            collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx)
            collectionMapTypes = {
                guard let classType = resolveClassType(receiverType, sema: sema),
                      classType.args.count >= 2
                else {
                    return (sema.types.anyType, sema.types.anyType)
                }
                let keyType: TypeID = switch classType.args[0] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
                let valueType: TypeID = switch classType.args[1] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
                return (keyType, valueType)
            }()


            listResultType = if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }

            if knownNames.destinationCollectionHOFs.contains(calleeName), args.count == 2 {
                if let inferredType = inferDestinationCollectionHOFSpecial(locals: &locals) {
                    return inferredType
                }
                if didReturnNil { return nil }
            }

            if let inferredType = inferCollectionHOFTransformCases(locals: &locals) {
                return inferredType
            }
            if didReturnNil { return nil }
            if let inferredType = inferCollectionHOFAggregateAndSortCases(locals: &locals) {
                return inferredType
            }
            if didReturnNil { return nil }
            if let inferredType = inferCollectionHOFSumAndMiscCases(locals: &locals) {
                return inferredType
            }
            if didReturnNil { return nil }
            if resultType == sema.types.errorType {
                resultType = sema.types.anyType
            }

            let didBindListFilterSource = knownNames.sourceBackedListFilterNames.contains(calleeName) && args.count == 1
                ? bindBundledListSourceFunction(typeArguments: [collectionElementType])
                : false
            if didBindListFilterSource {
                // The lambda argument was speculatively marked (above) as a
                // native collection HOF lambda expecting the (closureObj, it)
                // two-argument ABI. It is actually being passed to a bundled
                // Kotlin-source declaration as an ordinary boxed callable
                // value, so undo that so LambdaLowerer materializes it via
                // kk_function_create_N instead. Otherwise multi-capture
                // lambdas crash: the callee never packs captures into a
                // closure object (appendClosureArgumentsIfNeeded only runs
                // for calls with an externalLinkName), so the lambda's own
                // (closureObj, it) parameters read out-of-bounds.
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
            }

            let didBindIterableFilterSource = knownNames.sourceBackedListFilterNames.contains(calleeName)
                && args.count == 1
                && !didBindListFilterSource
                && (isIterableReceiver || (calleeName == knownNames.filterIndexed && isCollectionReceiver))
                && (!isSetReceiver || calleeName == knownNames.filterIndexed)
                && bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
            if didBindIterableFilterSource,
               let lambdaExpr = ast.arena.expr(args[0].expr),
               lambdaExpr.isLambdaOrCallableRef
            {
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
            }

            if !didBindListFilterSource,
               !didBindIterableFilterSource,
               sema.bindings.callBindings[id] == nil,
               calleeName == knownNames.filterIndexed,
               isCollectionReceiver
            {
                let memberFQName = knownNames.kotlinCollectionsListFQName + [calleeName]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { symbolID in
                    sema.symbols.functionSignature(for: symbolID)?.parameterTypes.count == args.count
                }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [collectionElementType],
                        parameterMapping: [0: 0]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }
            }

            if ["fold", "foldRight", "foldIndexed", "foldRightIndexed", "scan", "runningFold", "runningFoldIndexed", "scanIndexed"].contains(calleeStr), args.count == 2 {
                let initialType = foldAccumulatorType ?? sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
                if bindBundledListSourceFunction(typeArguments: [collectionElementType, initialType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if isSetReceiver, bindBundledSetSourceFunction(locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledIterableSourceFunction(typeArguments: [collectionElementType, initialType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledSequenceSourceIfAvailable(
                              resultType: resultType,
                              overrideTypeArguments: [collectionElementType, initialType],
                              allowIterableReceiver: true
                          , locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }
            } else if (calleeStr == "reduce" || calleeStr == "reduceOrNull" || calleeStr == "reduceIndexed" || calleeStr == "reduceIndexedOrNull"), args.count == 1 {
                if calleeStr == "reduce", isListReceiver,
                   bindBundledIterableSourceFunction(
                       typeArguments: [collectionElementType, collectionElementType],
                       enforceTypeParameterCount: true)
                {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if !isSequenceReceiver, (isCollectionReceiver || isIterableReceiver),
                          bindBundledIterableSourceFunction(
                              typeArguments: [collectionElementType, collectionElementType]
                          ) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
            }
            if sema.bindings.callBindings[id] == nil,
               !isSequenceReceiver,
               (isCollectionReceiver || (isIterableReceiver && calleeStr == "none")),
               ["any", "all", "last", "requireNoNulls", "none"].contains(calleeStr)
            {
                let iterableSourceTypeArguments = calleeStr == "requireNoNulls"
                    ? [sema.types.makeNonNullable(collectionElementType)]
                    : [collectionElementType]
                let didBindSource: Bool
                if calleeStr == "requireNoNulls" {
                    didBindSource = bindBundledListSourceFunction(
                        typeArguments: iterableSourceTypeArguments
                    ) || bindBundledIterableSourceFunction(
                        typeArguments: iterableSourceTypeArguments
                    )
                } else {
                    didBindSource = bindBundledIterableSourceFunction(
                        typeArguments: iterableSourceTypeArguments
                    )
                }
                if didBindSource {
                    for argument in args
                    where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                    }
                }
            }

            // Set-specific source declarations must be selected before the
            // generic Iterable overloads below. Set is also a Collection, so
            // binding Iterable.filter first would make the result depend on
            // bundled source load order.
            if isSetReceiver, sema.bindings.callBindings[id] == nil, bindBundledSetSourceFunction(locals: &locals) {
                for arg in args {
                    if let lambdaExpr = ast.arena.expr(arg.expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
                    }
                }
            }

            if sema.bindings.callBindings[id] == nil,
               let sourceBackedIterableAggregateTypeArguments,
               bindBundledIterableSourceFunction(
                   typeArguments: sourceBackedIterableAggregateTypeArguments,
                   matchingParameterTypes: sourceBackedIterableAggregateMatchingParameterTypes,
                   enforceTypeParameterCount: true,
                   matchingReceiverElementType: collectionElementType,
                   allowNominalIterableReceiver: true,
                   allowCollectionReceiver: true
               )
            {
                for argument in args
                where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                }
            }

            if sema.bindings.callBindings[id] == nil,
               !isSequenceReceiver,
               isCollectionReceiver,
               knownNames.iterableSourceHOFNames.contains(calleeName),
               bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
            {
                for argument in args
                where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                }
            }
            if let sourceBackedSequenceAggregateTypeArguments {
                bindBundledSequenceAggregateSource(typeArguments: sourceBackedSequenceAggregateTypeArguments, locals: &locals)
            }

            if isSequenceReceiver, sema.bindings.callBindings[id] == nil {
                _ = bindBundledSequenceSourceIfAvailable(resultType: resultType, locals: &locals)
            }

            if isSequenceReceiver,
               sema.bindings.callBindings[id] == nil,
               ["sum", "average"].contains(calleeStr)
            {
                if sema.requiresResolvedLibraryCalls,
                   let aggregateType = CallTypeChecker.jvmSequenceAggregateResultType(
                       member: calleeStr,
                       elementType: collectionElementType,
                       sema: sema
                   )
                {
                    resultType = aggregateType
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    let failedType = safeCall
                        ? sema.types.makeNullable(sema.types.errorType)
                        : sema.types.errorType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
            }

            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            if isSyntheticSequenceReceiver,
               ["map", "filter", "flatMap", "flatMapIndexed", "flatten", "sortedBy", "sortedByDescending", "takeWhile", "dropWhile", "onEach", "onEachIndexed", "distinctBy"].contains(calleeStr)
            {
                sema.bindings.markCollectionExpr(id)
            }
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }
}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
