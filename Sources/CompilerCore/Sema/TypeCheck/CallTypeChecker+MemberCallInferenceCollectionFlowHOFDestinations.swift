// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func nestedDestinationCallLeavesTypeParametersUnfixed(_ expr: ExprID) -> Bool {
        checker.partiallyInferredNestedCallType(expr, ctx: ctx)
            .map { !$0.unboundTypeVarBySymbol.isEmpty } ?? false
    }

    func inferDestinationCollectionHOFSpecial(locals: inout LocalBindings) -> TypeID? {
        if knownNames.destinationCollectionHOFs.contains(calleeName), args.count == 2 {
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
            if destinationType == sema.types.errorType,
               let partial = checker.partiallyInferredNestedCallType(args[0].expr, ctx: ctx),
               !partial.unboundTypeVarBySymbol.isEmpty {
                destinationType = partial.type
            }
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
                        code: "KSWIFTK-SEMA-0473",
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
                    if !isSequenceReceiver,
                       isIterableReceiver || receiverClassification.isListReceiver,
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
                    if !isSequenceReceiver,
                       let collectionSymbol = lookupStdlibSymbol("Collection", symbols: sema.symbols, interner: interner) {
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
                    if !isSequenceReceiver,
                       isIterableReceiver || receiverClassification.isListReceiver,
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
                    if !isSequenceReceiver,
                       let collectionSymbol = lookupStdlibSymbol("Collection", symbols: sema.symbols, interner: interner) {
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
                let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                let deferredDestinationElementType: TypeID = switch calleeStr {
                case "filterTo", "filterNotTo", "filterIndexedTo":
                    collectionElementType
                case "mapTo", "mapIndexedTo":
                    rawLambdaReturnType
                case "mapNotNullTo", "mapIndexedNotNullTo":
                    sema.types.makeNonNullable(rawLambdaReturnType)
                case "flatMapTo", "flatMapIndexedTo":
                    flatMapTransformElementType(
                        lambdaArgExpr: args[1].expr,
                        returnType: rawLambdaReturnType
                    )
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
                case "filterTo" where isMapReceiver, "filterNotTo" where isMapReceiver:
                    mutableMapExpectedType(key: collectionMapTypes.key, value: collectionMapTypes.value)
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
                    let firstPassDestinationDiagnostics: [Diagnostic] = ast.arena
                        .exprRange(args[0].expr)
                        .map { ctx.sema.diagnostics.removeErrorDiagnostics(containedIn: $0) }
                        ?? []
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
                        ctx.sema.diagnostics.rollback(to: reinferDiagnosticsCheckpoint)
                        for diagnostic in firstPassDestinationDiagnostics {
                            ctx.sema.diagnostics.emit(diagnostic)
                        }
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    }
                } else {
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                }
            }
            if isSequenceReceiver,
               calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo",
               case let .functionType(lambdaFunctionType) = sema.types.kind(of: effectiveLambdaExpectedType)
            {
                let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                let flattenedElementType = flatMapTransformElementType(lambdaArgExpr: args[1].expr, returnType: rawLambdaReturnType)
                let expectedElementType = flattenedElementType == sema.types.anyType ? destinationElementType : flattenedElementType
                let returnsSequence = receiverClassifier.isSequenceSubtypeType(rawLambdaReturnType)
                let expectedReturnContainer: SymbolID? = if returnsSequence {
                    lookupStdlibSymbol("Sequence", symbols: sema.symbols, interner: interner)
                } else if receiverClassifier.isIterableSubtypeType(rawLambdaReturnType) {
                    lookupStdlibSymbol("Iterable", symbols: sema.symbols, interner: interner)
                } else {
                    nil
                }
                if let expectedReturnContainer,
                   expectedElementType != sema.types.anyType,
                   expectedElementType != sema.types.errorType
                {
                    let expectedReturnType = sema.types.make(.classType(ClassType(
                        classSymbol: expectedReturnContainer,
                        args: [.invariant(expectedElementType)],
                        nullability: .nonNull
                    )))
                    let expectedLambdaType = sema.types.make(.functionType(FunctionType(
                        params: lambdaFunctionType.params,
                        returnType: expectedReturnType,
                        isSuspend: lambdaFunctionType.isSuspend,
                        nullability: .nonNull
                    )))
                    let lambdaRange = ast.arena.exprRange(args[1].expr)
                    let firstPassLambdaDiagnostics = lambdaRange.map {
                        sema.diagnostics.removeErrorDiagnostics(containedIn: $0)
                    } ?? []
                    let diagnosticsCheckpoint = sema.diagnostics.checkpoint()
                    var trialLocals = locals
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &trialLocals, expectedType: expectedLambdaType)
                    let emittedError = sema.diagnostics.diagnostics.dropFirst(diagnosticsCheckpoint).contains {
                        $0.severity == .error
                    }
                    if emittedError {
                        sema.diagnostics.rollback(to: diagnosticsCheckpoint)
                        for diagnostic in firstPassLambdaDiagnostics {
                            sema.diagnostics.emit(diagnostic)
                        }
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: effectiveLambdaExpectedType)
                    } else {
                        locals = trialLocals
                    }
                }
            }
            let boundLambdaReturnType: TypeID? = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[1].expr) {
                sema.bindings.exprType(for: bodyExpr)
            } else if let argType = sema.bindings.exprType(for: args[1].expr),
                      case let .functionType(argFunctionType) = sema.types.kind(of: argType)
            {
                argFunctionType.returnType
            } else {
                nil
            }
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
                    let extracted = flatMapTransformElementType(lambdaArgExpr: args[1].expr, returnType: lambdaReturn)
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
                } else if calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo" {
                    resultElementType = flatMapTransformElementType(
                        lambdaArgExpr: args[1].expr,
                        returnType: rawLambdaReturnType
                    )
                } else {
                    resultElementType = extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                }
                let boundIterableDestination = (calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo")
                    && bindBundledIterableFlatMapSourceFunction(
                        collectionElementType: collectionElementType,
                        resultElementType: resultElementType,
                        returnsSequence: receiverClassifier.isSequenceLikeType(rawLambdaReturnType),
                        destinationType: nonNullableDestinationType,
                        allowConcreteListReceiver: transformReturnsNonListFlattenable(
                            rawLambdaReturnType,
                            lambdaArgExpr: args[1].expr
                        )
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
                var sequenceTransformReturnsSequence: Bool? = nil
                if ["filterTo", "filterNotTo", "filterIndexedTo"].contains(calleeStr) {
                    typeArguments = [collectionElementType, nonNullableDestinationType]
                } else {
                    let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                    let resultElementType: TypeID
                    if calleeStr == "mapTo" || calleeStr == "mapIndexedTo" {
                        resultElementType = rawLambdaReturnType
                    } else if calleeStr == "mapNotNullTo" || calleeStr == "mapIndexedNotNullTo" {
                        resultElementType = sema.types.makeNonNullable(rawLambdaReturnType)
                    } else if calleeStr == "flatMapTo" || calleeStr == "flatMapIndexedTo" {
                        let returnsSequence = receiverClassifier.isSequenceSubtypeType(rawLambdaReturnType)
                        let returnsIterable = !returnsSequence && receiverClassifier.isIterableSubtypeType(rawLambdaReturnType)
                        guard returnsSequence || returnsIterable else {
                            didReturnNil = true
                            return nil
                        }
                        sequenceTransformReturnsSequence = returnsSequence
                        resultElementType = flatMapTransformElementType(lambdaArgExpr: args[1].expr, returnType: rawLambdaReturnType)
                    } else {
                        resultElementType = extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                    }
                    typeArguments = [collectionElementType, resultElementType, nonNullableDestinationType]
                }
                _ = bindBundledSequenceDestinationSourceFunction(
                    typeArguments: typeArguments,
                    returnsSequence: sequenceTransformReturnsSequence
                )
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
