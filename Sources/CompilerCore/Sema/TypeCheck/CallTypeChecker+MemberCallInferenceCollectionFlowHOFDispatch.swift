// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {

    func inferCollectionHOFSpecial(locals: inout LocalBindings) -> TypeID? {
        if isCollectionHOF, !isSourceBackedGenericOnEach {
            collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
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

            if CallTypeChecker.destinationCollectionHOFs.contains(calleeStr), args.count == 2 {
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
            // Original single-switch `default:` arm: callees matched by no
            // segment left resultType untouched; normalize to anyType.
            if resultType == sema.types.errorType {
                resultType = sema.types.anyType
            }

            let didBindListFilterSource = CallTypeChecker.sourceBackedListFilterNames.contains(calleeStr) && args.count == 1
                ? bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
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

            let didBindIterableFilterSource = CallTypeChecker.sourceBackedListFilterNames.contains(calleeStr)
                && args.count == 1
                && !didBindListFilterSource
                && (isIterableReceiver || (calleeStr == "filterIndexed" && isCollectionReceiver))
                && (!isSetReceiver || calleeStr == "filterIndexed")
                && bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            if didBindIterableFilterSource,
               let lambdaExpr = ast.arena.expr(args[0].expr),
               lambdaExpr.isLambdaOrCallableRef
            {
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
            }

            if !didBindListFilterSource,
               !didBindIterableFilterSource,
               sema.bindings.callBindings[id] == nil,
               calleeStr == "filterIndexed",
               isCollectionReceiver
            {
                let knownNames = KnownCompilerNames(interner: interner)
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
                let initialType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
                if bindBundledListSourceFunction(typeArguments: [collectionElementType, initialType], locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if isSetReceiver, bindBundledSetSourceFunction(locals: &locals) {
                    // Set has a more specific source-backed overload than
                    // Iterable; keep that receiver path ahead of the generic
                    // Iterable declaration.
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledIterableSourceFunction(typeArguments: [collectionElementType, initialType], locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledSequenceSourceIfAvailable(
                              resultType: resultType,
                              overrideTypeArguments: [collectionElementType, initialType],
                              allowIterableReceiver: true
                          , locals: &locals) {
                    // No dedicated Iterable source declaration or synthetic
                    // stub was found for this
                    // aggregate HOF (unlike reduce); fall back to the bundled
                    // Sequence<T> source body, which is plain iteration and
                    // therefore valid for any Iterable receiver.
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }
            } else if (calleeStr == "reduce" || calleeStr == "reduceOrNull" || calleeStr == "reduceIndexed" || calleeStr == "reduceIndexedOrNull"), args.count == 1 {
                // Iterable reduce-family source declarations are bound directly
                // below. Do not fall back to a Sequence declaration
                // for these names: the receiver may be a plain Set or another
                // Iterable, and the source-backed Iterable implementation is
                // the canonical dispatch target.
                if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledIterableSourceFunction(
                              typeArguments: [collectionElementType, collectionElementType]
                          , locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
            }
            // KSP-435/KSP-986: any/all/last/requireNoNulls/none on a nominal Collection/Iterable
            // receiver are bundled Kotlin source (Stdlib/kotlin/collections/Iterables.kt).
            // The name-keyed fast path above only computes a result type, so the call
            // would otherwise stay unresolved and lower to the bare member name.
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
                    // Prefer the List-specific overload when the receiver is a
                    // concrete List; its return type preserves the List contract.
                    didBindSource = bindBundledListSourceFunction(
                        typeArguments: iterableSourceTypeArguments
                    , locals: &locals) || bindBundledIterableSourceFunction(
                        typeArguments: iterableSourceTypeArguments
                    , locals: &locals)
                } else {
                    didBindSource = bindBundledIterableSourceFunction(
                        typeArguments: iterableSourceTypeArguments
                    , locals: &locals)
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
                // The call now targets an ordinary Kotlin declaration, so its lambda
                // arguments are boxed callables rather than native (closureObj, it)
                // collection-HOF lambdas.
                for arg in args {
                    if let lambdaExpr = ast.arena.expr(arg.expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(arg.expr)
                    }
                }
            }

            // KSP-984/KUU-542: bind the exact source-backed Iterable extrema and
            // sorting declarations after List/Set/Map-specific ownership has had
            // priority. Concrete Set and Collection receivers are admitted too:
            // the per-candidate Iterable subtype check keeps Map and other
            // non-Iterable receivers out. The selector parameter match keeps
            // minOf/minOfOrNull's Comparable/Double/Float overloads distinct.
            if sema.bindings.callBindings[id] == nil,
               let sourceBackedIterableAggregateTypeArguments,
               bindBundledIterableSourceFunction(
                   typeArguments: sourceBackedIterableAggregateTypeArguments,
                   matchingParameterTypes: sourceBackedIterableAggregateMatchingParameterTypes,
                   enforceTypeParameterCount: true,
                   matchingReceiverElementType: collectionElementType,
                   allowNominalIterableReceiver: true,
                   allowCollectionReceiver: true
               , locals: &locals)
            {
                for argument in args
                where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                }
            }

            // KSP-701: these generic collection extensions are ordinary
            // bundled Kotlin declarations on Iterable<T>. Keep the explicit
            // binding here for a statically Iterable receiver (and for
            // concrete collection receivers without a more specific source
            // overload) so the call never falls through to a Sequence-shaped
            // declaration or a removed synthetic runtime bridge.
            if sema.bindings.callBindings[id] == nil,
               !isSequenceReceiver,
               isCollectionReceiver,
               CallTypeChecker.iterableSourceHOFNames.contains(calleeStr),
               bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            {
                for argument in args
                where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
                }
            }
            if let sourceBackedSequenceAggregateTypeArguments {
                bindBundledSequenceAggregateSource(typeArguments: sourceBackedSequenceAggregateTypeArguments, locals: &locals)
            }

            // KSP-441: Bind source-backed Sequence transform extensions (map, filter,
            // mapIndexed, etc.) once the result element type is known. Do not override
            // an already-bound CallBinding from a list/aggregate source path.
            if isSequenceReceiver, sema.bindings.callBindings[id] == nil {
                _ = bindBundledSequenceSourceIfAvailable(resultType: resultType, locals: &locals)
            }

            // Sequence.sum()/average() only have the monomorphic numeric
            // source overloads (Byte/Short/Int/Long/Float/Double/unsigned).
            // Do not let an unsupported concrete element type fall through to
            // the raw runtime bridge with the wrong ABI shape.
            if isSequenceReceiver,
               sema.bindings.callBindings[id] == nil,
               ["sum", "average"].contains(calleeStr)
            {
                ctx.semaCtx.diagnostics.error(
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
