// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func inferDestinationCollectionHOFSpecial(locals: inout LocalBindings) -> TypeID? {
        if CallTypeChecker.destinationCollectionHOFs.contains(calleeStr), args.count == 2 {
            // A destination factory such as `mutableListOf()` has no
            // argument from which to infer its element type.  When the
            // enclosing destination HOF is itself target-typed, propagate
            // an exact MutableList target into that argument so the
            // factory contributes `MutableList<R>` rather than
            // `MutableList<Nothing>`/`Any?` to the generic `C` constraint.
            let destinationExpectedType: TypeID? = if let expectedType,
                                                        case let .classType(expectedClassType) = sema.types.kind(
                                                            of: sema.types.makeNonNullable(expectedType)
                                                        ),
                                                        let expectedClassSymbol = sema.symbols.symbol(expectedClassType.classSymbol),
                                                        expectedClassSymbol.fqName == [
                                                            interner.intern("kotlin"),
                                                            interner.intern("collections"),
                                                            interner.intern("MutableList"),
                                                        ]
            {
                expectedType
            } else {
                nil
            }
            var destinationType = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: destinationExpectedType
            )
            var nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
            let destinationRequiresMutableMap = calleeStr == "associateTo"
                || calleeStr == "mapKeysTo"
                || calleeStr == "mapValuesTo"
                || (isMapReceiver && (calleeStr == "filterTo" || calleeStr == "filterNotTo"))
            let destinationBoundName = destinationRequiresMutableMap ? "MutableMap" : "MutableCollection"
            let destinationBoundArity = destinationRequiresMutableMap ? 2 : 1
            let destinationBoundArguments: [TypeArg] = if case let .classType(destinationClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                         destinationClassType.args.count >= destinationBoundArity
            {
                destinationClassType.args.prefix(destinationBoundArity).map { argument in
                    switch argument {
                    case let .invariant(type), let .out(type), let .in(type): .in(type)
                    case .star: .in(sema.types.nothingType)
                    }
                }
            } else {
                Array(repeating: .in(sema.types.nothingType), count: destinationBoundArity)
            }
            if let destinationBoundSymbol = lookupStdlibSymbol(
                destinationBoundName,
                symbols: sema.symbols,
                interner: interner
            ) {
                let destinationBound = sema.types.make(.classType(ClassType(
                    classSymbol: destinationBoundSymbol,
                    args: destinationBoundArguments,
                    nullability: .nonNull
                )))
                guard sema.types.isSubtype(nonNullableDestinationType, destinationBound) else {
                    let actualTypeName = sema.types.displayName(
                        of: destinationType,
                        symbols: sema.symbols,
                        interner: interner
                    )
                    let requiredTypeName = sema.types.displayName(
                        of: destinationBound,
                        symbols: sema.symbols,
                        interner: interner
                    )
                    ctx.semaCtx.diagnostics.emit(Diagnostic(
                        severity: .error,
                        code: "KSWIFTK-TYPE-0001",
                        message: "Type mismatch: destination has type '\(actualTypeName)', but '\(requiredTypeName)' is required for '\(calleeStr)'.",
                        primaryRange: ast.arena.exprRange(args[0].expr) ?? range,
                        secondaryRanges: []
                    ))
                    return sema.types.errorType
                }
            }
            func destinationTypeArgument(at argIndex: Int, minimumArity: Int) -> TypeID {
                guard case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                      destClassType.args.count >= minimumArity,
                      argIndex < destClassType.args.count
                else {
                    return sema.types.anyType
                }
                return switch destClassType.args[argIndex] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            }
            var destinationElementType = destinationTypeArgument(at: 0, minimumArity: 1)
            var destinationMapKeyType = destinationTypeArgument(at: 0, minimumArity: 2)
            var destinationMapValueType = destinationTypeArgument(at: 1, minimumArity: 2)
            var pairReturnType: TypeID = if calleeStr == "associateTo" {
                if let pairSymbol = lookupStdlibSymbol("Pair", symbols: sema.symbols, interner: interner) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.invariant(destinationMapKeyType), .invariant(destinationMapValueType)],
                        nullability: .nonNull
                    )))
                } else {
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            // `mutableListOf()`/`mutableMapOf()` and similar factories infer
            // `Nothing` element types before the destination constraint is
            // known. While the argument is still an inferable nested call,
            // keep the lambda expectation unconstrained, then re-infer the
            // destination once the lambda's result type is known — the same
            // participation the nested call's type variable gets in
            // kotlinc's outer constraint set.
            let destinationNeedsDeferredInference = isInferableNestedCallExpr(args[0].expr, ast: ast)
                && (typeContainsNothingType(destinationElementType, sema: sema)
                    || typeContainsNothingType(destinationMapKeyType, sema: sema)
                    || typeContainsNothingType(destinationMapValueType, sema: sema))
            let lambdaExpectedType: TypeID = switch calleeStr {
            case "filterTo", "filterNotTo":
                sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.booleanType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "filterIndexedTo":
                sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType],
                    returnType: sema.types.booleanType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "mapTo":
                sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: !isListReceiver && !isSequenceReceiver && !isArrayReceiver && !isMapReceiver
                        ? sema.types.nullableAnyType
                        : destinationElementType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "flatMapTo":
                {
                    // The Iterable and Sequence overloads are distinguished by
                    // the lambda return type; infer that return before binding.
                    if !isSequenceReceiver,
                       isIterableReceiver,
                       !receiverClassification.isListReceiver,
                       !receiverClassification.isSetReceiver,
                       !receiverClassification.isMapReceiver
                    {
                        return sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }
                    if let collectionSymbol = lookupStdlibSymbol("Collection", symbols: sema.symbols, interner: interner) {
                        let iterableType = sema.types.make(.classType(ClassType(
                            classSymbol: collectionSymbol,
                            args: [.invariant(destinationElementType)],
                            nullability: .nonNull
                        )))
                        return sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType],
                            returnType: iterableType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }
                    return sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                }()
            case "mapNotNullTo":
                sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.makeNullable(destinationElementType),
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "mapIndexedTo":
                sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType],
                    returnType: !isListReceiver && !isSequenceReceiver && !isArrayReceiver && !isMapReceiver
                        ? sema.types.nullableAnyType
                        : destinationElementType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "mapIndexedNotNullTo":
                sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType],
                    returnType: sema.types.makeNullable(destinationElementType),
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "flatMapIndexedTo":
                {
                    // The Iterable and Sequence overloads are distinguished by
                    // the lambda return type; infer that return before binding.
                    if !isSequenceReceiver,
                       isIterableReceiver,
                       !receiverClassification.isListReceiver,
                       !receiverClassification.isSetReceiver,
                       !receiverClassification.isMapReceiver
                    {
                        return sema.types.make(.functionType(FunctionType(
                            params: [sema.types.intType, collectionElementType],
                            returnType: sema.types.anyType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }
                    if let collectionSymbol = lookupStdlibSymbol("Collection", symbols: sema.symbols, interner: interner) {
                        let iterableType = sema.types.make(.classType(ClassType(
                            classSymbol: collectionSymbol,
                            args: [.invariant(destinationElementType)],
                            nullability: .nonNull
                        )))
                        return sema.types.make(.functionType(FunctionType(
                            params: [sema.types.intType, collectionElementType],
                            returnType: iterableType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    }
                    return sema.types.make(.functionType(FunctionType(
                        params: [sema.types.intType, collectionElementType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                }()
            case "associateTo":
                sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: pairReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "mapKeysTo":
                sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: destinationMapKeyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            case "mapValuesTo":
                sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: destinationMapValueType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
            default:
                sema.types.anyType
            }
            let effectiveLambdaExpectedType: TypeID
            if destinationNeedsDeferredInference,
               case let .functionType(lambdaFunctionType) = sema.types.kind(of: lambdaExpectedType)
            {
                effectiveLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: lambdaFunctionType.params,
                    returnType: sema.types.nullableAnyType,
                    isSuspend: lambdaFunctionType.isSuspend,
                    nullability: .nonNull
                )))
            } else {
                effectiveLambdaExpectedType = lambdaExpectedType
            }
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: effectiveLambdaExpectedType)
            if destinationNeedsDeferredInference {
                // The destination argument's element types only become
                // knowable once the transform lambda has produced its
                // result type: rebuild the `C : MutableCollection<in R>` /
                // `M : MutableMap<in K, in V>` bound from that result and
                // steer the deferred factory call with it.
                let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                let deferredDestinationElementType: TypeID = switch calleeStr {
                case "filterTo", "filterNotTo", "filterIndexedTo":
                    collectionElementType
                case "mapTo", "mapIndexedTo":
                    rawLambdaReturnType
                case "mapNotNullTo", "mapIndexedNotNullTo":
                    sema.types.makeNonNullable(rawLambdaReturnType)
                case "flatMapTo", "flatMapIndexedTo":
                    !isSequenceReceiver && isIterableReceiver
                        && !receiverClassification.isListReceiver
                        && !receiverClassification.isSetReceiver
                        && !receiverClassification.isMapReceiver
                        ? extractIterableOrSequenceElementType(rawLambdaReturnType, sema: sema, interner: interner)
                        : extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                default:
                    sema.types.anyType
                }
                func unwrappedTypeArgument(_ arg: TypeArg) -> TypeID {
                    switch arg {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                }
                let deferredMapPairTypes: (key: TypeID, value: TypeID)? = if case let .classType(pairClassType) = sema.types.kind(
                    of: sema.types.makeNonNullable(rawLambdaReturnType)
                ), pairClassType.args.count == 2 {
                    (
                        unwrappedTypeArgument(pairClassType.args[0]),
                        unwrappedTypeArgument(pairClassType.args[1])
                    )
                } else {
                    nil
                }
                func mutableMapExpectedType(key: TypeID, value: TypeID) -> TypeID? {
                    guard let mutableMapSymbol = lookupStdlibSymbol("MutableMap", symbols: sema.symbols, interner: interner) else {
                        didReturnNil = true
                        return nil
                    }
                    return sema.types.make(.classType(ClassType(
                        classSymbol: mutableMapSymbol,
                        args: [.in(key), .in(value)],
                        nullability: .nonNull
                    )))
                }
                let reinferBoundType: TypeID? = switch calleeStr {
                case "mapKeysTo":
                    mutableMapExpectedType(key: rawLambdaReturnType, value: collectionMapTypes.value)
                case "mapValuesTo":
                    mutableMapExpectedType(key: collectionMapTypes.key, value: rawLambdaReturnType)
                case "associateTo":
                    if let deferredMapPairTypes {
                        mutableMapExpectedType(key: deferredMapPairTypes.key, value: deferredMapPairTypes.value)
                    } else {
                        nil
                    }
                default:
                    if let mutableCollectionSymbol = lookupStdlibSymbol("MutableCollection", symbols: sema.symbols, interner: interner) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: mutableCollectionSymbol,
                            args: [.in(deferredDestinationElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        nil
                    }
                }
                let reinferExpectedType = reinferBoundType.flatMap { boundType in
                    concreteNestedCallExpectedType(
                        originalArgumentType: nonNullableDestinationType,
                        boundType: boundType,
                        sema: sema
                    )
                }
                if let reinferExpectedType {
                    let reinferDiagnosticsCheckpoint = ctx.semaCtx.diagnostics.checkpoint()
                    let reinferredType = driver.inferExpr(
                        args[0].expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: reinferExpectedType
                    )
                    if reinferredType != sema.types.errorType,
                       !typeContainsNothingType(reinferredType, sema: sema)
                    {
                        destinationType = reinferredType
                        nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
                        destinationElementType = destinationTypeArgument(at: 0, minimumArity: 1)
                        destinationMapKeyType = destinationTypeArgument(at: 0, minimumArity: 2)
                        destinationMapValueType = destinationTypeArgument(at: 1, minimumArity: 2)
                        if calleeStr == "associateTo",
                           let pairSymbol = lookupStdlibSymbol("Pair", symbols: sema.symbols, interner: interner)
                        {
                            pairReturnType = sema.types.make(.classType(ClassType(
                                classSymbol: pairSymbol,
                                args: [.invariant(destinationMapKeyType), .invariant(destinationMapValueType)],
                                nullability: .nonNull
                            )))
                        }
                    } else {
                        // The factory could not be steered to a concrete
                        // type; drop the speculative diagnostics and
                        // restore the destination-shaped lambda
                        // expectation so the original failure still
                        // diagnoses at the transform.
                        ctx.semaCtx.diagnostics.rollback(to: reinferDiagnosticsCheckpoint)
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    }
                } else {
                    // No destination type could be derived (e.g. a non-Pair
                    // associateTo transform); restore the destination-shaped
                    // lambda expectation so the mismatch still diagnoses.
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                }
            }
            resultType = destinationType
            // Sequence and List now share top-level source-backed overload names.
            // Bind the Sequence overload explicitly to avoid selecting List.associateTo.
            if calleeStr == "associateTo", isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [
                    collectionElementType, destinationMapKeyType, destinationMapValueType
                ]
            }
            if calleeStr == "associateTo" {
                let sourceTypeArguments = [collectionElementType, destinationMapKeyType, destinationMapValueType, nonNullableDestinationType]
                if bindBundledListSourceFunction(
                    typeArguments: sourceTypeArguments
                , locals: &locals) || bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments, locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }
            }
            if let sourceBackedSequenceAggregateTypeArguments {
                bindBundledSequenceAggregateSource(typeArguments: sourceBackedSequenceAggregateTypeArguments, locals: &locals)
            }
            if ["filterTo", "filterNotTo", "filterIndexedTo"].contains(calleeStr),
               !isSequenceReceiver
            {
                let didBindListSource = bindBundledListSourceFunction(
                    typeArguments: [collectionElementType, nonNullableDestinationType]
                , locals: &locals)
                // KUU-1389: Set/Collection-family receivers inherit these
                // declarations from Iterable<T> upstream. Gating on
                // isIterableReceiver admitted only nominal Iterable types,
                // so a Set receiver bound a result type with no callee and
                // lowered to a phantom `_filterTo`-style symbol. Mirror the
                // mapTo arm below: bind the bundled Iterable declaration
                // for every collection receiver (the per-candidate nominal
                // subtype check keeps Map and Array out).
                let didBindIterableSource = !didBindListSource
                    && !isArrayReceiver
                    && !isMapReceiver
                    && bindBundledIterableSourceFunction(
                        typeArguments: [collectionElementType, nonNullableDestinationType]
                    , locals: &locals)
                if didBindListSource || didBindIterableSource,
                   let lambdaExpr = ast.arena.expr(args[1].expr),
                   lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                }
            }
            if ["mapTo", "mapNotNullTo", "flatMapTo", "mapIndexedTo", "mapIndexedNotNullTo", "flatMapIndexedTo"].contains(calleeStr),
               !isSequenceReceiver,
               !isMapReceiver
            {
                let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                let resultElementType: TypeID
                if calleeStr == "mapTo" || calleeStr == "mapIndexedTo" {
                    resultElementType = rawLambdaReturnType
                } else if calleeStr == "mapNotNullTo" || calleeStr == "mapIndexedNotNullTo" {
                    resultElementType = sema.types.makeNonNullable(rawLambdaReturnType)
                } else if (calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo"),
                          !isSequenceReceiver,
                          isIterableReceiver,
                          !receiverClassification.isListReceiver,
                          !receiverClassification.isSetReceiver,
                          !receiverClassification.isMapReceiver
                {
                    resultElementType = extractIterableOrSequenceElementType(
                        rawLambdaReturnType,
                        sema: sema,
                        interner: interner
                    )
                } else {
                    resultElementType = extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                }
                let boundIterableDestination = (calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo")
                    && bindBundledIterableFlatMapSourceFunction(
                        collectionElementType: collectionElementType,
                        resultElementType: resultElementType,
                        returnsSequence: receiverClassifier.isSequenceLikeType(rawLambdaReturnType),
                        destinationType: nonNullableDestinationType
                    , locals: &locals)
                let didBindListSource: Bool
                if boundIterableDestination {
                    didBindListSource = false
                } else {
                    didBindListSource = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType, resultElementType, nonNullableDestinationType]
                    , locals: &locals)
                }
                let didBindIterableSource: Bool
                if !boundIterableDestination,
                   !didBindListSource,
                   !isArrayReceiver,
                   !isMapReceiver
                {
                    didBindIterableSource = bindBundledIterableSourceFunction(
                        typeArguments: [collectionElementType, resultElementType, nonNullableDestinationType]
                    , locals: &locals)
                } else {
                    didBindIterableSource = false
                }
                if boundIterableDestination || didBindListSource || didBindIterableSource {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }
            }
            if isSequenceReceiver {
                let typeArguments: [TypeID]
                if ["filterTo", "filterNotTo", "filterIndexedTo"].contains(calleeStr) {
                    typeArguments = [collectionElementType, nonNullableDestinationType]
                } else {
                    let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                    let resultElementType: TypeID
                    if calleeStr == "mapTo" || calleeStr == "mapIndexedTo" {
                        resultElementType = rawLambdaReturnType
                    } else if calleeStr == "mapNotNullTo" || calleeStr == "mapIndexedNotNullTo" {
                        resultElementType = sema.types.makeNonNullable(rawLambdaReturnType)
                    } else {
                        resultElementType = extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                    }
                    typeArguments = [collectionElementType, resultElementType, nonNullableDestinationType]
                }
                _ = bindBundledSequenceDestinationSourceFunction(typeArguments: typeArguments, locals: &locals)
            }
            if isMapReceiver,
               ["filterTo", "filterNotTo", "mapTo", "mapNotNullTo", "mapKeysTo", "mapValuesTo"].contains(calleeStr)
            {
                _ = bindBundledMapSourceFunction(locals: &locals)
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }
}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
