// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    /// A nested factory/constructor destination whose own arguments could not
    /// fix one of its callee type parameters (`ArrayList(capacity)`, where no
    /// parameter mentions `E`) collapsed that parameter to its default `Any`
    /// bound on the standalone pass. kotlinc keeps such a variable inside the
    /// enclosing `C : MutableCollection<in T>` constraint instead, so the
    /// destination must be re-inferred under the bound the same way a
    /// `Nothing`-typed factory is (KUU-3917). Destinations whose arguments
    /// already fixed every type parameter — `mutableListOf(x)`, where `T`
    /// got a real lower bound — keep their first-pass type.
    func nestedDestinationCallLeavesTypeParametersUnfixed(_ expr: ExprID) -> Bool {
        checker.partiallyInferredNestedCallType(expr, ctx: ctx)
            .map { !$0.unboundTypeVarBySymbol.isEmpty } ?? false
    }

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
                    ctx.sema.diagnostics.emit(Diagnostic(
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
            //
            // The same deferral applies when the nested call's own arguments
            // left a type parameter unfixed and it collapsed to `Any` by
            // default: `ArrayList(capacity)` has no argument mentioning E, so
            // the standalone pass fixes E := Any. kotlinc instead keeps E in
            // the enclosing `C : MutableCollection<in T>` constraint, where
            // `MutableList<E> <: MutableCollection<in T>` contributes the
            // lower bound `T <: E` and E fixes to the element type — yielding
            // `ArrayList<T>`, not `ArrayList<Any>` (KUU-3917).
            let destinationNeedsDeferredInference = isInferableNestedCallExpr(args[0].expr, ast: ast)
                && (typeContainsNothingType(destinationElementType, sema: sema)
                    || typeContainsNothingType(destinationMapKeyType, sema: sema)
                    || typeContainsNothingType(destinationMapValueType, sema: sema)
                    || nestedDestinationCallLeavesTypeParametersUnfixed(args[0].expr))
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
            // Only the transforms that derive the destination bound from the
            // lambda's *result* type need the unconstrained expectation
            // below. The filter family always expects `Boolean` and reuses
            // the receiver's element type for the bound — loosening the
            // predicate to `Any?` boxes its Boolean result, and the inlined
            // bundled `if (predicate(element))` then compares a non-null
            // boxed pointer against `false`, appending every element
            // (KUU-3917).
            let lambdaReturnFeedsDestinationBound = ![
                "filterTo", "filterNotTo", "filterIndexedTo",
            ].contains(calleeStr)
            if destinationNeedsDeferredInference,
               lambdaReturnFeedsDestinationBound,
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
            func unwrappedTypeArgument(_ arg: TypeArg) -> TypeID {
                switch arg {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            }
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
                let reinferExpectedType: TypeID? = reinferBoundType.flatMap { boundType in
                    // kotlinc keeps the destination call's free type parameter
                    // inside the enclosing constraint set: the `in` bound only
                    // gives the element a *lower* bound (`T <: E`), while an
                    // expected `Collection<X>`/`MutableCollection<X>` gives it
                    // an upper bound. Prefer the bound-shaped
                    // re-parameterization — the smallest solution, e.g.
                    // `ArrayList<T>` for `ArrayList(capacity)` — and fall back
                    // to the expected-shaped one only when the bound-shaped
                    // type cannot satisfy the call's expected type (an
                    // expected `MutableCollection<Any>` demands `ArrayList<Any>`,
                    // which still satisfies `MutableCollection<in T>`).
                    let boundSteered = concreteNestedCallExpectedType(
                        originalArgumentType: nonNullableDestinationType,
                        boundType: boundType,
                        sema: sema
                    )
                    if let boundSteered,
                       expectedType == nil || sema.types.isSubtype(boundSteered, expectedType!)
                    {
                        return boundSteered
                    }
                    if let expectedType,
                       let expectedSteered = concreteNestedCallExpectedType(
                           originalArgumentType: nonNullableDestinationType,
                           boundType: expectedType,
                           sema: sema
                       ),
                       sema.types.isSubtype(expectedSteered, boundType)
                    {
                        return expectedSteered
                    }
                    return boundSteered
                }
                if let reinferExpectedType {
                    let reinferDiagnosticsCheckpoint = ctx.sema.diagnostics.checkpoint()
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
                        ctx.sema.diagnostics.rollback(to: reinferDiagnosticsCheckpoint)
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    }
                } else {
                    // No destination type could be derived (e.g. a non-Pair
                    // associateTo transform); restore the destination-shaped
                    // lambda expectation so the mismatch still diagnoses.
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                }
            }
            // The bound check above re-parameterized MutableCollection /
            // MutableMap with the destination's *own* arguments, so it only
            // proves the destination is a collection at all. kotlinc declares
            // the bound contravariantly — `C : MutableCollection<in T>` and
            // `M : MutableMap<in K, in V>` — which additionally requires the
            // destination element types to be *supertypes* of the element the
            // transform produces: `listOf("a").filterTo(ArrayList<Int>())`
            // must diagnose because `String` is not an `Int` (KUU-3955). The
            // produced element is only knowable after the transform lambda —
            // and any deferred factory destination — has been inferred, so
            // the contravariant check runs here, against the final
            // destination type.
            let boundLambdaReturnType: TypeID? = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[1].expr) {
                sema.bindings.exprType(for: bodyExpr)
            } else if let argType = sema.bindings.exprType(for: args[1].expr),
                      case let .functionType(argFunctionType) = sema.types.kind(of: argType)
            {
                argFunctionType.returnType
            } else {
                nil
            }
            // `nil` for a required bound argument means the call never fixed
            // it — an unbound transform result, or a receiver whose declared
            // type arguments are absent (`class L : MutableList<Int>` leaves
            // `collectionMapTypes`/`collectionElementType` at their `Any`
            // fallbacks, which are not evidence the bound demands `in Any`).
            // Checking anyway would reject destinations the bound does not
            // actually forbid.
            let receiverDeclaresMapArguments = resolveClassType(receiverType, sema: sema)
                .map { $0.args.count >= 2 } ?? false
            let receiverDeclaresElementArgument = collectionElementType != sema.types.anyType
                || (resolveClassType(receiverType, sema: sema).map { !$0.args.isEmpty } ?? false)
            let requiredMapTypes: (key: TypeID, value: TypeID)? = switch calleeStr {
            case "mapKeysTo":
                receiverDeclaresMapArguments
                    ? boundLambdaReturnType.map { (key: $0, value: collectionMapTypes.value) }
                    : nil
            case "mapValuesTo":
                receiverDeclaresMapArguments
                    ? boundLambdaReturnType.map { (key: collectionMapTypes.key, value: $0) }
                    : nil
            case "associateTo":
                {
                    guard let lambdaReturn = boundLambdaReturnType,
                          case let .classType(pairClassType) = sema.types.kind(
                              of: sema.types.makeNonNullable(lambdaReturn)
                          ),
                          pairClassType.args.count == 2
                    else {
                        return nil
                    }
                    return (
                        key: unwrappedTypeArgument(pairClassType.args[0]),
                        value: unwrappedTypeArgument(pairClassType.args[1])
                    )
                }()
            default:
                // Only map receivers' filterTo/filterNotTo take a MutableMap
                // destination; they copy matching entries, so the bound keeps
                // the receiver's own key/value types.
                receiverDeclaresMapArguments ? collectionMapTypes : nil
            }
            let requiredCollectionElement: TypeID? = switch calleeStr {
            case "filterTo", "filterNotTo", "filterIndexedTo":
                receiverDeclaresElementArgument ? collectionElementType : nil
            case "mapTo", "mapIndexedTo":
                boundLambdaReturnType
            case "mapNotNullTo", "mapIndexedNotNullTo":
                boundLambdaReturnType.map { sema.types.makeNonNullable($0) }
            case "flatMapTo", "flatMapIndexedTo":
                boundLambdaReturnType.flatMap { lambdaReturn -> TypeID? in
                    let extracted = !isSequenceReceiver && isIterableReceiver
                        && !receiverClassification.isListReceiver
                        && !receiverClassification.isSetReceiver
                        && !receiverClassification.isMapReceiver
                        ? extractIterableOrSequenceElementType(lambdaReturn, sema: sema, interner: interner)
                        : extractListElementType(lambdaReturn, sema: sema, interner: interner)
                    return extracted == sema.types.anyType ? nil : extracted
                }
            default:
                nil
            }
            let requiredDestinationBound: TypeID? = if destinationRequiresMutableMap {
                requiredMapTypes.flatMap { mapTypes in
                    lookupStdlibSymbol("MutableMap", symbols: sema.symbols, interner: interner).map { mutableMapSymbol in
                        sema.types.make(.classType(ClassType(
                            classSymbol: mutableMapSymbol,
                            args: [.in(mapTypes.key), .in(mapTypes.value)],
                            nullability: .nonNull
                        )))
                    }
                }
            } else {
                requiredCollectionElement.flatMap { elementType in
                    lookupStdlibSymbol("MutableCollection", symbols: sema.symbols, interner: interner).map { mutableCollectionSymbol in
                        sema.types.make(.classType(ClassType(
                            classSymbol: mutableCollectionSymbol,
                            args: [.in(elementType)],
                            nullability: .nonNull
                        )))
                    }
                }
            }
            // A destination still holding `Nothing` arguments is a factory
            // whose inference could not be completed — its element type is a
            // variable the bound may still fix, not a violation.
            if let requiredDestinationBound,
               !typeContainsNothingType(nonNullableDestinationType, sema: sema),
               !sema.types.isSubtype(nonNullableDestinationType, requiredDestinationBound)
            {
                let actualTypeName = sema.types.displayName(
                    of: destinationType,
                    symbols: sema.symbols,
                    interner: interner
                )
                let requiredTypeName = sema.types.displayName(
                    of: requiredDestinationBound,
                    symbols: sema.symbols,
                    interner: interner
                )
                ctx.sema.diagnostics.emit(Diagnostic(
                    severity: .error,
                    code: "KSWIFTK-TYPE-0001",
                    message: "Type mismatch: destination has type '\(actualTypeName)', but '\(requiredTypeName)' is required for '\(calleeStr)'.",
                    primaryRange: ast.arena.exprRange(args[0].expr) ?? range,
                    secondaryRanges: []
                ))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                }
                return sema.types.errorType
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
                ) || bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments) {
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
                )
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
                    )
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
                    )
                let didBindListSource: Bool
                if boundIterableDestination {
                    didBindListSource = false
                } else {
                    didBindListSource = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType, resultElementType, nonNullableDestinationType]
                    )
                }
                let didBindIterableSource: Bool
                if !boundIterableDestination,
                   !didBindListSource,
                   !isArrayReceiver,
                   !isMapReceiver
                {
                    didBindIterableSource = bindBundledIterableSourceFunction(
                        typeArguments: [collectionElementType, resultElementType, nonNullableDestinationType]
                    )
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
                _ = bindBundledSequenceDestinationSourceFunction(typeArguments: typeArguments)
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
