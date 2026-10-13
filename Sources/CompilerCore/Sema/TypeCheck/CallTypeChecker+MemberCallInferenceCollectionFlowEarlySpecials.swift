// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func inferIterableDropFamilySpecial(locals: inout LocalBindings) -> TypeID? {
        if isIterableDropFamily {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            guard args.count == 1 else {
                didReturnNil = true
                return nil
            }

            let listSymbol = lookupStdlibSymbol("List", symbols: sema.symbols, interner: interner)
            let resultType = if let listSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let didBindSource: Bool
            if calleeStr == "drop" {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                didBindSource = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                    || bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            } else {
                let predicateType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.booleanType
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: predicateType)
                didBindSource = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                    || bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                if didBindSource,
                   let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef
                {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            guard didBindSource else {
                didReturnNil = true
                return nil
            }
            sema.bindings.markCollectionExpr(id)

            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferIterableElementFamilySpecial(locals: inout LocalBindings) -> TypeID? {
        // KSP-970: bind the generic Iterable element family explicitly so a
        // plain Iterable receiver cannot fall through to the legacy runtime
        // fallback. List source overloads remain preferred for concrete Lists.
        if !isSequenceReceiver,
           (calleeStr == "elementAt" || calleeStr == "elementAtOrElse" || calleeStr == "elementAtOrNull"),
           (isCollectionReceiver || isIterableReceiver)
        {
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let expectedArgumentCount = calleeStr == "elementAtOrElse" ? 2 : 1
            guard args.count == expectedArgumentCount else {
                didReturnNil = true
                return nil
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
            if calleeStr == "elementAtOrElse" {
                let defaultValueType = sema.types.make(.functionType(FunctionType(
                    params: [sema.types.intType],
                    returnType: collectionElementType
                )))
                _ = driver.inferExpr(
                    args[1].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: defaultValueType
                )
            }
            let didBindSource = bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals)
                || bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
            guard didBindSource else {
                didReturnNil = true
                return nil
            }
            for argument in args
            where ast.arena.expr(argument.expr)?.isLambdaOrCallableRef == true {
                sema.bindings.unmarkCollectionHOFLambdaExpr(argument.expr)
            }
            sema.bindings.markCollectionExpr(id)
            let resultType = calleeStr == "elementAtOrNull"
                ? sema.types.makeNullable(collectionElementType)
                : collectionElementType
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferMutableListMemberSpecial(locals: inout LocalBindings) -> TypeID? {
        // KSP-1021: MutableList source extensions share names with retained
        // synthetic member fallbacks. Bind the exact source overload before the
        // generic collection/member resolver can select the fallback by name and
        // arity alone. The mutable receiver check also keeps List.asReversed()
        // read-only when the static receiver is only List<T>.
        let isMutableListPredicateName = calleeStr == "removeAll" || calleeStr == "retainAll"
        let hasMutableListPredicateArgument = args.count == 1
            && (ast.arena.expr(args[0].expr)?.isLambdaOrCallableRef ?? false)
        if isMutableListReceiver,
           (!isMutableListPredicateName || hasMutableListPredicateArgument),
           [
               "asReversed", "remove", "removeFirst", "removeFirstOrNull",
               "removeLast", "removeLastOrNull", "removeAll", "retainAll",
               "reverse", "shuffle",
           ].contains(calleeStr)
        {
            let elementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let mutableSourceArguments: [TypeID] = [elementType]
            let bound: Bool
            let resultType: TypeID

            switch calleeStr {
            case "asReversed" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                , locals: &locals)
                resultType = receiverType
            case "remove" where args.count == 1 && args[0].label == interner.intern("index"):
                _ = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: sema.types.intType
                )
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                , locals: &locals)
                resultType = elementType
            case "removeFirst" where args.isEmpty,
                 "removeLast" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                , locals: &locals)
                resultType = elementType
            case "removeFirstOrNull" where args.isEmpty,
                 "removeLastOrNull" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                , locals: &locals)
                resultType = sema.types.makeNullable(elementType)
            case "removeAll" where args.count == 1,
                 "retainAll" where args.count == 1:
                let predicateType = sema.types.make(.functionType(FunctionType(
                    params: [elementType],
                    returnType: sema.types.booleanType
                )))
                if let argExpr = ast.arena.expr(args[0].expr), argExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(
                    args[0].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: predicateType
                )
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    matchingParameterType: predicateType,
                    requireMutableListReceiver: true
                , locals: &locals)
                if bound, let argExpr = ast.arena.expr(args[0].expr), argExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
                resultType = sema.types.booleanType
            case "reverse" where args.isEmpty:
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                , locals: &locals)
                resultType = sema.types.unitType
            case "shuffle" where args.isEmpty || args.count == 1:
                if let randomArg = args.first {
                    _ = driver.inferExpr(randomArg.expr, ctx: ctx, locals: &locals)
                }
                bound = bindBundledListSourceFunction(
                    typeArguments: mutableSourceArguments,
                    requireMutableListReceiver: true
                , locals: &locals)
                resultType = sema.types.unitType
            default:
                didReturnNil = true
                return nil
            }

            guard bound else { didReturnNil = true; return nil }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferAsFlowMemberSpecial(locals: inout LocalBindings) -> TypeID? {
        if interner.resolve(calleeName) == "asFlow",
           args.isEmpty,
           !isMapReceiver,
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
            // KSP-674: resolve to the bundled `Iterable<T>.asFlow()` Kotlin
            // source (kotlinx.coroutines.flow) when present, so Lowering runs the
            // real `flow { }`-composed body instead of the removed
            // `kk_flow_as_flow` bridge. Fall back to type-only binding otherwise.
            let asFlowFQName = [
                interner.intern("kotlinx"),
                interner.intern("coroutines"),
                interner.intern("flow"),
                calleeName,
            ]
            if isCollectionReceiver || isSequenceReceiver,
               let chosenCallee = sema.symbols.lookupAll(fqName: asFlowFQName).first(where: { candidate in
                   guard let symbol = sema.symbols.symbol(candidate),
                         symbol.kind == .function,
                         sema.symbols.isSourceBackedSymbol(candidate),
                         let signature = sema.symbols.functionSignature(for: candidate),
                         signature.parameterTypes.isEmpty,
                         let declaredReceiver = signature.receiverType
                   else {
                       return false
                   }
                   // Multiple bundled `asFlow` overloads exist (Iterable,
                   // Sequence, Array, primitive arrays, function types); pick
                   // the one whose declared receiver fits this call site.
                   return extensionSyntheticFallbackReceiverMatches(
                       callSiteReceiver: receiverType,
                       declaredReceiver: declaredReceiver,
                       sema: sema
                   )
               })
            {
                sema.bindings.bindCall(id, binding: CallBinding(
                    chosenCallee: chosenCallee,
                    substitutedTypeArguments: [elementType],
                    parameterMapping: [:]
                ))
                sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
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
        return nil
    }

    func inferZipMemberSpecial(locals: inout LocalBindings) -> TypeID? {
        if interner.resolve(calleeName) == "zip",
           !isSequenceReceiver,
           isCollectionReceiver,
           !isMapReceiver,
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
                    returnType: sema.types.nullableAnyType,
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
            _ = bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments, locals: &locals)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.markCollectionExpr(id)
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferFilterIsInstanceSpecial(locals: inout LocalBindings) -> TypeID? {

        // filterIsInstance<R>() — reified type parameter, returns List<R> or Sequence<R>
        if interner.resolve(calleeName) == "filterIsInstance",
           args.isEmpty,
           !isMapReceiver,
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
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
                let didBindSource: Bool = if isSequenceReceiver {
                    bindBundledSequenceDestinationSourceFunction(
                        typeArguments: [filterType],
                        parameterMapping: [:]
                    , locals: &locals)
                } else if receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver {
                    bindBundledListSourceFunction(typeArguments: [filterType], parameterMapping: [:], locals: &locals)
                } else {
                    bindBundledIterableSourceFunction(typeArguments: [filterType], locals: &locals)
                }
                let ownerFQName = isSequenceReceiver
                    ? [interner.intern("kotlin"), interner.intern("sequences")]
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
                          sema.symbols.isSourceBackedSymbol(symbolID),
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
        return nil
    }

    func inferToCollectionSpecial(locals: inout LocalBindings) -> TypeID? {
        if interner.resolve(calleeName) == "toCollection",
           args.count == 1,
           !isMapReceiver,
           isCollectionReceiver || isSequenceReceiver
        {
            let destinationType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferFilterIsInstanceToSpecial(locals: inout LocalBindings) -> TypeID? {
        if interner.resolve(calleeName) == "filterIsInstanceTo",
           args.count == 1,
           !isMapReceiver,
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
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
            if isSequenceReceiver {
                _ = bindBundledSequenceDestinationSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                , locals: &locals)
            } else if receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver {
                bindBundledListSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                , locals: &locals)
            } else {
                _ = bindBundledIterableSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType]
                , locals: &locals)
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferFilterNotNullSpecial(locals: inout LocalBindings) -> TypeID? {

        // filterNotNull() — bundled Kotlin source implementation with sequence runtime fallback.
        if interner.resolve(calleeName) == "filterNotNull",
           args.isEmpty,
           !isMapReceiver,
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
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
            if isSequenceReceiver {
                let memberFQName = [
                    interner.intern("kotlin"),
                    interner.intern("sequences"),
                    calleeName,
                ]
                if let chosenCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.isSourceBackedSymbol(candidate),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == args.count,
                          let signatureReceiver = signature.receiverType
                    else {
                        return false
                    }
                    return receiverClassifier.isSequenceLikeType(signatureReceiver)
                }) {
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: chosenCallee,
                        substitutedTypeArguments: [resultElementType],
                        parameterMapping: [:]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
                }
            } else if receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver {
                _ = bindBundledListSourceFunction(typeArguments: [resultElementType], locals: &locals)
            } else {
                _ = bindBundledIterableSourceFunction(typeArguments: [resultElementType], locals: &locals)
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferFilterNotNullToSpecial(locals: inout LocalBindings) -> TypeID? {

        // filterNotNullTo(destination) — no lambda, returns destination type (STDLIB-SEQ-021)
        if interner.resolve(calleeName) == "filterNotNullTo",
           args.count == 1,
           !isMapReceiver,
           isCollectionReceiver || isIterableReceiver || isSequenceReceiver
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
            if !isSequenceReceiver,
               receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
            {
                bindBundledListSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                , locals: &locals)
            } else if !isSequenceReceiver {
                _ = bindBundledIterableSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType]
                , locals: &locals)
            } else {
                _ = bindBundledSequenceDestinationSourceFunction(
                    typeArguments: [destinationElementType, nonNullableDestinationType],
                    parameterMapping: [0: 0]
                , locals: &locals)
            }
            sema.bindings.markCollectionExpr(id)
            let finalType = safeCall ? sema.types.makeNullable(destinationType) : destinationType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferBinarySearchLambdaSpecial(locals: inout LocalBindings) -> TypeID? {
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
            _ = bindBundledListBinarySearchSource(elementType: collectionElementType, locals: &locals)
            let finalType = safeCall ? sema.types.makeNullable(sema.types.intType) : sema.types.intType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }

    func inferGenericOnEachSpecial(locals: inout LocalBindings) -> TypeID? {
        if isSourceBackedGenericOnEach {
            guard args.count == 1 else {
                didReturnNil = true
                return nil
            }
            let collectionElementType = resolvedCollectionElementType(
                receiverID: receiverID,
                receiverType: receiverType,
                sema: sema,
                interner: interner,
                ctx: ctx,
                locals: &locals
            )
            let typeArguments: [TypeID]
            if isMapReceiver,
               let mapClassType = resolveClassType(sema.types.makeNonNullable(receiverType), sema: sema),
               mapClassType.args.count >= 2
            {
                typeArguments = [
                    typeIDFromTypeArg(mapClassType.args[0]),
                    typeIDFromTypeArg(mapClassType.args[1]),
                    sema.types.makeNonNullable(receiverType),
                ]
            } else if !isMapReceiver {
                typeArguments = [collectionElementType, sema.types.makeNonNullable(receiverType)]
            } else {
                didReturnNil = true
                return nil
            }
            let lambdaParameterTypes = calleeStr == "onEachIndexed"
                ? [sema.types.intType, collectionElementType]
                : [collectionElementType]
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: lambdaParameterTypes,
                returnType: sema.types.unitType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            guard bindBundledGenericOnEachSourceFunction(typeArguments: typeArguments, locals: &locals) else {
                didReturnNil = true
                return nil
            }
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
            }
            let finalType = safeCall ? sema.types.makeNullable(receiverType) : receiverType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        return nil
    }
}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
