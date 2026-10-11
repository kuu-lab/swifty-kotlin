// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func inferCollectionHOFSumAndMiscCases(locals: inout LocalBindings) -> TypeID? {
        switch calleeStr {
        case "flatten":
            // Sequence<Iterable<T>> / List<List<T>> etc.: one-level flatten → element type T
            guard args.isEmpty else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            // If the receiver call has explicit type arguments (e.g. listOf<Int>())
            // and the explicit element type is a known non-collection, flatten() is
            // invalid — reject before the type-inference result can mask the error.
            // This handles cases where kswiftc infers List<Any> despite <Int> being
            // written explicitly (type-inference gap for empty collection literals).
            if !isSequenceReceiver,
               let receiverExpr = ast.arena.expr(receiverID),
               case let .call(_, receiverTypeArgs, _, _) = receiverExpr,
               let firstTypeArgID = receiverTypeArgs.first
            {
                let explicitElemType = driver.helpers.resolveTypeRef(firstTypeArgID, ast: ast, sema: sema, interner: interner)
                if !receiverClassifier.isCollectionLikeType(explicitElemType) {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "Unresolved member function 'flatten'.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
            }
            let extractedInner = getCollectionElementType(collectionElementType, sema: sema, interner: interner)
            // Reject when the element type is a KNOWN non-collection (e.g. Int).
            if !isSequenceReceiver && extractedInner == sema.types.anyType
                && collectionElementType != sema.types.anyType
                && !receiverClassifier.isCollectionLikeType(collectionElementType) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "Unresolved member function 'flatten'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            // KUU-461 / BUG-237: on a Sequence receiver, flatten() only
            // exists as Sequence<Iterable<T>>.flatten() or
            // Sequence<Sequence<T>>.flatten(). Accept the call only when
            // the element type satisfies exactly one of those
            // constraints: Sequence<Any>, Sequence<Int>, or an
            // unbounded type parameter satisfies neither (kotlinc:
            // cannot infer the type parameter), while Sequence<Nothing>
            // or a type implementing both Iterable and Sequence
            // satisfies both (kotlinc: overload ambiguity). errorType
            // stays lenient — the element failure was already diagnosed
            // upstream.
            if isSequenceReceiver, collectionElementType != sema.types.errorType {
                let flattenSourcePackages: [[InternedString]] = [
                    [interner.intern("kotlin"), interner.intern("sequences")],
                    [interner.intern("kotlin"), interner.intern("collections")],
                ]
                var satisfiedConstraintCount = 0
                for packageFQName in flattenSourcePackages {
                    for candidate in sema.symbols.lookupAll(fqName: packageFQName + [calleeName]) {
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              sema.symbols.isSourceBackedSymbol(candidate),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              signature.parameterTypes.isEmpty,
                              let signatureReceiver = signature.receiverType,
                              receiverClassifier.isSequenceLikeType(signatureReceiver),
                              let (elementOwnerClassType, _) = resolveClassTypeSymbol(
                                  getCollectionElementType(signatureReceiver, sema: sema, interner: interner),
                                  sema: sema
                              )
                        else {
                            continue
                        }
                        let constraint = sema.types.make(.classType(ClassType(
                            classSymbol: elementOwnerClassType.classSymbol,
                            args: [.star],
                            nullability: .nonNull
                        )))
                        if sema.types.isSubtype(collectionElementType, constraint) {
                            satisfiedConstraintCount += 1
                        }
                    }
                }
                if satisfiedConstraintCount != 1 {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "Unresolved member function 'flatten'.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
            }
            let flattenedElementType = extractedInner != sema.types.anyType
                ? extractedInner
                : collectionElementType
            if isSequenceReceiver {
                resultType = makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: flattenedElementType
                )
            } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                resultType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(flattenedElementType)],
                    nullability: .nonNull
                )))
            } else {
                resultType = sema.types.anyType
            }
            if !isSequenceReceiver {
                // List.flatten and Iterable.flatten share the public name,
                // but the statically Iterable path must not fall through
                // without a source-backed callee binding.
                _ = bindBundledListSourceFunction(typeArguments: [flattenedElementType], locals: &locals)
                    || bindBundledIterableSourceFunction(typeArguments: [flattenedElementType], locals: &locals)
            }

        case "zipWithNext":
            if args.isEmpty {
                guard explicitTypeArgs.isEmpty else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                    let pairType = sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.invariant(collectionElementType), .invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                    if isSequenceReceiver {
                        resultType = makeSyntheticSequenceType(
                            symbols: sema.symbols,
                            types: sema.types,
                            interner: interner,
                            elementType: pairType
                        )
                        _ = bindBundledSequenceSourceIfAvailable(
                            resultType: resultType,
                            overrideTypeArguments: [collectionElementType]
                        , locals: &locals)
                    } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(pairType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                } else {
                    resultType = sema.types.anyType
                }
            } else {
                // zipWithNext(transform: (T, T) -> R): List<R>
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                guard explicitTypeArgs.count <= 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaReturnType = explicitTypeArgs.first ?? sema.types.anyType
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: lambdaReturnType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let bodyType = explicitTypeArgs.first
                    ?? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: bodyType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(bodyType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
            }

        case "indexOfFirst", "indexOfLast":
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.intType)
                return sema.types.intType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.booleanType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            resultType = sema.types.intType
            let didBindSource = if isIterableIndexReceiver {
                bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            } else {
                bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            }
            if didBindSource {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }

        case "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed", "onEachIndexed":
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            let lambdaReturnType: TypeID = switch calleeStr {
            case "forEachIndexed", "onEachIndexed":
                sema.types.unitType
            case "filterIndexed":
                sema.types.booleanType
            case "mapIndexedNotNull":
                sema.types.nullableAnyType
            default:
                sema.types.nullableAnyType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, collectionElementType],
                returnType: lambdaReturnType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            if calleeStr == "forEachIndexed" {
                resultType = sema.types.unitType
                // KSP-626: bind the bundled Iterable<T>.forEachIndexed source function.
                if bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals),
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            } else if calleeStr == "onEachIndexed" {
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
            } else if calleeStr == "filterIndexed" {
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
                    resultType = receiverType
                }
            } else if isSequenceReceiver {
                let inferredBodyType = inferredLambdaReturnType(
                    argExpr: args[0].expr, ast: ast, sema: sema
                )
                let bodyType = calleeStr == "mapIndexedNotNull"
                    ? sema.types.makeNonNullable(inferredBodyType)
                    : inferredBodyType
                resultType = makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: bodyType
                )
            } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                let inferredBodyType = inferredLambdaReturnType(
                    argExpr: args[0].expr, ast: ast, sema: sema
                )
                let bodyType = calleeStr == "mapIndexedNotNull"
                    ? sema.types.makeNonNullable(inferredBodyType)
                    : inferredBodyType
                resultType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(bodyType)],
                    nullability: .nonNull
                )))
                if calleeStr == "mapIndexed" || calleeStr == "mapIndexedNotNull" {
                    let didBindListSource = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType, bodyType]
                    , locals: &locals)
                    let didBindIterableSource: Bool
                    if !didBindListSource, !isArrayReceiver, !isMapReceiver {
                        didBindIterableSource = bindBundledIterableSourceFunction(
                            typeArguments: [collectionElementType, bodyType]
                        , locals: &locals)
                    } else {
                        didBindIterableSource = false
                    }
                    if didBindListSource || didBindIterableSource {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                }
            } else {
                resultType = sema.types.anyType
            }

        case "sumOf", "sumBy":
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            if calleeStr == "sumOf",
               let iterableSumOfType = bindBundledIterableSumOfSource(locals: &locals)
            {
                resultType = iterableSumOfType
                break
            }
            let isListSumOf = calleeStr == "sumOf"
                && (receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver)
            // KSP-1359: a Sequence receiver's sumOf selector is likewise
            // inferred against Any so its concrete return type can pick the
            // matching bundled overload below.
            let isSequenceSumOf = calleeStr == "sumOf" && isSequenceReceiver
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: (isListSumOf || isSequenceSumOf) ? sema.types.anyType : sema.types.intType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let selectorType = (isListSumOf || isSequenceSumOf)
                ? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                : sema.types.intType
            // BUG-256 sibling: List<T>.sumOf only has Int/Long/Double
            // concrete overloads (ListAggregateHOF.kt); UInt/ULong
            // selectors have no concrete List overload and must fall
            // back to the generic Iterable<T>.sumOf family below
            // instead of being silently arity-matched onto the wrong
            // (Int) overload.
            let supportedListSumOfType = selectorType == sema.types.intType
                || selectorType == sema.types.longType
                || selectorType == sema.types.doubleType
            let selectorHasIterableSumOfOverload = supportedListSumOfType
                || selectorType == sema.types.uintType
                || selectorType == sema.types.ulongType
            if isSequenceReceiver {
                if calleeStr == "sumOf" {
                    // KSP-1359: bind the bundled Sequence<T>.sumOf overload
                    // matching the inferred selector return type
                    // (Int/Long/Double/UInt/ULong). An unsupported selector
                    // type has no viable overload upstream and must not
                    // fall through to the first-arity-match binder.
                    guard let sequenceSumOfType = bindSequenceSumOfSourceForSelectorType(
                        selectorReturnType: selectorType
                    , locals: &locals) else {
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
                    resultType = sequenceSumOfType
                    if case .lambdaLiteral = ast.arena.expr(args[0].expr) {
                        // Same lambda-type restoration as the List branch:
                        // the boxed selector's result ABI must match the
                        // bound overload's primitive return type.
                        sema.bindings.bindExprType(
                            args[0].expr,
                            type: sema.types.make(.functionType(FunctionType(
                                params: [collectionElementType],
                                returnType: selectorType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        )
                    }
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else {
                    resultType = sema.types.intType
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }
            } else {
                // KUU-1358: upstream exposes only the
                // Int/Long/Double/UInt/ULong selector overloads, so a
                // selector return type outside that family (Float,
                // String, Any, ...) has no viable overload and upstream
                // rejects the call. Arity-matching the first (Int)
                // List.sumOf overload instead silently accumulated the
                // boxed selector result as Int bits and printed garbage.
                if isListSumOf,
                   !selectorHasIterableSumOfOverload,
                   selectorType != sema.types.errorType
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
                resultType = isListSumOf && selectorHasIterableSumOfOverload
                    ? selectorType
                    : sema.types.intType
                if isListSumOf,
                   selectorHasIterableSumOfOverload,
                   case .lambdaLiteral = ast.arena.expr(args[0].expr)
                {
                    // The temporary Any return type above supplies the lambda's
                    // input type while its body is inferred. Restore the
                    // concrete selector type before KIR lowering so the closure
                    // ABI remains raw for primitive results such as Double.
                    sema.bindings.bindExprType(
                        args[0].expr,
                        type: sema.types.make(.functionType(FunctionType(
                            params: [collectionElementType],
                            returnType: selectorType,
                            isSuspend: false,
                            nullability: .nonNull
                        )))
                    )
                }
                var didBindSource = calleeStr == "sumOf"
                    ? bindBundledListSourceFunction(
                        typeArguments: [collectionElementType],
                        matchingParameterType: isListSumOf && selectorHasIterableSumOfOverload
                            ? sema.types.make(.functionType(FunctionType(
                                params: [collectionElementType],
                                returnType: selectorType
                            )))
                            : nil
                    , locals: &locals)
                    : bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                // BUG-256 sibling: a concrete List<T> receiver whose
                // selector return type has no List<T>.sumOf overload
                // (UInt/ULong) never matches above. Fall back to the
                // generic Iterable<T>.sumOf family instead of leaving
                // the call unbound. The lambda was already inferred
                // above against this same selectorType, so bind
                // directly by that known type rather than calling
                // bindBundledIterableSumOfSource() (which would
                // re-infer the same lambda expr).
                if !didBindSource,
                   calleeStr == "sumOf",
                   isListSumOf,
                   !supportedListSumOfType,
                   selectorHasIterableSumOfOverload,
                   bindIterableSumOfSourceForSelectorType(
                       collectionElementType: collectionElementType,
                       selectorReturnType: selectorType
                   , locals: &locals) != nil
                {
                    // resultType is already `selectorType` from the
                    // isListSumOf/selectorHasIterableSumOfOverload branch
                    // above -- the matched Iterable<T>.sumOf overload's
                    // return type is that same selectorType by construction.
                    didBindSource = true
                }
                if didBindSource,
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }

        case "intersect", "union", "subtract":
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.anyType)
            if let setSymbol = lookupStdlibSymbol("Set", symbols: sema.symbols, interner: interner) {
                resultType = sema.types.make(.classType(ClassType(
                    classSymbol: setSymbol,
                    args: [.out(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                resultType = sema.types.anyType
            }
            _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)

        case "sumByDouble":
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.doubleType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            resultType = sema.types.doubleType
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            } else {
                let didBindSource = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                if didBindSource,
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }

        case "max", "min", "maxOrNull", "minOrNull":
            guard args.isEmpty else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                let comparableElementType = sema.types.make(.classType(ClassType(
                    classSymbol: comparableSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
                if !sema.types.isSubtype(collectionElementType, comparableElementType) {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-BOUND",
                        "Type argument does not satisfy upper bound constraint.",
                        range: ast.arena.exprRange(id)
                    )
                    let failedType = safeCall ? sema.types.nullableAnyType : sema.types.anyType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
            }
            // KUU-553/KUU-542: concrete Float/Double receivers must use the
            // exact Iterable overloads. The generic List<T> declarations
            // erase the floating-point specialization before code generation.
            let isFloatingPointElement = collectionElementType == sema.types.doubleType
                || collectionElementType == sema.types.floatType
            if !isFloatingPointElement {
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            }
            sourceBackedIterableAggregateTypeArguments = isFloatingPointElement
                ? []
                : [collectionElementType]
            resultType = (calleeStr == "max" || calleeStr == "min")
                ? collectionElementType
                : sema.types.makeNullable(collectionElementType)

        case "maxBy", "minBy", "maxByOrNull", "minByOrNull":
            guard args.count == 1 else {
                let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                sema.bindings.bindExprType(id, type: failedType)
                return failedType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.anyType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let selectorType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
            } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                      case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
            {
                sema.types.makeNonNullable(fnType.returnType)
            } else {
                sema.types.anyType
            }
            do {
                let primitiveComparableTypes: Set<TypeID> = [
                    sema.types.intType,
                    sema.types.longType,
                    sema.types.floatType,
                    sema.types.doubleType,
                    sema.types.charType,
                    sema.types.stringType,
                    sema.types.make(.primitive(.uint, .nonNull)),
                    sema.types.make(.primitive(.ulong, .nonNull)),
                ]
                let isPrimitiveComparable = primitiveComparableTypes.contains(selectorType)
                let isNominalComparable: Bool
                if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                    let comparableSelectorType = sema.types.make(.classType(ClassType(
                        classSymbol: comparableSymbol,
                        args: [.invariant(selectorType)],
                        nullability: .nonNull
                    )))
                    isNominalComparable = sema.types.isSubtype(selectorType, comparableSelectorType)
                } else {
                    isNominalComparable = false
                }
                if selectorType != sema.types.anyType, !isPrimitiveComparable, !isNominalComparable {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-BOUND",
                        "Type argument does not satisfy upper bound constraint.",
                        range: ast.arena.exprRange(id)
                    )
                    let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
            }
            resultType = (calleeStr == "maxBy" || calleeStr == "minBy")
                ? collectionElementType
                : sema.types.makeNullable(collectionElementType)
            if (calleeStr == "maxByOrNull" || calleeStr == "minByOrNull"), isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, selectorType]
            }
            if isMapReceiver, calleeStr == "maxBy" || calleeStr == "minBy" {
                if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorType, locals: &locals),
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isMapReceiver, calleeStr == "maxByOrNull" || calleeStr == "minByOrNull" {
                _ = bindBundledMapSourceFunction(locals: &locals)
            }
            sourceBackedIterableAggregateTypeArguments = [collectionElementType, selectorType]

        case "maxOf", "minOf":
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.anyType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let selectorType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
            } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                      case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
            {
                sema.types.makeNonNullable(fnType.returnType)
            } else {
                sema.types.anyType
            }
            if isMapReceiver, calleeStr == "maxOf" || calleeStr == "minOf" {
                if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorType, locals: &locals),
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            let sourceTypeArguments = selectorType == sema.types.doubleType || selectorType == sema.types.floatType
                ? [collectionElementType]
                : [collectionElementType, selectorType]
            sourceBackedIterableAggregateTypeArguments = sourceTypeArguments
            sourceBackedIterableAggregateMatchingParameterTypes = [sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: selectorType
            )))]
            resultType = selectorType

        case "maxOfOrNull", "minOfOrNull":
            guard args.count == 1 else {
                let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                sema.bindings.bindExprType(id, type: failedType)
                return failedType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.anyType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let selectorType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
            } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                      case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
            {
                sema.types.makeNonNullable(fnType.returnType)
            } else {
                sema.types.anyType
            }
            let selectorKind = sema.types.kind(of: selectorType)
            if case .typeParam = selectorKind {} else {
                do {
                    let primitiveComparableTypes: Set<TypeID> = [
                        sema.types.intType,
                        sema.types.longType,
                        sema.types.floatType,
                        sema.types.doubleType,
                        sema.types.charType,
                        sema.types.stringType,
                        sema.types.make(.primitive(.uint, .nonNull)),
                        sema.types.make(.primitive(.ulong, .nonNull)),
                    ]
                    let isPrimitiveComparable = primitiveComparableTypes.contains(selectorType)
                    let isNominalComparable: Bool
                    if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                        let comparableSelectorType = sema.types.make(.classType(ClassType(
                            classSymbol: comparableSymbol,
                            args: [.invariant(selectorType)],
                            nullability: .nonNull
                        )))
                        isNominalComparable = sema.types.isSubtype(selectorType, comparableSelectorType)
                    } else {
                        isNominalComparable = false
                    }
                    if selectorType != sema.types.anyType, !isPrimitiveComparable, !isNominalComparable {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-BOUND",
                            "Type argument does not satisfy upper bound constraint.",
                            range: ast.arena.exprRange(id)
                        )
                        let failedType = safeCall ? sema.types.makeNullable(sema.types.errorType) : sema.types.errorType
                        sema.bindings.bindExprType(id, type: failedType)
                        return failedType
                    }
                }
            }
            resultType = sema.types.makeNullable(selectorType)
            if isMapReceiver, calleeStr == "maxOfOrNull" || calleeStr == "minOfOrNull" {
                if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorType, locals: &locals),
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            let sourceTypeArguments = selectorType == sema.types.doubleType || selectorType == sema.types.floatType
                ? [collectionElementType]
                : [collectionElementType, selectorType]
            sourceBackedIterableAggregateTypeArguments = sourceTypeArguments
            sourceBackedIterableAggregateMatchingParameterTypes = [sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: selectorType
            )))]

        case "binarySearch":
            // STDLIB-547: binarySearch(comparison: (T) -> Int) overload.
            // STDLIB-COL-BSEARCH-002: binarySearch(element, comparator, fromIndex, toIndex).
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                nil
            }
            let binarySearchFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            func bindBinarySearchSource(parameterCount: Int, parameterMapping: [Int: Int]) {
                guard let chosenCallee = sema.symbols.lookupAll(fqName: binarySearchFQName).first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate),
                          let signatureReceiver = signature.receiverType
                    else { return false }
                    return sema.symbols.isSourceBackedSymbol(candidate)
                        && signature.parameterTypes.count == parameterCount
                        && receiverClassifier.isConcreteListLikeType(signatureReceiver)
                }) else {
                    return
                }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: [collectionElementType],
                    parameterMapping: parameterMapping
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            }

            if args.count == 1 {
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.intType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                } else {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                    bindBinarySearchSource(parameterCount: 3, parameterMapping: [0: 0])
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    bindBinarySearchSource(parameterCount: 1, parameterMapping: [0: 0])
                }
                resultType = sema.types.intType
            } else if (2 ... 4).contains(args.count) {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                let secondIsLambda = ast.arena.expr(args[1].expr)?.isLambdaOrCallableRef == true
                let secondType = sema.bindings.exprTypes[args[1].expr]
                    ?? driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
                let isNaturalRange = !secondIsLambda && secondType == sema.types.intType && args.count <= 3
                if isNaturalRange {
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                    if args.count == 3 {
                        _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                    }
                    bindBinarySearchSource(
                        parameterCount: 3,
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                } else if let comparatorLambdaExpr = ast.arena.expr(args[1].expr),
                          comparatorLambdaExpr.isLambdaOrCallableRef
                {
                    let comparatorLambdaType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: sema.types.intType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: comparatorLambdaType)
                } else {
                    _ = driver.inferExpr(
                        args[1].expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: comparatorExpectedType
                    )
                }
                if args.count >= 3 {
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                if args.count >= 4 {
                    _ = driver.inferExpr(args[3].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                if !isNaturalRange {
                    bindBinarySearchSource(
                        parameterCount: 4,
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    )
                }
                resultType = sema.types.intType
            } else {
                sema.bindings.bindExprType(id, type: sema.types.intType)
                return sema.types.intType
            }
            _ = bindBundledListBinarySearchSource(elementType: collectionElementType, locals: &locals)

        case "binarySearchBy":
            guard (2 ... 4).contains(args.count) else {
                sema.bindings.bindExprType(id, type: sema.types.intType)
                return sema.types.intType
            }
            let keyType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            if args.count >= 3 {
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            }
            if args.count == 4 {
                _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            }
            let selectorReturnType: TypeID = if keyType == sema.types.errorType {
                sema.types.nullableAnyType
            } else {
                switch sema.types.kind(of: keyType) {
                case .nothing:
                    sema.types.nullableAnyType
                default:
                    sema.types.makeNonNullable(keyType)
                }
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: selectorReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[args.count - 1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[args.count - 1].expr)
            }
            _ = driver.inferExpr(args[args.count - 1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            resultType = sema.types.intType
            if bindBundledListBinarySearchSource(elementType: collectionElementType, locals: &locals) {
                // The bundled selector returns an erased K, so use the
                // Kotlin function-value ABI rather than a raw HOF callback.
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[args.count - 1].expr)
            }

        case "distinctBy":
            guard args.count == 1 else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            // Match the synthetic stub: selector is (T) -> Any (non-null, non-suspend).
            // KNOWN LIMITATION: nullable keys are not supported; see stub comment.
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let keyType = inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
            if isSequenceReceiver {
                resultType = makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: collectionElementType
                )
                _ = bindBundledSequenceSourceIfAvailable(
                    resultType: resultType,
                    overrideTypeArguments: [collectionElementType, keyType]
                , locals: &locals)
            } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                resultType = sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                resultType = receiverType
            }
            if !isSequenceReceiver,
               bindBundledIterableSourceFunction(typeArguments: [collectionElementType, keyType], locals: &locals)
            {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }

        case "mapTo", "mapIndexedTo", "mapNotNullTo", "flatMapTo", "flatMapIndexedTo":
            guard args.count == 2 else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "\(calleeStr)() expects 2 arguments (destination and a lambda), but \(args.count) were supplied.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let destinationType = sema.bindings.exprTypes[args[0].expr] ?? sema.types.anyType
            let isIndexed = calleeStr == "mapIndexedTo" || calleeStr == "flatMapIndexedTo"
            let isMapNotNullTo = calleeStr == "mapNotNullTo"
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: isIndexed ? [sema.types.intType, collectionElementType] : [collectionElementType],
                returnType: isMapNotNullTo ? sema.types.nullableAnyType : sema.types.anyType
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let rawReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
            let resultElementType: TypeID
            if calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo" {
                resultElementType = extractListElementType(rawReturnType, sema: sema, interner: interner)
            } else if isMapNotNullTo {
                resultElementType = sema.types.makeNonNullable(rawReturnType)
            } else {
                resultElementType = rawReturnType
            }
            resultType = destinationType
            if bindBundledListSourceFunction(typeArguments: [collectionElementType, resultElementType, destinationType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                }
            }

        // The original single-switch `default:` assigned `anyType`. Because the
        // switch is split across three methods, a callee handled by an earlier
        // segment must not fall into this default and clobber `resultType`.
        // Unhandled callees are normalized in inferCollectionHOFSpecial after
        // all segments run.
        default:
            break
        }
        return nil
    }
}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
