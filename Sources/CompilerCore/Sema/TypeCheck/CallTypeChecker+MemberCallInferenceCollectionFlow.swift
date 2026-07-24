// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallCollectionFlowSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        // Defer inference of lambda arguments for collection HOFs so that the
        // contextual function type (and thus implicit `it`) is available.
        let collectionHOFNames: Set = [
            "map", "filter", "filterNot", "mapNotNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
            "fold", "foldRight", "reduce", "reduceOrNull", "reduceRight", "reduceRightOrNull", "reduceRightIndexed", "reduceRightIndexedOrNull", "foldIndexed", "foldRightIndexed", "reduceIndexed", "reduceIndexedOrNull",
            "scan", "scanIndexed", "runningFold", "runningFoldIndexed", "runningReduce", "runningReduceIndexed", "scanReduce",
            "groupBy", "groupingBy", "reduceTo", "sortedBy", "count", "first", "last", "find", "findLast", "indexOf", "lastIndexOf", "contains", "containsAll", "firstOrNull", "lastOrNull",
            "associateBy", "associateWith", "associate", "associateTo", "associateByTo", "associateWithTo", "groupByTo",
            "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo", "mapIndexedTo", "flatMapIndexedTo",
            "mapIndexedNotNullTo", "filterIndexedTo", "filterNotNullTo",
            "mapKeysTo", "mapValuesTo",
            "forEachIndexed", "mapIndexed", "mapIndexedNotNull", "filterIndexed",
            "onEach", "onEachIndexed",
            "sumOf", "sumBy", "sumByDouble", "min", "maxOrNull", "minOrNull",
            "indexOfFirst", "indexOfLast", "binarySearch", "binarySearchBy",
            "maxBy", "minBy", "maxByOrNull", "minByOrNull", "maxOfOrNull", "minOfOrNull",
            "maxOf", "minOf",
            "maxWith", "maxWithOrNull", "minWith", "minWithOrNull",
            "maxOfWith", "maxOfWithOrNull", "minOfWith", "minOfWithOrNull",
            "sortedByDescending", "sortedWith", "sortedArrayWith", "partition", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "distinctBy", "zip", "zipWithNext",
            "flatten",
            "sort", "sortBy", "sortByDescending", "sortWith",
        ]
        let flowHOFNames: Set = ["map", "filter", "collect"]
        let mapOnlyCollectionHOFNames: Set = ["mapValues", "mapValuesTo", "mapKeys", "mapKeysTo", "filterKeys", "filterValues"]
        let mutableListOnlyCollectionHOFNames: Set = ["sort", "sortBy", "sortByDescending", "sortWith"]
        // Fallback for receivers that were never routed through a `flow { }`/operator
        // call (e.g. a user function declared `fun f(): Flow<Int>`), so the
        // `isFlowExpr`/`isFlowSymbol` bindings above were never marked. Recover the
        // same information directly from the receiver's inferred class type.
        let flowClassSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlinx"), interner.intern("coroutines"),
            interner.intern("flow"), interner.intern("Flow"),
        ])
        let receiverFlowClassType: ClassType? = if let flowClassSymbol,
                                                    case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType)),
                                                    classType.classSymbol == flowClassSymbol
        {
            classType
        } else {
            nil
        }
        let isFlowReceiver = if sema.bindings.isFlowExpr(receiverID) {
            true
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  sema.bindings.isFlowSymbol(receiverSymbol)
        {
            true
        } else if receiverFlowClassType != nil {
            true
        } else {
            false
        }
        let flowElementType: TypeID = if let elementType = sema.bindings.flowElementType(forExpr: receiverID) {
            elementType
        } else if case .nameRef = ast.arena.expr(receiverID),
                  let receiverSymbol = sema.bindings.identifierSymbol(for: receiverID),
                  let elementType = sema.bindings.flowElementType(forSymbol: receiverSymbol)
        {
            elementType
        } else if let firstArg = receiverFlowClassType?.args.first {
            switch firstArg {
            case let .invariant(t), let .out(t), let .in(t):
                t
            case .star:
                sema.types.anyType
            }
        } else {
            sema.types.anyType
        }
        let isFlowHOF = isFlowReceiver && flowHOFNames.contains(interner.resolve(calleeName))
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: interner)
        let receiverClassification = receiverClassifier.classify(
            receiverID: receiverID,
            receiverType: receiverType,
            ast: ast
        )
        let isCollectionReceiver = receiverClassification.isCollectionReceiver
        let isArrayReceiver = receiverClassification.isArrayReceiver
        let isMapReceiver = receiverClassification.isMapReceiver
        let isMutableListReceiver = receiverClassification.isMutableListReceiver
        let isListFactoryReceiver = receiverClassification.isListFactoryReceiver
        let isSyntheticSequenceReceiver = receiverClassification.isSyntheticSequenceReceiver
        let isSequenceReceiver = receiverClassification.isSequenceReceiver
        var activeCollectionHOFNames = collectionHOFNames
        if !isMutableListReceiver {
            activeCollectionHOFNames.subtract(mutableListOnlyCollectionHOFNames)
        }
        if !isSequenceReceiver {
            activeCollectionHOFNames.remove("flatMapIndexed")
            // List.zip resolves through bundled Kotlin source. Only Sequence
            // needs this generic fast path until KSP-308 removes its bridge.
            activeCollectionHOFNames.remove("zip")
        } else {
            activeCollectionHOFNames.remove("mapIndexedNotNull")
            activeCollectionHOFNames.remove("dropLastWhile")
        }
        if isMapReceiver {
            activeCollectionHOFNames.formUnion(mapOnlyCollectionHOFNames)
        }
        let isCollectionHOF = activeCollectionHOFNames.contains(interner.resolve(calleeName))
            && (isCollectionReceiver || isSequenceReceiver)
            && !(interner.resolve(calleeName) == "binarySearch"
                && isArrayReceiver)

        @discardableResult
        func bindBundledListSourceFunction(
            typeArguments: [TypeID],
            parameterMapping: [Int: Int] = Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
        ) -> Bool {
            guard (!isSequenceReceiver || isListFactoryReceiver),
                  receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
            else {
                return false
            }
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      symbol.declSite != nil,
                      (sema.symbols.externalLinkName(for: candidate) ?? "").isEmpty,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                return receiverClassifier.isConcreteListLikeType(signatureReceiver)
            }) else {
                return false
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: typeArguments,
                parameterMapping: parameterMapping
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            return true
        }

        @discardableResult
        func bindBundledIterableSourceFunction(typeArguments: [TypeID]) -> Bool {
            guard !isSequenceReceiver, isCollectionReceiver else {
                return false
            }
            let sourceFQName = [
                interner.intern("kotlin"),
                interner.intern("collections"),
                calleeName,
            ]
            let receiverForLookup = sema.types.makeNonNullable(receiverType)
            guard let (actualReceiverClassType, _) = resolveClassTypeSymbol(receiverForLookup, sema: sema) else {
                return false
            }
            let actualClassSymbol = actualReceiverClassType.classSymbol
            guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      symbol.declSite != nil,
                      (sema.symbols.externalLinkName(for: candidate) ?? "").isEmpty,
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == args.count,
                      let signatureReceiver = signature.receiverType
                else {
                    return false
                }
                if isCollectionLikeType(signatureReceiver, sema: sema, interner: interner),
                   let (sigClassType, _) = resolveClassTypeSymbol(signatureReceiver, sema: sema),
                   sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol) {
                    return true
                }
                guard let (sigClassType, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema) else {
                    return false
                }
                if receiverSymbol.fqName == [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Iterable"),
                ], sema.types.isNominalSubtypeSymbol(actualClassSymbol, of: sigClassType.classSymbol) {
                    return true
                }
                return false
            }) else {
                return false
            }
            sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: typeArguments,
                parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
            ))
            sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            return true
        }

        if interner.resolve(calleeName) == "asFlow",
           args.isEmpty,
           isCollectionReceiver || isSequenceReceiver
        {
            let elementType = if isCollectionReceiver {
                resolvedCollectionElementType(
                    receiverID: receiverID,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner,
                    ctx: ctx,
                    locals: &locals
                )
            } else {
                sema.types.anyType
            }
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(elementType, forExpr: id)
            let resultType = driver.helpers.makeFlowType(
                elementType: elementType,
                sema: sema,
                interner: interner
            ) ?? sema.types.anyType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "zip",
           !isSequenceReceiver,
           isCollectionReceiver,
           !args.isEmpty
        {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let otherType = sema.bindings.exprTypes[args[0].expr]
                ?? driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let otherElementType: TypeID
            if case let .classType(otherClassType) = sema.types.kind(of: sema.types.makeNonNullable(otherType)),
               let firstArg = otherClassType.args.first
            {
                otherElementType = switch firstArg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: sema.types.anyType
                }
            } else {
                otherElementType = sema.types.anyType
            }

            let resultElementType: TypeID
            let sourceTypeArguments: [TypeID]
            if args.count >= 2 {
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, otherElementType],
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultElementType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                sourceTypeArguments = [collectionElementType, otherElementType, resultElementType]
            } else if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                resultElementType = sema.types.make(.classType(ClassType(
                    classSymbol: pairSymbol,
                    args: [.invariant(collectionElementType), .invariant(otherElementType)],
                    nullability: .nonNull
                )))
                sourceTypeArguments = [collectionElementType, otherElementType]
            } else {
                resultElementType = sema.types.anyType
                sourceTypeArguments = [collectionElementType, otherElementType]
            }

            let resultType = if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(resultElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            _ = bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterIsInstance<R>() — reified type parameter, returns List<R> or Sequence<R>
        if interner.resolve(calleeName) == "filterIsInstance",
           args.isEmpty,
           isCollectionReceiver || isSequenceReceiver
        {
            let filterType = explicitTypeArgs.first ?? sema.types.anyType
            let receiverElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let resultType = if isSequenceReceiver {
                makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: filterType
                )
            } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(filterType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            if resultType != sema.types.anyType {
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.markCollectionExpr(id)
                let didBindSource = !isSequenceReceiver && bindBundledListSourceFunction(typeArguments: [filterType], parameterMapping: [:])
                let ownerFQName = isSequenceReceiver
                    ? [interner.intern("kotlin"), interner.intern("sequences"), interner.intern("Sequence")]
                    : KnownCompilerNames(interner: interner).kotlinCollectionsListFQName
                if !didBindSource,
                   let chosenCallee = sema.symbols.lookupAll(fqName: ownerFQName + [calleeName]).first(where: { symbolID in
                       guard let signature = sema.symbols.functionSignature(for: symbolID),
                             signature.parameterTypes.count == args.count
                       else {
                           return false
                       }
                       // Bundled Kotlin-source declarations (e.g. List<T>.filter) share
                       // this fqName with Map/Set/Iterable fallback candidates once their
                       // synthetic stub is suppressed. Skip a receiver-specific bundled
                       // declaration when the concrete receiver kind doesn't match it, so
                       // non-List collection fallbacks (Map.filter, etc.) aren't
                       // incorrectly bound to the List-only bundled function.
                       if let signatureReceiver = signature.receiverType,
                          (sema.symbols.externalLinkName(for: symbolID) ?? "").isEmpty,
                          receiverClassifier.isConcreteListLikeType(signatureReceiver),
                          !receiverClassifier.isConcreteListLikeType(receiverType) {
                           return false
                       }
                       return true
                   }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [receiverElementType, filterType],
                        parameterMapping: [:]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        if interner.resolve(calleeName) == "toCollection",
           args.count == 1,
           isCollectionReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "filterIsInstanceTo",
           args.count == 1,
           isCollectionReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
            let destinationElementType: TypeID = if case let .classType(destinationClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                    let firstArg = destinationClassType.args.first
            {
                switch firstArg {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let receiverElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            if isSequenceReceiver {
                let memberFQName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    interner.intern("Sequence"),
                    calleeName,
                ]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    sema.symbols.externalLinkName(for: candidate) == "kk_sequence_filterIsInstanceTo"
                }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [receiverElementType, destinationElementType],
                        parameterMapping: [0: 0]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }
            } else {
                bindBundledListSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                )
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterNotNull() — source-backed List implementation, sequence runtime fallback.
        if interner.resolve(calleeName) == "filterNotNull",
           args.isEmpty,
           isCollectionReceiver || isSequenceReceiver
        {
            let receiverElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let resultElementType = sema.types.makeNonNullable(receiverElementType)
            let resultType: TypeID = if isSequenceReceiver {
                makeSyntheticSequenceType(
                    symbols: sema.symbols,
                    types: sema.types,
                    interner: interner,
                    elementType: resultElementType
                )
            } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(resultElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            if !isSequenceReceiver {
                bindBundledListSourceFunction(typeArguments: [resultElementType])
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        // filterNotNullTo(destination) — no lambda, returns destination type (STDLIB-SEQ-021)
        if interner.resolve(calleeName) == "filterNotNullTo",
           args.count == 1,
           isCollectionReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
            let destinationElementType: TypeID = if case let .classType(destinationClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                    let firstArg = destinationClassType.args.first
            {
                switch firstArg {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            if !isSequenceReceiver {
                bindBundledListSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                )
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if interner.resolve(calleeName) == "binarySearch",
           receiverClassifier.isConcreteListLikeType(receiverType),
           args.count == 1,
           let lambdaExpr = ast.arena.expr(args[0].expr),
           lambdaExpr.isLambdaOrCallableRef
        {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.intType,
                isSuspend: false,
                nullability: .nonNull
            )))
            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        if let groupingType = tryGroupingMemberCall(
            id,
            calleeName: calleeName,
            receiverID: receiverID,
            receiverType: receiverType,
            args: args,
            safeCall: safeCall,
            expectedType: expectedType,
            ast: ast,
            sema: sema,
            ctx: ctx,
            locals: &locals
        ) {
            return groupingType
        }

        let isGroupingReceiver: Bool = {
            let knownNames = KnownCompilerNames(interner: interner)
            guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
                return false
            }
            return knownNames.isGroupingSymbol(symbol)
        }()
        let calleeStr = interner.resolve(calleeName)

        if isGroupingReceiver {
            let groupingTypeInfo: (element: TypeID, key: TypeID) = {
                if let receiverExpr = ast.arena.expr(receiverID),
                   case let .memberCall(innerReceiverID, innerCallee, _, innerArgs, _) = receiverExpr,
                   interner.resolve(innerCallee) == "groupingBy",
                   innerArgs.count == 1
                {
                    let innerReceiverType = sema.bindings.exprType(for: innerReceiverID)
                        ?? driver.inferExpr(innerReceiverID, ctx: ctx, locals: &locals)
                    let sourceElementType = resolvedCollectionElementType(
                        receiverID: innerReceiverID,
                        receiverType: innerReceiverType,
                        sema: sema,
                        interner: interner,
                        ctx: ctx,
                        locals: &locals
                    )
                    let keyType = inferredLambdaReturnType(
                        argExpr: innerArgs[0].expr, ast: ast, sema: sema
                    )
                    return (sourceElementType, keyType)
                }

                let receiverTypeToInspect = sema.bindings.exprType(for: receiverID)
                    ?? driver.inferExpr(receiverID, ctx: ctx, locals: &locals)
                let elementType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverTypeToInspect),
                                             ct.args.count >= 1
                {
                    switch ct.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let keyType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverTypeToInspect),
                                         ct.args.count >= 2
                {
                    switch ct.args[1] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                return (elementType, keyType)
            }()
            switch calleeStr {
            case "eachCount":
                let groupingKeyType = groupingTypeInfo.key
                if let mapSymbol = sema.symbols.lookupByShortName(interner.intern("Map")).first {
                    let resultType = sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [.invariant(groupingKeyType), .invariant(sema.types.intType)],
                        nullability: .nonNull
                    )))
                    sema.bindings.bindExprType(id, type: resultType)
                    return resultType
                }
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType

            case "foldTo":
                guard args.count == 3 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
                let destinationMapKeyType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                       destClassType.args.count >= 2
                {
                    switch destClassType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let destinationMapValueType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                         destClassType.args.count >= 2
                {
                    switch destClassType.args[1] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let groupingElementType = groupingTypeInfo.element
                let groupingKeyType = groupingTypeInfo.key == sema.types.anyType
                    ? destinationMapKeyType
                    : groupingTypeInfo.key
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    let initialValueSelectorType = sema.types.make(.functionType(FunctionType(
                        params: [groupingKeyType, groupingElementType],
                        returnType: destinationMapValueType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: initialValueSelectorType)
                    let initialValueType = destinationMapValueType == sema.types.anyType
                        ? inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                        : destinationMapValueType
                    let operationExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [groupingKeyType, initialValueType, groupingElementType],
                        returnType: initialValueType
                    )))
                    if let operationLambdaExpr = ast.arena.expr(args[2].expr), operationLambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[2].expr)
                    }
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                } else {
                    let initialValueType: TypeID = if destinationMapValueType == sema.types.anyType {
                        driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals)
                    } else {
                        driver.inferExpr(
                            args[1].expr, ctx: ctx, locals: &locals, expectedType: destinationMapValueType
                        )
                    }
                    let operationExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [initialValueType, groupingElementType],
                        returnType: initialValueType
                    )))
                    if let operationLambdaExpr = ast.arena.expr(args[2].expr), operationLambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[2].expr)
                    }
                    _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                }
                sema.bindings.bindExprType(id, type: destinationType)
                return destinationType

            default:
                break
            }
        }

        // --- Collection higher-order functions (STDLIB-005) ---
        if isCollectionHOF {
            let calleeStr = interner.resolve(calleeName)
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let collectionMapTypes: (key: TypeID, value: TypeID) = {
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

            func bindBundledSequenceAggregateSource(typeArguments: [TypeID]) {
                guard isSequenceReceiver else {
                    return
                }
                let sourceFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    calleeName,
                ]
                guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          symbol.declSite != nil,
                          (sema.symbols.externalLinkName(for: candidate) ?? "").isEmpty,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == args.count,
                          let signatureReceiver = signature.receiverType
                    else {
                        return false
                    }
                    return receiverClassifier.isSequenceLikeType(signatureReceiver)
                }) else {
                    return
                }
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: typeArguments,
                    parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
            }

            var sourceBackedSequenceAggregateTypeArguments: [TypeID]?
            let resultType: TypeID
            let destinationCollectionHOFs: Set = [
                "filterTo", "filterNotTo", "mapTo", "flatMapTo", "mapNotNullTo",
                "mapIndexedTo", "mapIndexedNotNullTo", "flatMapIndexedTo", "associateTo",
                "filterIndexedTo", "mapKeysTo", "mapValuesTo",
            ]
            if destinationCollectionHOFs.contains(calleeStr), args.count == 2 {
                let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let nonNullableDestinationType = sema.types.makeNonNullable(destinationType)
                let destinationElementType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                        destClassType.args.count >= 1
                {
                    switch destClassType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let destinationMapKeyType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                       destClassType.args.count >= 2
                {
                    switch destClassType.args[0] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let destinationMapValueType: TypeID = if case let .classType(destClassType) = sema.types.kind(of: nonNullableDestinationType),
                                                         destClassType.args.count >= 2
                {
                    switch destClassType.args[1] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let pairReturnType: TypeID = if calleeStr == "associateTo" {
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
                        returnType: destinationElementType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case "flatMapTo":
                    {
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
                        } else {
                            return sema.types.make(.functionType(FunctionType(
                                params: [collectionElementType],
                                returnType: sema.types.anyType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        }
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
                        returnType: destinationElementType,
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
                        } else {
                            return sema.types.make(.functionType(FunctionType(
                                params: [sema.types.intType, collectionElementType],
                                returnType: sema.types.anyType,
                                isSuspend: false,
                                nullability: .nonNull
                            )))
                        }
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
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = destinationType
                if ["filterTo", "filterNotTo", "filterIndexedTo"].contains(calleeStr),
                   !isSequenceReceiver
                {
                    bindBundledListSourceFunction(
                        typeArguments: [collectionElementType, nonNullableDestinationType]
                    )
                }
                if ["mapTo", "mapNotNullTo", "flatMapTo", "mapIndexedTo", "mapIndexedNotNullTo", "flatMapIndexedTo"].contains(calleeStr),
                   !isSequenceReceiver
                {
                    let rawLambdaReturnType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                    let resultElementType: TypeID
                    if calleeStr == "mapTo" || calleeStr == "mapIndexedTo" {
                        resultElementType = rawLambdaReturnType
                    } else if calleeStr == "mapNotNullTo" || calleeStr == "mapIndexedNotNullTo" {
                        resultElementType = sema.types.makeNonNullable(rawLambdaReturnType)
                    } else {
                        resultElementType = extractListElementType(rawLambdaReturnType, sema: sema, interner: interner)
                    }
                    if bindBundledListSourceFunction(typeArguments: [collectionElementType, resultElementType, nonNullableDestinationType]) {
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                        }
                    }
                }
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            if calleeStr == "zip", !args.isEmpty {
                let otherType = sema.bindings.exprTypes[args[0].expr]
                    ?? driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let otherElementType: TypeID
                if let otherClassType = resolveClassType(otherType, sema: sema),
                   let firstArg = otherClassType.args.first
                {
                    otherElementType = switch firstArg {
                    case let .invariant(t), let .out(t), let .in(t): t
                    case .star: sema.types.anyType
                    }
                } else {
                    otherElementType = sema.types.anyType
                }

                let resultElementType: TypeID
                if args.count >= 2 {
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, otherElementType],
                        returnType: sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    }
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultElementType = inferredLambdaReturnType(argExpr: args[1].expr, ast: ast, sema: sema)
                } else if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first {
                    resultElementType = sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.invariant(collectionElementType), .invariant(otherElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultElementType = sema.types.anyType
                }

                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: resultElementType
                    )
                } else if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner) {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(resultElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
            switch calleeStr {
            case "indexOf", "lastIndexOf":
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    return nil
                }
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                resultType = sema.types.intType
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])

            case "contains":
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    return nil
                }
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.booleanType)
                    return sema.types.booleanType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                resultType = sema.types.booleanType
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])

            case "containsAll":
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    return nil
                }
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.booleanType)
                    return sema.types.booleanType
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.anyType)
                resultType = sema.types.booleanType
                _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])

            case "findLast", "firstOrNull", "lastOrNull":
                guard receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver else {
                    return nil
                }
                if args.isEmpty {
                    resultType = sema.types.makeNullable(collectionElementType)
                    _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
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
                    if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                        }
                    }
                } else {
                    sema.bindings.bindExprType(id, type: sema.types.makeNullable(collectionElementType))
                    return sema.types.makeNullable(collectionElementType)
                }

            case "map", "filter", "filterNot", "filterKeys", "filterValues", "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull", "forEach", "flatMap", "flatMapIndexed", "any", "none", "all",
                 "count", "first", "last", "find", "associateBy", "associateWith", "associate",
                 "mapValues", "mapKeys", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "onEach":
                // any(), none(), count(), first(), last() can be called with no args
                if args.isEmpty {
                    switch calleeStr {
                    case "any", "none": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last":
                        resultType = collectionElementType
                    case "find": resultType = sema.types.makeNullable(collectionElementType)
                    default: resultType = sema.types.anyType
                    }
                    if ["any", "none", "first", "last"].contains(calleeStr) {
                        _ = bindBundledListSourceFunction(typeArguments: [collectionElementType])
                    }
                } else {
                    let lambdaReturnType: TypeID = switch calleeStr {
                    case "filter", "filterNot", "filterKeys", "filterValues", "any", "none", "all", "takeWhile", "takeLastWhile", "dropWhile", "dropLastWhile", "find", "first", "last": sema.types.booleanType
                    case "forEach", "onEach": sema.types.unitType
                    case "count": sema.types.booleanType
                    case "mapNotNull", "firstNotNullOf", "firstNotNullOfOrNull": sema.types.nullableAnyType
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
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType, resultElementType]) {
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
                    case "forEach": resultType = sema.types.unitType
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
                    case "flatMap":
                        let lambdaBodyType = inferredLambdaReturnType(
                            argExpr: args[0].expr, ast: ast, sema: sema
                        )
                        let innerElementType = extractListElementType(
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
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType, innerElementType]) {
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
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType, innerElementType]) {
                            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    case "any", "none", "all": resultType = sema.types.booleanType
                    case "count": resultType = sema.types.intType
                    case "first", "last": resultType = collectionElementType
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
                                    returnType: sema.types.anyType
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

                    if ["any", "none", "all", "count", "find", "first", "last"].contains(calleeStr) {
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                            if args.count == 1, let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                            }
                        }
                    }
                }

            case "fold":
                if let groupingKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) {
                    guard args.count == 2 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let expectedGroupingValueType: TypeID = if let expectedType,
                                                               let (expectedClassType, expectedSymbol) = resolveClassTypeSymbol(expectedType, sema: sema),
                                                               knownNames.isMapLikeSymbol(expectedSymbol),
                                                               expectedClassType.args.count >= 2
                    {
                        switch expectedClassType.args[1] {
                        case let .invariant(id), let .out(id), let .in(id): id
                        case .star: sema.types.anyType
                        }
                    } else {
                        sema.types.anyType
                    }
                    let firstArgLabel = args[0].label.map { interner.resolve($0) }
                    let useInitialValueSelectorOverload = if let firstArgLabel {
                        firstArgLabel == "initialValueSelector"
                    } else if case .lambdaLiteral = ast.arena.expr(args[0].expr) {
                        true
                    } else {
                        ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false
                    }
                    if useInitialValueSelectorOverload {
                        let initialValueSelectorExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [groupingKeyType, collectionElementType],
                            returnType: expectedGroupingValueType
                        )))
                        let initialValueSelectorType = driver.inferExpr(
                            args[0].expr,
                            ctx: ctx,
                            locals: &locals,
                            expectedType: initialValueSelectorExpectedType
                        )
                        if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                        }
                        let groupingResultValueType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: initialValueSelectorType) {
                            fnType.returnType
                        } else if expectedGroupingValueType != sema.types.anyType {
                            expectedGroupingValueType
                        } else {
                            sema.types.anyType
                        }
                        let operationExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [groupingKeyType, groupingResultValueType, collectionElementType],
                            returnType: groupingResultValueType
                        )))
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                        }
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: operationExpectedType)
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(groupingKeyType), .invariant(groupingResultValueType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    } else {
                        let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedGroupingValueType)
                        let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                            params: [groupingKeyType, initialType, collectionElementType],
                            returnType: initialType
                        )))
                        if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                            sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                        }
                        _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                        if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                            resultType = sema.types.make(.classType(ClassType(
                                classSymbol: mapSymbol,
                                args: [.invariant(groupingKeyType), .invariant(initialType)],
                                nullability: .nonNull
                            )))
                        } else {
                            resultType = sema.types.anyType
                        }
                    }
                } else {
                    guard args.count == 2 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [initialType, collectionElementType],
                        returnType: initialType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    }
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultType = initialType
                }

            case "foldIndexed":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, initialType, collectionElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = initialType

            case "foldRight":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, initialType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = initialType

            case "foldRightIndexed":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, initialType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = initialType

            case "reduceRight":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = collectionElementType
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "reduceRightIndexed":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = collectionElementType
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "reduceRightIndexedOrNull":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.makeNullable(collectionElementType)
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "reduceRightOrNull":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.makeNullable(collectionElementType)
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "reduce":
                if let groupingKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) {
                    guard args.count == 1 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: collectionElementType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                        resultType = sema.types.make(.classType(ClassType(
                            classSymbol: mapSymbol,
                            args: [.invariant(groupingKeyType), .invariant(collectionElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        resultType = sema.types.anyType
                    }
                } else {
                    guard args.count == 1 else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0024",
                            "No viable overload found for call.",
                            range: ast.arena.exprRange(id)
                        )
                        return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: collectionElementType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    resultType = collectionElementType
                }

            case "reduceOrNull":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "reduceOrNull() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let reduceOrNullLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: reduceOrNullLambdaType)
                resultType = sema.types.makeNullable(collectionElementType)

            case "reduceIndexed":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let reduceIndexedLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: reduceIndexedLambdaType)
                resultType = collectionElementType

            case "reduceIndexedOrNull":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "No viable overload found for call.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let reduceIndexedOrNullLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: reduceIndexedOrNullLambdaType)
                resultType = sema.types.makeNullable(collectionElementType)

            case "scan", "runningFold":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "\(calleeStr)() expects 2 arguments (initial value and a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [initialType, collectionElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: initialType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(initialType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "runningFoldIndexed", "scanIndexed":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "\(calleeStr)() expects 2 arguments (initial value and a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, initialType, collectionElementType],
                    returnType: initialType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: initialType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(initialType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "runningReduce":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "runningReduce() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "runningReduceIndexed":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "runningReduceIndexed() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType, collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }

            case "groupBy":
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let keyType = inferredLambdaReturnType(
                    argExpr: args[0].expr, ast: ast, sema: sema
                )
                // Two-lambda variant: groupBy(keySelector, valueTransform)
                var valueElementType = collectionElementType
                if args.count >= 2 {
                    let valueLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType],
                        returnType: sema.types.anyType
                    )))
                    if let lambdaExpr = ast.arena.expr(args[1].expr), case .lambdaLiteral = lambdaExpr {
                        sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    }
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: valueLambdaExpectedType)
                    valueElementType = inferredLambdaReturnType(
                        argExpr: args[1].expr, ast: ast, sema: sema
                    )
                }
                if let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner),
                   let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner)
                {
                    let listType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(valueElementType)],
                        nullability: .nonNull
                    )))
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [.invariant(keyType), .invariant(listType)],
                        nullability: .nonNull
                    )))
                    if isSequenceReceiver {
                        sourceBackedSequenceAggregateTypeArguments = args.count >= 2
                            ? [collectionElementType, keyType, valueElementType]
                            : [collectionElementType, keyType]
                    }
                } else {
                    resultType = sema.types.anyType
                }

            case "associateByTo", "associateWithTo", "groupByTo":
                // *To(destination, keySelector/valueSelector): returns the destination map
                guard args.count == 2 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                // Infer the destination map argument first
                let destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                // Extract K/V from destination MutableMap<K, V> for stronger lambda return type inference
                let lambdaReturnType: TypeID
                if let destClassType = resolveClassType(destType, sema: sema),
                   destClassType.args.count >= 2
                {
                    // For associateWithTo: lambda returns V (value type, args[1])
                    // For associateByTo/groupByTo: lambda returns K (key type, args[0])
                    let targetArgIndex = (calleeStr == "associateWithTo") ? 1 : 0
                    lambdaReturnType = switch destClassType.args[targetArgIndex] {
                    case let .invariant(id), let .out(id), let .in(id): id
                    case .star: sema.types.anyType
                    }
                } else {
                    lambdaReturnType = sema.types.anyType
                }
                let lambdaExpectedType2 = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: lambdaReturnType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType2)
                // Return type is the destination map type
                resultType = destType

            case "groupingBy":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                // Infer key type K from lambda return type
                let keyType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType
                } else if case let .functionType(fnType) = sema.types.kind(of: sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType) {
                    fnType.returnType
                } else {
                    sema.types.anyType
                }
                // Return Grouping<T, K> type
                if let groupingSymbol = sema.symbols.lookupByShortName(interner.intern("Grouping")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: groupingSymbol,
                        args: [.invariant(collectionElementType), .invariant(keyType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                sema.bindings.markCollectionExpr(id)

            case "eachCount":
                // Called on Grouping, returns Map<K, Int>
                // Extract key type K from receiver's Grouping<T, K> type args
                let eachCountKeyType = resolvedGroupingKeyType(of: receiverType, sema: sema, interner: interner) ?? sema.types.anyType
                if let mapSymbol = lookupStdlibSymbol("Map", symbols: sema.symbols, interner: interner) {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: mapSymbol,
                        args: [.invariant(eachCountKeyType), .invariant(sema.types.intType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

            case "reduceTo":
                guard args.count == 2 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "reduceTo() expects 2 arguments (destination and lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
                let reduceToKeyType: TypeID = if let ct = resolveClassType(receiverType, sema: sema),
                                                 ct.args.count >= 2,
                                                 case let .invariant(k) = ct.args[1]
                {
                    k
                } else {
                    sema.types.anyType
                }
                let reduceToAccumulatorType: TypeID = if let destCt = resolveClassType(destType, sema: sema),
                                                         destCt.args.count >= 2
                {
                    switch destCt.args[1] {
                    case let .invariant(id), let .out(id), let .in(id):
                        id
                    case .star:
                        collectionElementType
                    }
                } else {
                    collectionElementType
                }
                let reduceToLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [reduceToKeyType, reduceToAccumulatorType, collectionElementType],
                    returnType: reduceToAccumulatorType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: reduceToLambdaType)
                resultType = destType

            case "eachCountTo":
                // Called on Grouping, returns the destination MutableMap<in K, Int>
                // and updates its counts in place.
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let eachCountToKeyType: TypeID = if case let .classType(ct) = sema.types.kind(of: receiverType),
                                                    ct.args.count >= 2,
                                                    case let .invariant(k) = ct.args[1]
                {
                    k
                } else {
                    sema.types.anyType
                }
                let destinationExpectedType: TypeID? = if let mutableMapSymbol = lookupStdlibSymbol("MutableMap", symbols: sema.symbols, interner: interner) {
                    sema.types.make(.classType(ClassType(
                        classSymbol: mutableMapSymbol,
                        args: [.in(eachCountToKeyType), .invariant(sema.types.intType)],
                        nullability: .nonNull
                    )))
                } else {
                    nil
                }
                let destinationType = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: destinationExpectedType
                )
                resultType = destinationType

            case "sortedBy", "sortedByDescending":
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = receiverType

            case "sort":
                resultType = sema.types.unitType

            case "sortBy", "sortByDescending":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.unitType)
                    return sema.types.unitType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.unitType

            case "sortedWith", "sortedArrayWith", "sortWith":
                let isInPlaceMutation = calleeStr == "sortWith"
                guard args.count == 1 else {
                    let failedType = isInPlaceMutation ? sema.types.unitType : sema.types.anyType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    // Lambda argument: infer as (T, T) -> Int comparator function
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: sema.types.intType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                } else {
                    // Non-lambda argument (e.g. compareBy { ... }, reverseOrder(), etc.)
                    // Pass Comparator<T> expected type so factory functions can infer element type.
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
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                }
                resultType = isInPlaceMutation ? sema.types.unitType : receiverType

            case "maxWith", "minWith", "maxWithOrNull", "minWithOrNull":
                guard args.count == 1 else {
                    let failedType = (calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull")
                        ? sema.types.makeNullable(sema.types.errorType)
                        : sema.types.errorType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    let comparatorLambdaType = sema.types.make(.functionType(FunctionType(
                        params: [collectionElementType, collectionElementType],
                        returnType: sema.types.intType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorLambdaType)
                } else {
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
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                }
                resultType = (calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull")
                    ? sema.types.makeNullable(collectionElementType)
                    : collectionElementType

            case "maxOfWith", "minOfWith", "maxOfWithOrNull", "minOfWithOrNull":
                guard args.count == 2 else {
                    let failedType = (calleeStr == "maxOfWithOrNull" || calleeStr == "minOfWithOrNull")
                        ? sema.types.makeNullable(sema.types.errorType)
                        : sema.types.errorType
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
                let selectorExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.anyType
                )))
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                }
                _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: selectorExpectedType)
                let selectorResultType: TypeID = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[1].expr) {
                    sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                } else if let lambdaExprType = sema.bindings.exprType(for: args[1].expr),
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
                {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    let comparatorLambdaType = sema.types.make(.functionType(FunctionType(
                        params: [selectorResultType, selectorResultType],
                        returnType: sema.types.intType
                    )))
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorLambdaType)
                } else {
                    let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
                    let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: comparatorSymbol,
                            args: [.invariant(selectorResultType)],
                            nullability: .nonNull
                        )))
                    } else {
                        nil
                    }
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                }
                resultType = (calleeStr == "maxOfWithOrNull" || calleeStr == "minOfWithOrNull")
                    ? sema.types.makeNullable(selectorResultType)
                    : selectorResultType

            case "partition":
                guard args.count == 1 else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.booleanType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                // Pair<List<T>, List<T>>
                if let pairSymbol = sema.symbols.lookupByShortName(interner.intern("Pair")).first,
                   let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                {
                    let listType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: pairSymbol,
                        args: [.invariant(listType), .invariant(listType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }

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
                _ = bindBundledListSourceFunction(typeArguments: [flattenedElementType])

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
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
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
                    sema.types.anyType
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
                    let bodyType = inferredLambdaReturnType(
                        argExpr: args[0].expr, ast: ast, sema: sema
                    )
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
                        if bindBundledListSourceFunction(typeArguments: [collectionElementType, bodyType]) {
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
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.intType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                resultType = sema.types.intType
                if calleeStr == "sumOf", isSequenceReceiver {
                    sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
                }
                if calleeStr == "sumBy" {
                    let memberFQName = [
                        interner.intern("kotlin"),
                        interner.intern("collections"),
                        interner.intern("Iterable"),
                        calleeName,
                    ]
                    if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                        sema.symbols.functionSignature(for: candidate)?.parameterTypes.count == args.count
                    }) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: chosenCallee,
                            substitutedTypeArguments: [collectionElementType],
                            parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                        ))
                        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                    }
                }

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
                let memberFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("Iterable"),
                    calleeName,
                ]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    sema.symbols.functionSignature(for: candidate)?.parameterTypes.count == args.count
                }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [collectionElementType],
                        parameterMapping: Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }

            case "min", "maxOrNull", "minOrNull":
                guard args.isEmpty else {
                    sema.bindings.bindExprType(id, type: sema.types.anyType)
                    return sema.types.anyType
                }
                if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                    let comparableElementType = sema.types.make(.classType(ClassType(
                        classSymbol: comparableSymbol,
                        args: [.in(collectionElementType)],
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
                resultType = calleeStr == "min"
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
                            args: [.in(selectorType)],
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
                resultType = if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[0].expr) {
                    sema.types.makeNonNullable(sema.bindings.exprType(for: bodyExpr) ?? sema.types.anyType)
                } else if let lambdaExprType = sema.bindings.exprType(for: args[0].expr),
                          case let .functionType(fnType) = sema.types.kind(of: lambdaExprType)
                {
                    sema.types.makeNonNullable(fnType.returnType)
                } else {
                    sema.types.anyType
                }

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
                                args: [.in(selectorType)],
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
                    }
                    resultType = sema.types.intType
                } else if (2 ... 4).contains(args.count) {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: collectionElementType)
                    if let comparatorLambdaExpr = ast.arena.expr(args[1].expr),
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
                    resultType = sema.types.intType
                } else {
                    sema.bindings.bindExprType(id, type: sema.types.intType)
                    return sema.types.intType
                }

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
                        sema.types.makeNullable(keyType)
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

                let knownNames = KnownCompilerNames(interner: interner)
                let memberFQName = knownNames.kotlinCollectionsListFQName + [calleeName]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
                    return signature.parameterTypes.count == args.count
                }) {
                    let keySubstitution: TypeID = if keyType == sema.types.errorType {
                        sema.types.nullableAnyType
                    } else {
                        switch sema.types.kind(of: keyType) {
                        case .nothing:
                            sema.types.nullableAnyType
                        default:
                            keyType
                        }
                    }
                    let substitutedTypeArguments = [collectionElementType, keySubstitution]
                    let parameterMapping = Dictionary(uniqueKeysWithValues: args.indices.map { ($0, $0) })
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: substitutedTypeArguments,
                        parameterMapping: parameterMapping
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
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
                resultType = receiverType

            case "scanReduce":
                guard args.count == 1 else {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0024",
                        "scanReduce() expects 1 argument (a lambda), but \(args.count) were supplied.",
                        range: ast.arena.exprRange(id)
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                let scanReduceLambdaType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType, collectionElementType],
                    returnType: collectionElementType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: scanReduceLambdaType)
                if isSequenceReceiver {
                    resultType = makeSyntheticSequenceType(
                        symbols: sema.symbols,
                        types: sema.types,
                        interner: interner,
                        elementType: collectionElementType
                    )
                } else if let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first {
                    resultType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(collectionElementType)],
                        nullability: .nonNull
                    )))
                } else {
                    resultType = sema.types.anyType
                }
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
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
                if bindBundledListSourceFunction(typeArguments: [collectionElementType, resultElementType, destinationType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }

            default:
                resultType = sema.types.anyType
            }

            let sourceBackedListFilterNames: Set = ["filter", "filterNot", "filterIndexed"]
            let didBindListFilterSource = sourceBackedListFilterNames.contains(calleeStr) && args.count == 1
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

            if !didBindListFilterSource, calleeStr == "filterIndexed", isCollectionReceiver {
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
                if bindBundledListSourceFunction(typeArguments: [collectionElementType, initialType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledIterableSourceFunction(typeArguments: [collectionElementType, initialType]) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                }
            } else if (calleeStr == "reduce" || calleeStr == "reduceOrNull" || calleeStr == "reduceIndexed" || calleeStr == "reduceIndexedOrNull"), args.count == 1 {
                if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                } else if !isSequenceReceiver, isCollectionReceiver,
                          bindBundledIterableSourceFunction(typeArguments: [collectionElementType]) {
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
            }
            if let sourceBackedSequenceAggregateTypeArguments {
                bindBundledSequenceAggregateSource(typeArguments: sourceBackedSequenceAggregateTypeArguments)
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

        if isFlowHOF,
           let lambdaArg = args.first?.expr,
           let lambdaExpr = ast.arena.expr(lambdaArg),
           lambdaExpr.isLambdaOrCallableRef
        {
            sema.bindings.markCollectionHOFLambdaExpr(lambdaArg)
        }

        // KSP-499 Stage 3: a real bundled/user Kotlin declaration for this
        // exact (Flow owner, member name, arity) takes priority over the
        // hard-coded Flow intrinsic dispatch below — mirrors the declaration
        // priority rule already established for synthetic stub registration
        // (BundledDeclarationIndex / KSP-001-003). Without this, migrating a
        // Flow operator to real Kotlin source would compile but never run:
        // this special-case would keep intercepting the call by name.
        let flowOwnerFQNameForPriorityCheck: [InternedString]? = {
            guard case let .classType(classType) = sema.types.kind(of: receiverType),
                  let ownerSymbol = sema.symbols.symbol(classType.classSymbol)
            else {
                return nil
            }
            return ownerSymbol.fqName
        }()
        let hasBundledFlowDeclaration = flowOwnerFQNameForPriorityCheck.map {
            sema.bundledIndex.contains(
                ownerFQName: $0,
                name: calleeName,
                arity: args.count
            )
        } ?? false
        if isFlowReceiver,
           !hasBundledFlowDeclaration,
           let builtinFlowType = tryBuiltinFlowMemberCall(
               id,
               calleeName: calleeName,
               receiverElementType: flowElementType,
               args: args,
               safeCall: safeCall,
               ast: ast,
               sema: sema,
               ctx: ctx,
               locals: &locals
           )
        {
            return builtinFlowType
        }
        return nil
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
