// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func inferCollectionHOFAggregateAndSortCases(locals: inout LocalBindings) -> TypeID? {
        switch calleeStr {
        case "fold":
            guard args.count == 2 else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let accumulatorType = inferFoldAccumulatorType(initialType: initialType, locals: &locals)
            foldAccumulatorType = accumulatorType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [accumulatorType, collectionElementType],
                returnType: accumulatorType
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            resultType = accumulatorType
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, accumulatorType]
            }

        case "foldIndexed":
            guard args.count == 2 else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let accumulatorType = inferFoldAccumulatorType(initialType: initialType, locals: &locals)
            foldAccumulatorType = accumulatorType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, accumulatorType, collectionElementType],
                returnType: accumulatorType
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            resultType = accumulatorType
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, accumulatorType]
            }

        case "foldRight":
            guard args.count == 2 else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let accumulatorType = inferFoldAccumulatorType(initialType: initialType, locals: &locals)
            foldAccumulatorType = accumulatorType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType, accumulatorType],
                returnType: accumulatorType
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            resultType = accumulatorType

        case "foldRightIndexed":
            guard args.count == 2 else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "No viable overload found for call.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let initialType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals)
            let accumulatorType = inferFoldAccumulatorType(initialType: initialType, locals: &locals)
            foldAccumulatorType = accumulatorType
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, collectionElementType, accumulatorType],
                returnType: accumulatorType
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            resultType = accumulatorType

        case "reduceRight":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduceRightIndexed":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduceRightIndexedOrNull":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduceRightOrNull":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduce":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduceOrNull":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduceIndexed":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduceIndexedOrNull":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "scan", "runningFold":
            guard args.count == 2 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
            }

        case "runningFoldIndexed", "scanIndexed":
            guard args.count == 2 else {
                ctx.sema.diagnostics.error(
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
            }

        case "runningReduce":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "runningReduce() expects 1 argument (a lambda), but \(args.count) were supplied.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let isIterableRunningReduce = !isSequenceReceiver
                && !receiverClassifier.isConcreteListLikeType(receiverType)
            let accumulatorType: TypeID = if isIterableRunningReduce,
                                              let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
                                                  args[0].expr,
                                                  ctx: ctx,
                                                  paramCount: 2
                                              ),
                                              let annotated = annotations[0]
            {
                annotated
            } else {
                collectionElementType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [accumulatorType, collectionElementType],
                returnType: accumulatorType
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
                    args: [.invariant(accumulatorType)],
                    nullability: .nonNull
                )))
            } else {
                resultType = sema.types.anyType
            }
            let sourceTypeArguments = isIterableRunningReduce
                ? [accumulatorType, collectionElementType]
                : [collectionElementType]
            let didBindSource = isIterableRunningReduce
                ? bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments)
                : bindBundledListSourceFunction(typeArguments: sourceTypeArguments)
            if didBindSource {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "runningReduceIndexed":
            guard args.count == 1 else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "runningReduceIndexed() expects 1 argument (a lambda), but \(args.count) were supplied.",
                    range: ast.arena.exprRange(id)
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            let isIterableRunningReduce = !isSequenceReceiver
                && !receiverClassifier.isConcreteListLikeType(receiverType)
            let accumulatorType: TypeID = if isIterableRunningReduce,
                                              let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
                                                  args[0].expr,
                                                  ctx: ctx,
                                                  paramCount: 3
                                              ),
                                              let annotated = annotations[1]
            {
                annotated
            } else {
                collectionElementType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [sema.types.intType, accumulatorType, collectionElementType],
                returnType: accumulatorType
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
                    args: [.invariant(accumulatorType)],
                    nullability: .nonNull
                )))
            } else {
                resultType = sema.types.anyType
            }
            let sourceTypeArguments = isIterableRunningReduce
                ? [accumulatorType, collectionElementType]
                : [collectionElementType]
            let didBindSource = isIterableRunningReduce
                ? bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments)
                : bindBundledListSourceFunction(typeArguments: sourceTypeArguments)
            if didBindSource {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "groupBy":
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.nullableAnyType
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let keyType = inferredLambdaReturnType(
                argExpr: args[0].expr, ast: ast, sema: sema
            )
            var valueElementType = collectionElementType
            if args.count >= 2 {
                let valueLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: sema.types.nullableAnyType
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
            let groupByTypeArgs: [TypeID] = args.count >= 2
                ? [collectionElementType, keyType, valueElementType]
                : [collectionElementType, keyType]
            let didBindSource = bindBundledListSourceFunction(typeArguments: groupByTypeArgs)
                || bindBundledIterableSourceFunction(typeArguments: groupByTypeArgs)
            if didBindSource {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
                if args.count >= 2,
                   let lambdaExpr = ast.arena.expr(args[1].expr),
                   lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                }
            }

        case "associateByTo", "associateWithTo", "groupByTo":
            // *To(destination, keySelector/valueSelector, [valueTransform]): returns the destination map
            guard args.count == 2 || (args.count == 3 && calleeStr != "associateWithTo") else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            var destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            var nonNullableDestType = sema.types.makeNonNullable(destType)

            // The bundled declarations bound the destination as a
            // `MutableMap` (`M : MutableMap<in K, in V>` for associateByTo /
            // associateWithTo, `M : MutableMap<in K, MutableList<V>>` for
            // groupByTo). Re-parameterize the bound with the destination's own
            // arguments — the same nominal-family check the collection
            // destination path runs — so a non-map destination such as
            // `mutableListOf()` cannot reach lowering (KUU-4292).
            if let mutableMapSymbol = lookupStdlibSymbol("MutableMap", symbols: sema.symbols, interner: interner) {
                let shapeBoundArguments: [TypeArg] = if case let .classType(destClassType) = sema.types.kind(
                    of: nonNullableDestType
                ), destClassType.args.count >= 2 {
                    destClassType.args.prefix(2).map { argument in
                        switch argument {
                        case let .invariant(type), let .out(type), let .in(type): .in(type)
                        case .star: .in(sema.types.nothingType)
                        }
                    }
                } else {
                    [.in(sema.types.nothingType), .in(sema.types.nothingType)]
                }
                let destinationShapeBound = sema.types.make(.classType(ClassType(
                    classSymbol: mutableMapSymbol,
                    args: shapeBoundArguments,
                    nullability: .nonNull
                )))
                guard sema.types.isSubtype(nonNullableDestType, destinationShapeBound) else {
                    let actualTypeName = sema.types.displayName(
                        of: destType,
                        symbols: sema.symbols,
                        interner: interner
                    )
                    let requiredTypeName = sema.types.displayName(
                        of: destinationShapeBound,
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
            let destKeyType: TypeID
            let destValueType: TypeID
            if let destClassType = resolveClassType(nonNullableDestType, sema: sema),
               destClassType.args.count >= 2
            {
                destKeyType = switch destClassType.args[0] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.nullableAnyType
                }
                destValueType = switch destClassType.args[1] {
                case let .invariant(id), let .out(id), let .in(id): id
                case .star: sema.types.nullableAnyType
                }
            } else {
                destKeyType = sema.types.nullableAnyType
                destValueType = sema.types.nullableAnyType
            }
            let destinationNeedsDeferredInference = isInferableNestedCallExpr(args[0].expr, ast: ast)
                && (typeContainsNothingType(destKeyType, sema: sema)
                    || typeContainsNothingType(destValueType, sema: sema))

            let firstLambdaReturnType: TypeID = destinationNeedsDeferredInference
                ? sema.types.nullableAnyType
                : ((calleeStr == "associateWithTo") ? destValueType : destKeyType)
            let firstLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: firstLambdaReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
            }
            _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: firstLambdaExpectedType)
            let firstLambdaReturn = inferredLambdaReturnType(
                argExpr: args[1].expr, ast: ast, sema: sema
            )

            var valueType: TypeID = destValueType
            if args.count == 3 {
                // For groupByTo the destination stores MutableList<V>, so the lambda returns V.
                let secondLambdaExpectedReturn: TypeID
                if destinationNeedsDeferredInference {
                    secondLambdaExpectedReturn = sema.types.nullableAnyType
                } else if calleeStr == "groupByTo" {
                    secondLambdaExpectedReturn = extractListElementType(destValueType, sema: sema, interner: interner)
                } else {
                    secondLambdaExpectedReturn = destValueType
                }
                let secondLambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [collectionElementType],
                    returnType: secondLambdaExpectedReturn,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[2].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[2].expr)
                }
                _ = driver.inferExpr(args[2].expr, ctx: ctx, locals: &locals, expectedType: secondLambdaExpectedType)
                valueType = inferredLambdaReturnType(
                    argExpr: args[2].expr, ast: ast, sema: sema
                )
            }

            if destinationNeedsDeferredInference,
               let mapSymbol = lookupStdlibSymbol("MutableMap", symbols: sema.symbols, interner: interner) {
                let keyType = calleeStr == "associateWithTo" ? collectionElementType : firstLambdaReturn
                let inferredValueType = args.count == 3 ? valueType : collectionElementType
                let mapValueType: TypeID
                if calleeStr == "associateWithTo" {
                    mapValueType = firstLambdaReturn
                } else if calleeStr == "groupByTo",
                          let listSymbol = lookupStdlibSymbol("MutableList", symbols: sema.symbols, interner: interner) {
                    mapValueType = sema.types.make(.classType(ClassType(
                        classSymbol: listSymbol,
                        args: [.invariant(inferredValueType)],
                        nullability: .nonNull
                    )))
                } else {
                    mapValueType = inferredValueType
                }
                let boundType = sema.types.make(.classType(ClassType(
                    classSymbol: mapSymbol,
                    args: [.invariant(keyType), .invariant(mapValueType)],
                    nullability: .nonNull
                )))
                if let destinationExpectedType = concreteNestedCallExpectedType(
                    originalArgumentType: nonNullableDestType,
                    boundType: boundType,
                    sema: sema
                ) {
                    // The first pass diagnosed the still-unconstrained
                    // destination call (KSWIFTK-SEMA-INFER on bare factories
                    // such as `mutableMapOf()`); the re-inference below
                    // re-derives it under the destination bound, so drop
                    // those stale errors up front and restore them only when
                    // re-inference fails.
                    let firstPassDestinationDiagnostics: [Diagnostic] = ast.arena
                        .exprRange(args[0].expr)
                        .map { ctx.sema.diagnostics.removeErrorDiagnostics(containedIn: $0) }
                        ?? []
                    let reinferDiagnosticsCheckpoint = ctx.sema.diagnostics.checkpoint()
                    let reinferredType = driver.inferExpr(
                        args[0].expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: destinationExpectedType
                    )
                    if reinferredType != sema.types.errorType,
                       !typeContainsNothingType(reinferredType, sema: sema)
                    {
                        destType = reinferredType
                        nonNullableDestType = sema.types.makeNonNullable(destType)
                    } else {
                        ctx.sema.diagnostics.rollback(to: reinferDiagnosticsCheckpoint)
                        for diagnostic in firstPassDestinationDiagnostics {
                            ctx.sema.diagnostics.emit(diagnostic)
                        }
                    }
                }
            }

            // The shape check above re-parameterized `MutableMap` with the
            // destination's *own* arguments, so it only proves the destination
            // is a map at all. kotlinc declares the bound contravariantly —
            // `M : MutableMap<in K, in V>` for associateByTo/associateWithTo
            // and `M : MutableMap<in K, MutableList<V>>` for groupByTo — which
            // additionally requires the destination key/value types to be
            // *supertypes* of what the selectors produce. The produced types
            // are only knowable after the lambdas — and any deferred factory
            // destination — have been inferred, so the check runs here
            // against the final destination type (KUU-4292).
            let producedLambdaReturn: (ExprID) -> TypeID? = { argExpr in
                if case let .lambdaLiteral(_, bodyExpr, _, _) = self.ast.arena.expr(argExpr) {
                    return self.sema.bindings.exprType(for: bodyExpr)
                }
                if let argType = self.sema.bindings.exprType(for: argExpr),
                   case let .functionType(functionType) = self.sema.types.kind(of: argType)
                {
                    return functionType.returnType
                }
                return nil
            }
            // A receiver whose declared type arguments are absent
            // (`class L : MutableList<Int>`) leaves `collectionElementType` at
            // its `Any` fallback — not evidence the bound demands `in Any`,
            // so element-derived positions stay unchecked there (the same
            // guard the collection destination path applies).
            let receiverDeclaresElementArgument = collectionElementType != sema.types.anyType
                || (resolveClassType(receiverType, sema: sema).map { !$0.args.isEmpty } ?? false)
            let requiredKeyType: TypeID?
            let requiredValueType: TypeID?
            let requiredGroupElementType: TypeID?
            switch calleeStr {
            case "associateWithTo":
                requiredKeyType = receiverDeclaresElementArgument ? collectionElementType : nil
                requiredValueType = producedLambdaReturn(args[1].expr)
                requiredGroupElementType = nil
            case "associateByTo":
                requiredKeyType = producedLambdaReturn(args[1].expr)
                requiredValueType = args.count == 3
                    ? producedLambdaReturn(args[2].expr)
                    : (receiverDeclaresElementArgument ? collectionElementType : nil)
                requiredGroupElementType = nil
            default:
                requiredKeyType = producedLambdaReturn(args[1].expr)
                requiredValueType = nil
                requiredGroupElementType = args.count == 3
                    ? producedLambdaReturn(args[2].expr)
                    : (receiverDeclaresElementArgument ? collectionElementType : nil)
            }
            // A `nil` produced type means the call never fixed it — an
            // unbound lambda result or a receiver without declared type
            // arguments — so there is no evidence the bound is violated;
            // checking anyway could reject destinations the bound does not
            // actually forbid.
            var requiredBoundViolation = false
            var requiredBoundForMessage: TypeID?
            if let requiredKeyType,
               !typeContainsNothingType(nonNullableDestType, sema: sema),
               let mutableMapSymbol = lookupStdlibSymbol("MutableMap", symbols: sema.symbols, interner: interner)
            {
                if calleeStr == "groupByTo" {
                    if let requiredGroupElementType,
                       let mutableListSymbol = lookupStdlibSymbol("MutableList", symbols: sema.symbols, interner: interner)
                    {
                        let messageListType = sema.types.make(.classType(ClassType(
                            classSymbol: mutableListSymbol,
                            args: [.invariant(requiredGroupElementType)],
                            nullability: .nonNull
                        )))
                        requiredBoundForMessage = sema.types.make(.classType(ClassType(
                            classSymbol: mutableMapSymbol,
                            args: [.in(requiredKeyType), .invariant(messageListType)],
                            nullability: .nonNull
                        )))
                        // The `in Nothing` placeholder verifies the key
                        // position and the `MutableMap` nominal shape without
                        // committing `V`; the invariant `MutableList<V>` value
                        // is verified separately below.
                        let keyAndShapeBound = sema.types.make(.classType(ClassType(
                            classSymbol: mutableMapSymbol,
                            args: [.in(requiredKeyType), .in(sema.types.nothingType)],
                            nullability: .nonNull
                        )))
                        requiredBoundViolation = !sema.types.isSubtype(nonNullableDestType, keyAndShapeBound)
                            || !groupByDestinationValueAccepts(
                                nonNullableDestType,
                                producedElementType: requiredGroupElementType,
                                mutableMapSymbol: mutableMapSymbol,
                                mutableListSymbol: mutableListSymbol
                            )
                    }
                } else if let requiredValueType {
                    let requiredBound = sema.types.make(.classType(ClassType(
                        classSymbol: mutableMapSymbol,
                        args: [.in(requiredKeyType), .in(requiredValueType)],
                        nullability: .nonNull
                    )))
                    requiredBoundForMessage = requiredBound
                    requiredBoundViolation = !sema.types.isSubtype(nonNullableDestType, requiredBound)
                }
            }
            if requiredBoundViolation, let requiredBoundForMessage {
                let actualTypeName = sema.types.displayName(
                    of: destType,
                    symbols: sema.symbols,
                    interner: interner
                )
                let requiredTypeName = sema.types.displayName(
                    of: requiredBoundForMessage,
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
                for argumentIndex in [1, 2] where argumentIndex < args.count {
                    if let lambdaExpr = ast.arena.expr(args[argumentIndex].expr),
                       lambdaExpr.isLambdaOrCallableRef
                    {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[argumentIndex].expr)
                    }
                }
                return sema.types.errorType
            }

            resultType = destType

            // Source-backed overloads:
            //   associateByTo<T,K,M> / associateByTo<T,K,V,M> / associateWithTo<T,V,M>
            //   groupByTo<T,K,M> / groupByTo<T,K,V,M>
            let toTypeArgs: [TypeID] = args.count == 3
                ? [collectionElementType, firstLambdaReturn, valueType, nonNullableDestType]
                : [collectionElementType, firstLambdaReturn, nonNullableDestType]
            let didBindSource = bindBundledListSourceFunction(typeArguments: toTypeArgs)
                || bindBundledIterableSourceFunction(typeArguments: toTypeArgs)
            if didBindSource {
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                }
                if args.count == 3,
                   let lambdaExpr = ast.arena.expr(args[2].expr),
                   lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[2].expr)
                }
            }

        case "sortedBy", "sortedByDescending", "sortBy", "sortByDescending":
            let isInPlaceMutation = calleeStr == "sortBy" || calleeStr == "sortByDescending"
            guard args.count == 1 else {
                let failedType = isInPlaceMutation ? sema.types.unitType : sema.types.anyType
                sema.bindings.bindExprType(id, type: failedType)
                return failedType
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType],
                returnType: sema.types.nullableAnyType
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
            if selectorType != sema.types.anyType {
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
                if !isPrimitiveComparable, !isNominalComparable {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-BOUND",
                        "Type argument does not satisfy upper bound constraint.",
                        range: ast.arena.exprRange(id)
                    )
                    let failedType = isInPlaceMutation ? sema.types.unitType : (safeCall ? sema.types.nullableAnyType : sema.types.anyType)
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
            }
            if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType]) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isInPlaceMutation {
                resultType = sema.types.unitType
            } else if isSequenceReceiver {
                resultType = receiverType
            } else {
                resultType = listResultType
            }
            if !isInPlaceMutation, isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, selectorType]
            }
            if !isInPlaceMutation, !isSequenceReceiver {
                sourceBackedIterableAggregateTypeArguments = [collectionElementType, selectorType]
            }

        case "sort", "sorted", "sortedDescending":
            let isInPlaceMutation = calleeStr == "sort"
            guard args.isEmpty else {
                let failedType = isInPlaceMutation ? sema.types.unitType : sema.types.anyType
                sema.bindings.bindExprType(id, type: failedType)
                return failedType
            }
            if let comparableSymbol = sema.types.comparableInterfaceSymbol {
                let comparableElementType = sema.types.make(.classType(ClassType(
                    classSymbol: comparableSymbol,
                    args: [.invariant(collectionElementType)],
                    nullability: .nonNull
                )))
                if !sema.types.isSubtype(collectionElementType, comparableElementType) {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-BOUND",
                        "Type argument does not satisfy upper bound constraint.",
                        range: ast.arena.exprRange(id)
                    )
                    let failedType = isInPlaceMutation ? sema.types.unitType : (safeCall ? sema.types.nullableAnyType : sema.types.anyType)
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
            }
            if !bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType])
            }
            if isInPlaceMutation {
                resultType = sema.types.unitType
            } else if isSequenceReceiver {
                resultType = receiverType
            } else {
                resultType = listResultType
            }

        case "sortedWith", "sortedArrayWith", "sortWith":
            let isInPlaceMutation = calleeStr == "sortWith"
            guard args.count == 1 else {
                let failedType = isInPlaceMutation ? sema.types.unitType : sema.types.anyType
                sema.bindings.bindExprType(id, type: failedType)
                return failedType
            }
            let usesRuntimeFunctionPointerComparator = calleeStr == "sortedArrayWith"
            let functionExpectedType = sema.types.make(.functionType(FunctionType(
                params: [collectionElementType, collectionElementType],
                returnType: sema.types.intType
            )))
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.in(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                nil
            }
            if usesRuntimeFunctionPointerComparator {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: functionExpectedType)
                } else {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                }
            } else if isSequenceReceiver {
                let argExpr = ast.arena.expr(args[0].expr)
                if argExpr?.isLambdaOrCallableRef == true {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                } else {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                }
            } else if (calleeStr == "sortedWith" || calleeStr == "sortWith"),
                      receiverClassifier.isConcreteListLikeType(receiverType) || isListFactoryReceiver
            {
                let argExpr = ast.arena.expr(args[0].expr)
                if argExpr?.isLambdaOrCallableRef == true {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: functionExpectedType)
                    _ = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType],
                        matchingParameterType: functionExpectedType
                    )
                } else if case .nameRef = argExpr {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                    let argType = sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType
                    let argKind = sema.types.kind(of: argType)
                    if case .functionType = argKind {
                        _ = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType],
                            matchingParameterType: functionExpectedType
                        )
                    } else {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                        _ = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType],
                            matchingParameterType: comparatorExpectedType ?? sema.types.nothingType
                        )
                    }
                } else {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                    _ = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType],
                        matchingParameterType: comparatorExpectedType ?? sema.types.nothingType
                    )
                }
            } else if calleeStr == "sortedWith", !isSequenceReceiver {
                // KUU-542: Set/Collection receivers bind the bundled
                // Iterable<T>.sortedWith declaration, whose only parameter
                // shape is Comparator — a lambda literal must be inferred
                // as a Comparator (SAM) for the call to dispatch. A
                // function-typed argument cannot take that shape, so it is
                // left unbound exactly as before.
                let argExpr = ast.arena.expr(args[0].expr)
                if argExpr?.isLambdaOrCallableRef == true {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                } else {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                }
                if isComparatorTypedArgument(args[0].expr) {
                    sourceBackedIterableAggregateTypeArguments = [collectionElementType]
                }
            } else {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
            }
            if isInPlaceMutation {
                resultType = sema.types.unitType
            } else if calleeStr == "sortedArrayWith" {
                resultType = receiverType
            } else if isSequenceReceiver {
                resultType = receiverType
            } else {
                resultType = listResultType
            }
            if !isInPlaceMutation, isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "maxWith", "minWith", "maxWithOrNull", "minWithOrNull":
            guard args.count == 1 else {
                let failedType = (calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull")
                    ? sema.types.makeNullable(sema.types.errorType)
                    : sema.types.errorType
                sema.bindings.bindExprType(id, type: failedType)
                return failedType
            }
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [.in(collectionElementType)],
                    nullability: .nonNull
                )))
            } else {
                nil
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
            if isMapReceiver,
               calleeStr == "maxWith" || calleeStr == "minWith"
                   || calleeStr == "maxWithOrNull" || calleeStr == "minWithOrNull"
            {
                _ = bindBundledMapSourceFunction(locals: &locals)
            } else if !isSequenceReceiver, bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            // KUU-542: the bundled Iterable *With overloads take a
            // Comparator parameter, so a function-typed comparator (an
            // invalid Kotlin call shape) must stay unbound rather than
            // misdispatching through the source declaration.
            if isComparatorTypedArgument(args[0].expr) {
                sourceBackedIterableAggregateTypeArguments = [collectionElementType]
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
                returnType: sema.types.nullableAnyType
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
            let comparatorFQName: [InternedString] = [interner.intern("kotlin"), interner.intern("Comparator")]
            let usesIterableMinComparator = (calleeStr == "minOfWith" || calleeStr == "minOfWithOrNull")
                && !isSequenceReceiver
                && !isMapReceiver
                && !receiverClassifier.isConcreteListLikeType(receiverType)
                && !isListFactoryReceiver
            let comparatorExpectedType: TypeID? = if let comparatorSymbol = sema.symbols.lookup(fqName: comparatorFQName) {
                sema.types.make(.classType(ClassType(
                    classSymbol: comparatorSymbol,
                    args: [usesIterableMinComparator ? .in(selectorResultType) : .invariant(selectorResultType)],
                    nullability: .nonNull
                )))
            } else {
                nil
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
            if isMapReceiver,
               calleeStr == "maxOfWith" || calleeStr == "minOfWith"
                   || calleeStr == "maxOfWithOrNull" || calleeStr == "minOfWithOrNull"
            {
                if bindBundledMapSourceFunction(matchingLambdaReturnType: selectorResultType, locals: &locals) {
                    if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                    }
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                }
            } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorResultType]) {
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isComparatorTypedArgument(args[0].expr) {
                sourceBackedIterableAggregateTypeArguments = [collectionElementType, selectorResultType]
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
            if bindBundledListSourceFunction(typeArguments: [collectionElementType]) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }

            default:
                break
        }
        return nil
    }

    /// `groupByTo` stores `MutableList<V>` values: the destination's map value
    /// argument must itself be a `MutableList<X>` and the produced element
    /// only needs to be a subtype of `X`. kotlinc fixes `V := X` through the
    /// invariant `MutableList<V>` position of `MutableMap<in K, MutableList<V>>`
    /// rather than comparing the produced element type against the whole list
    /// type — so `MutableMap<String, MutableList<Int?>>` still accepts an
    /// `Int` transform while `MutableMap<String, List<Int>>` and
    /// `MutableMap<String, ArrayList<Int>>` do not (KUU-4292).
    ///
    /// The value argument is read through the destination's `MutableMap`
    /// supertype so map implementations whose own type parameters do not
    /// mirror `MutableMap`'s (for example `class StringKeyMap<V> :
    /// MutableMap<String, V>`) are checked by their projected map type rather
    /// than rejected for lacking two type arguments of their own.
    func groupByDestinationValueAccepts(
        _ destinationType: TypeID,
        producedElementType: TypeID,
        mutableMapSymbol: SymbolID,
        mutableListSymbol: SymbolID
    ) -> Bool {
        guard case let .classType(destinationClass) = sema.types.kind(of: destinationType),
              let mapArguments = sema.types.liftedNominalSupertypeArgs(
                  from: destinationClass,
                  to: mutableMapSymbol
              ),
              mapArguments.count >= 2
        else {
            // A destination that is not a concrete `MutableMap` class type —
            // a type parameter bounded by one, an intersection, or an
            // already-failed expression — gives no positive evidence the
            // `MutableList<V>` slot is violated, so the check stays lenient
            // there rather than rejecting what the bound does not forbid.
            return true
        }
        let mapValueType: TypeID?
        switch mapArguments[1] {
        case let .invariant(id), let .out(id), let .in(id):
            mapValueType = id
        case .star:
            mapValueType = nil
        }
        guard let mapValueType else {
            // `MutableMap<K, *>` cannot satisfy the invariant `MutableList<V>`
            // slot for any concrete `V`.
            return false
        }
        guard case let .classType(valueClass) = sema.types.kind(
            of: sema.types.makeNonNullable(mapValueType)
        ) else {
            // A non-class value argument (a type parameter, an error type)
            // is not positive evidence of a violation either.
            return true
        }
        guard valueClass.classSymbol == mutableListSymbol,
              valueClass.args.count == 1
        else {
            return false
        }
        let listElementType: TypeID?
        switch valueClass.args[0] {
        case let .invariant(id), let .out(id), let .in(id):
            listElementType = id
        case .star:
            listElementType = nil
        }
        guard let listElementType else {
            return false
        }
        return sema.types.isSubtype(producedElementType, listElementType)
    }
}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
