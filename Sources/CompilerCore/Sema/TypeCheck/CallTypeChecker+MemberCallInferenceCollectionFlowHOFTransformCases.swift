// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func inferCollectionHOFTransformCases(locals: inout LocalBindings) -> TypeID? {
        switch calleeStr {
        case "indexOf":
            if !isIterableIndexReceiver {
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    didReturnNil = true
                    return nil
                }
            }
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.intType)
                return sema.types.intType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
            resultType = sema.types.intType
            if isIterableIndexReceiver {
                _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            } else {
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            }

        case "lastIndexOf":
            if isCollectionReceiver,
               !isSequenceReceiver,
               !receiverClassifier.isConcreteListLikeType(receiverType),
               !isListFactoryReceiver
            {
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                resultType = sema.types.intType
                _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            } else {
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    didReturnNil = true
                    return nil
                }
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                resultType = sema.types.intType
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            }

        case "contains":
            didReturnNil = true
            return nil

        case "containsAll":
            guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                didReturnNil = true
                return nil
            }
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.booleanType)
                return sema.types.booleanType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.anyType)
            resultType = sema.types.booleanType
            _ = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)

        case "findLast", "firstOrNull", "lastOrNull":
            if calleeStr == "lastOrNull",
               isCollectionReceiver,
               !isSequenceReceiver,
               !receiverClassifier.isConcreteListLikeType(receiverType),
               !isListFactoryReceiver
            {
                if args.isEmpty {
                    resultType = sema.types.makeNullable(collectionElementType)
                    _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                } else if args.count == 1 {
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.booleanType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultType = sema.types.makeNullable(collectionElementType)
                    if bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                } else {
                    sema.bindings.bindExprType(id, type: sema.types.makeNullable(collectionElementType))
                    return sema.types.makeNullable(collectionElementType)
                }
            } else {
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    didReturnNil = true
                    return nil
                }
                if args.isEmpty {
                    resultType = sema.types.makeNullable(collectionElementType)
                    _ = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                } else if args.count == 1 {
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.booleanType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultType = sema.types.makeNullable(collectionElementType)
                    if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                } else {
                    sema.bindings.bindExprType(id, type: sema.types.makeNullable(collectionElementType))
                    return sema.types.makeNullable(collectionElementType)
                }
            }

        case "map", "filter", "filterNot", "filterKeys", "filterValues", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
             "count", "first", "last", "single", "singleOrNull", "find", "associateBy", "associateWith", "associate",
             "mapValues", "mapKeys", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "onEach", "distinct", "withIndex", "filterNotNull", "requireNoNulls", "asSequence", "sum", "average", "reversed", "asReversed":
            // any(), none(), count(), first(), last() can be called with no args
            if args.isEmpty {
                switch calleeStr {
                case "any", "none": resultType = sema.types.booleanType
                case "count": resultType = sema.types.intType
                case "first", "last", "single":
                    resultType = collectionElementType
                case "singleOrNull":
                    resultType = sema.types.makeNullable(collectionElementType)
                case "find": resultType = sema.types.makeNullable(collectionElementType)
                case "withIndex":
                    let indexedValueSymbol = lookupStdlibSymbol("IndexedValue", symbols: sema.symbols, interner: interner)
                    let indexedValueType: TypeID = if let indexedValueSymbol {
                        sema.types.make(.classType(ClassType(
                            classSymbol: indexedValueSymbol,
                            args: [.out(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        sema.types.anyType
                    }
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: indexedValueType
                        )
                        _ = bindBundledSequenceSourceIfAvailable(
                            resultType: resultType,
                            overrideTypeArguments: [collectionElementType]
                        , locals: &locals)
                    } else if bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals),
                              let iterableSymbol = lookupStdlibSymbol("Iterable", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: iterableSymbol,
                            args: [.out(indexedValueType)],
                            nullability: .nonNull
                        )))
                    } else if let iterableSymbol = lookupStdlibSymbol("Iterable", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: iterableSymbol,
                            args: [.out(indexedValueType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                case "filterNotNull", "requireNoNulls":
                    let nonNullElementType = sema.types.makeNonNullable(collectionElementType)
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: nonNullElementType
                        )
                    } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(nonNullElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                case "asSequence":
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                    _ = bindBundledAsSequenceSourceIfAvailable(typeArguments: [collectionElementType], locals: &locals)
                case "distinct":
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                    } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                case "sum":
                    // KSP-1359: a Sequence receiver binds the bundled
                    // monomorphic Sequence<E>.sum() overload matching its
                    // element type, and the call's result is that
                    // overload's declared return type (UInt/ULong included)
                    // rather than the historical hard-wired Int.
                    resultType = (isSequenceReceiver
                        ? bindBundledSequenceSumSource(locals: &locals)
                        : bindBundledIterableSumSource(locals: &locals)) ?? sema.types.intType
                case "average":
                    resultType = sema.types.doubleType
                case "reversed", "asReversed":
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                    } else {
                        resultType = receiverType
                    }
                case "flatten":
                    let innerElementType = extractIterableOrSequenceElementType(
                        collectionElementType,
                        sema: sema,
                        interner: interner
                    )
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: innerElementType
                        )
                    } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(innerElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                default: resultType = sema.types.anyType
                }
                if ["any", "none", "first", "last", "single", "singleOrNull"].contains(calleeStr) {
                    let didBindListSource = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType]
                    , locals: &locals)
                    if !didBindListSource,
                       ["first", "last"].contains(calleeStr),
                       !(calleeStr == "first" && isSetReceiver)
                    {
                        // Collection<T> and map.values use the generic
                        // Iterable<T> source implementation when no more
                        // specific List/Set overload is applicable.
                        _ = bindBundledIterableSourceFunction(
                            typeArguments: [collectionElementType]
                        , locals: &locals)
                    }
                }
                if isMapReceiver, calleeStr == "none" {
                    // KSP-1016: bind the zero-argument Map overload to its
                    // bundled source symbol instead of the name-only fallback.
                    _ = bindBundledMapSourceFunction(locals: &locals)
                }
                if calleeStr == "sum", !isSequenceReceiver, !isRangeReceiver {
                    if receiverClassifier.isConcreteListLikeType(receiverType) {
                        let bound = bindBundledListSourceFunction(
                            typeArguments: [],
                            receiverElementType: collectionElementType
                        , locals: &locals)
                        // KSP-994 regression: `Deferred<T>.await()` can't recover `T`
                        // statically (Deferred has no class-level type parameter; see
                        // CallTypeChecker+CoroutineBuilderReturnType.swift), so a
                        // `List<Deferred<T>>` mapped through `.map { it.await() }`
                        // erases its element type to `Any` here. None of the
                        // monomorphic `sum()` overloads declare an `Any` element, so
                        // the call above never binds and would otherwise reach
                        // codegen as an unresolved `sum` callee (link failure).
                        // Fall back to the pre-migration assumption that an unknown
                        // element type is `Int`, matching historical behavior.
                        if !bound, collectionElementType == sema.types.anyType {
                            _ = bindBundledListSourceFunction(
                                typeArguments: [],
                                receiverElementType: sema.types.intType
                            , locals: &locals)
                        } else if !bound {
                            // BUG-256: ListCollectionOps.kt only declares a
                            // concrete `List<Int>.sum()` overload, so every
                            // other element type (UInt, ULong, Long,
                            // Double, ...) falls back to the generic
                            // Iterable<T>.sum() family instead of being
                            // left unbound (which used to reach codegen as
                            // an unresolved `sum` callee and fail at link
                            // time).
                            _ = bindBundledIterableSumSource(locals: &locals)
                        }
                    } else {
                        _ = bindBundledIterableSumSource(locals: &locals)
                    }
                }
                if calleeStr == "average", !isSequenceReceiver {
                    // KSP-965: prefer the existing List overloads, then bind
                    // the numeric Iterable overload matching the element type.
                    let didBindAverageSource = if bindBundledListSourceFunction(
                        typeArguments: [],
                        receiverElementType: collectionElementType
                    , locals: &locals) {
                        true
                    } else {
                        bindBundledIterableSourceFunction(
                            typeArguments: [collectionElementType],
                            receiverElementType: collectionElementType
                        , locals: &locals)
                    }
                    if !didBindAverageSource,
                       isIterableReceiver,
                       !isArrayReceiver
                    {
                        // Iterable.average() is defined only for the six
                        // non-null numeric element types. Do not let the
                        // legacy name-based fallback accept String, nullable,
                        // or otherwise unsupported Iterable receivers.
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
                }
                if calleeStr == "reversed", !isSequenceReceiver {
                    _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                }
                if calleeStr == "asReversed", !isSequenceReceiver {
                    _ = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                }
                if calleeStr == "distinct", !isSequenceReceiver {
                    _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                }
                if calleeStr == "withIndex", !isSequenceReceiver {
                    _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                }
            } else {
                let lambdaReturnType: TypeID = switch calleeStr {
                case "filter", "filterNot", "filterKeys", "filterValues", "any", "none", "all", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "find", "first", "last", "single", "singleOrNull": sema.types.booleanType
                case "forEach", "onEach": sema.types.unitType
                case "count": sema.types.booleanType
                case "map", "mapKeys", "mapValues", "associateBy", "associateWith",
                     "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull": sema.types.nullableAnyType
                default: sema.types.anyType
                }
                let lambdaParameterTypes: [TypeID] = switch calleeStr {
                case "flatMapIndexed":
                    [sema.types.intType, collectionElementType]
                case "filterKeys":
                    [collectionMapTypes.key]
                case "filterValues":
                    [collectionMapTypes.value]
                default:
                    [collectionElementType]
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: lambdaParameterTypes,
                    returnType: lambdaReturnType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)

                switch calleeStr {
                case "map", "mapNotNull":
                    let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                        sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                    } else if case .callableRef = ast.arena.expr(args[0].expr),
                              case let .symbol(refTarget)? = sema.bindings.callableTarget(for: args[0].expr),
                              let refReturnType = sema.symbols.functionSignature(for: refTarget)?.returnType,
                              !sema.types.typeContainsAnyTypeParam(refReturnType)
                    {
                        // The callable reference is inferred against the
                        // placeholder `(T) -> Any` expected type, which the
                        // reference then adopts as its own type. Take the
                        // result element type from the resolved target
                        // instead, so `map(::mk)` yields `List<Top>`.
                        refReturnType
                    } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    let resultElementType = calleeStr == "mapNotNull"
                        ? sema.types.makeNonNullable(bodyType)
                        : bodyType
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: resultElementType
                        )
                    } else {
                        if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: listSymbol,
                                args: [.invariant(resultElementType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    }
                    let didBindListSource = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType, resultElementType]
                    , locals: &locals)
                    let didBindIterableSource: Bool
                    if !didBindListSource,
                       !isSequenceReceiver,
                       !isArrayReceiver,
                       !isMapReceiver,
                       !(calleeStr == "map" && isSetReceiver),
                       !(calleeStr == "mapNotNull" && isSetReceiver)
                    {
                        didBindIterableSource = bindBundledIterableSourceFunction(
                            typeArguments: [collectionElementType, resultElementType]
                        , locals: &locals)
                    } else {
                        didBindIterableSource = false
                    }
                    if didBindListSource || didBindIterableSource {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                case "filter", "filterNot":
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                    } else if isMapReceiver {
                        // Map.filter/filterNot return Map<K, V>, not List<Map.Entry<K, V>>.
                        resultType = receiverType
                    } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = receiverType
                    }
                    if calleeStr == "filter",
                       bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                    {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                case "takeLastWhile":
                    if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = receiverType
                    }
                    if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                case "takeWhile", "dropWhile", "dropLastWhile":
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                    } else {
                        resultType = receiverType
                    }
                    if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                case "forEach":
                    resultType = sema.types.unitType
                    if bindBundledIterableSourceFunction(
                        typeArguments: [collectionElementType],
                        allowNominalIterableReceiver: true,
                        allowConcreteForEachReceiver: true
                    , locals: &locals),
                       let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                case "onEach":
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: collectionElementType
                        )
                    } else {
                        resultType = receiverType
                    }
                    if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                case "flatMap":
                    let lambdaBodyType = inferredLambdaReturnType(
                        argExpr: args[0].expr, ast: ast, sema: sema
                    )
                    let innerElementType = extractIterableOrSequenceElementType(
                        lambdaBodyType, sema: sema, interner: interner
                    )
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: innerElementType
                        )
                    } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(innerElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                    let boundIterableSource = bindBundledIterableFlatMapSourceFunction(
                        collectionElementType: collectionElementType,
                        resultElementType: innerElementType,
                        returnsSequence: receiverClassifier.isSequenceLikeType(lambdaBodyType)
                    , locals: &locals)
                    if !boundIterableSource,
                       bindBundledListSourceFunction(typeArguments: [collectionElementType, innerElementType], locals: &locals)
                    {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                case "flatMapIndexed":
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [sema.types.intType, collectionElementType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    let lambdaBodyType = inferredLambdaReturnType(
                        argExpr: args[0].expr, ast: ast, sema: sema
                    )
                    let innerElementType = extractIterableOrSequenceElementType(
                        lambdaBodyType,
                        sema: sema,
                        interner: interner
                    )
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: innerElementType
                        )
                    } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(innerElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                    let boundIterableSource = bindBundledIterableFlatMapSourceFunction(
                        collectionElementType: collectionElementType,
                        resultElementType: innerElementType,
                        returnsSequence: receiverClassifier.isSequenceLikeType(lambdaBodyType)
                    , locals: &locals)
                    if !boundIterableSource,
                       bindBundledListSourceFunction(typeArguments: [collectionElementType, innerElementType], locals: &locals)
                    {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                case "any", "none", "all": resultType = sema.types.booleanType
                case "count": resultType = sema.types.intType
                case "first", "last", "single": resultType = collectionElementType
                case "singleOrNull": resultType = sema.types.makeNullable(collectionElementType)
                case "find": resultType = sema.types.makeNullable(collectionElementType)
                case "associateBy":
                    if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                        let keyType = inferredLambdaReturnType(
                            argExpr: args[0].expr, ast: ast, sema: sema
                        )
                        let valueType: TypeID
                        if args.count >= 2 {
                            let valueLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                                params: [collectionElementType],
                                returnType: sema.types.nullableAnyType
                            )))
                            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                            }
                            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: valueLambdaExpectedType)
                            valueType = inferredLambdaReturnType(
                                argExpr: args[1].expr, ast: ast, sema: sema
                            )
                        } else {
                            valueType = collectionElementType
                        }
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(keyType), .invariant(valueType)],
                            nullability: .nonNull
                        )))
                        if isSequenceReceiver {
                            sourceBackedSequenceAggregateTypeArguments = args.count >= 2
                                ? [collectionElementType, keyType, valueType]
                                : [collectionElementType, keyType]
                        }
                        let associateByTypeArgs: [TypeID] = args.count >= 2
                            ? [collectionElementType, keyType, valueType]
                            : [collectionElementType, keyType]
                        if bindBundledListSourceFunction(typeArguments: associateByTypeArgs, locals: &locals)
                            || bindBundledIterableSourceFunction(typeArguments: associateByTypeArgs, locals: &locals) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                            if args.count >= 2,
                               let lambdaExpr = ast.arena.expr(args[1].expr),
                               lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                            }
                        }
                    } else {
                        resultType = sema.types.anyType
                    }
                case "associateWith":
                    if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                        let valueType = inferredLambdaReturnType(
                            argExpr: args[0].expr, ast: ast, sema: sema
                        )
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(collectionElementType), .invariant(valueType)],
                            nullability: .nonNull
                        )))
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType, valueType], locals: &locals)
                            || bindBundledIterableSourceFunction(typeArguments: [collectionElementType, valueType], locals: &locals) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    } else {
                        resultType = sema.types.anyType
                    }
                case "associate":
                    if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                        let lambdaBodyType = inferredLambdaReturnType(
                            argExpr: args[0].expr, ast: ast, sema: sema
                        )
                        let nonNullBodyType = sema.types.makeNonNullable(lambdaBodyType)
                        let keyType: TypeID
                        let valueType: TypeID
                        if let (pairClass, pairSym) = resolveClassTypeSymbol(nonNullBodyType, sema: sema),
                           pairClass.args.count == 2,
                           pairSym.name == interner.intern("Pair")
                        {
                            keyType = switch pairClass.args[0] {
                            case let .invariant(id), let .out(id), let .in(id): id
                            case .star: sema.types.anyType
                            }
                            valueType = switch pairClass.args[1] {
                            case let .invariant(id), let .out(id), let .in(id): id
                            case .star: sema.types.anyType
                            }
                        } else {
                            keyType = sema.types.anyType
                            valueType = sema.types.anyType
                        }
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(keyType), .invariant(valueType)],
                            nullability: .nonNull
                        )))
                        if isSequenceReceiver {
                            sourceBackedSequenceAggregateTypeArguments = [collectionElementType, keyType, valueType]
                        }
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType, keyType, valueType], locals: &locals)
                            || bindBundledIterableSourceFunction(typeArguments: [collectionElementType, keyType, valueType], locals: &locals) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    } else {
                        resultType = sema.types.anyType
                    }
                case "mapValues" where isMapReceiver:
                    let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                        sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                    } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    let keyType: TypeID = if let classType = resolveClassType(receiverType, sema: sema),
                                             classType.args.count >= 2
                    {
                        switch classType.args[0] {
                        case let .invariant(id), let .out(id), let .in(id): id
                        case .star: sema.types.anyType
                        }
                    } else {
                        sema.types.anyType
                    }
                    if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(keyType), .invariant(bodyType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                case "mapKeys" where isMapReceiver:
                    let bodyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                        sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                    } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    let valueType: TypeID = if let classType = resolveClassType(receiverType, sema: sema),
                                               classType.args.count >= 2
                    {
                        switch classType.args[1] {
                        case let .invariant(id), let .out(id), let .in(id): id
                        case .star: sema.types.anyType
                        }
                    } else {
                        sema.types.anyType
                    }
                    if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(bodyType), .invariant(valueType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                case "filterKeys" where isMapReceiver:
                    resultType = sema.types.makeNonNullable(receiverType)
                case "filterValues" where isMapReceiver:
                    resultType = sema.types.makeNonNullable(receiverType)
                case "firstNotNullOf":
                    resultType = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                        sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                    } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                        sema.types.makeNonNullable(fnType.returnType)
                    } else {
                        sema.types.anyType
                    }
                case "firstNotNullOfOrNull":
                    if let expectedType {
                        resultType = sema.types.makeNullable(sema.types.makeNonNullable(expectedType))
                    } else if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                        resultType = sema.types.makeNullable(sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType))
                    } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                        resultType = sema.types.makeNullable(sema.types.makeNonNullable(fnType.returnType))
                    } else {
                        resultType = sema.types.nullableAnyType
                    }
                default: resultType = sema.types.anyType
                }

                if ["any", "none", "all", "count", "find", "first", "last", "single", "singleOrNull"].contains(calleeStr) {
                    let didBindListSource = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType]
                    , locals: &locals)
                    let didBindIterableSource = !didBindListSource
                        && ["first", "last", "find"].contains(calleeStr)
                        && bindBundledIterableSourceFunction(
                            typeArguments: [collectionElementType]
                        , locals: &locals)
                    if didBindListSource || didBindIterableSource {
                        if args.count == 1, let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                }

                if isMapReceiver {
                    _ = bindBundledMapSourceFunction(locals: &locals)
                }
            }

            default:
                break
        }
        return nil
    }
}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
