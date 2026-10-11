// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker.MemberCallCollectionFlowContext {
    func inferCollectionHOFAggregateAndSortCases(locals: inout LocalBindings) -> TypeID? {
        switch calleeStr {
        case "fold":
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
            }

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
            if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
            if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
            if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
            if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

        case "reduce":
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType]
            }

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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
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
            if isSequenceReceiver {
                sourceBackedSequenceAggregateTypeArguments = [collectionElementType, initialType]
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
                ? bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments, locals: &locals)
                : bindBundledListSourceFunction(typeArguments: sourceTypeArguments, locals: &locals)
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
                ctx.semaCtx.diagnostics.error(
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
                ? bindBundledIterableSourceFunction(typeArguments: sourceTypeArguments, locals: &locals)
                : bindBundledListSourceFunction(typeArguments: sourceTypeArguments, locals: &locals)
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
            // Two-lambda variant: groupBy(keySelector, valueTransform)
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
            let didBindSource = bindBundledListSourceFunction(typeArguments: groupByTypeArgs, locals: &locals)
                || bindBundledIterableSourceFunction(typeArguments: groupByTypeArgs, locals: &locals)
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
            guard args.count == 2 || args.count == 3 else {
                sema.bindings.bindExprType(id, type: sema.types.anyType)
                return sema.types.anyType
            }
            // Infer the destination map argument first
            var destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedType)
            var nonNullableDestType = sema.types.makeNonNullable(destType)
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

            // First lambda return type: value for associateWithTo, key otherwise.
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
                // Second lambda provides the transformed value.
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
                    destType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: destinationExpectedType)
                    nonNullableDestType = sema.types.makeNonNullable(destType)
                }
            }

            // Return type is the destination map type
            resultType = destType

            // Source-backed overloads:
            //   associateByTo<T,K,M> / associateByTo<T,K,V,M> / associateWithTo<T,V,M>
            //   groupByTo<T,K,M> / groupByTo<T,K,V,M>
            let toTypeArgs: [TypeID] = args.count == 3
                ? [collectionElementType, firstLambdaReturn, valueType, nonNullableDestType]
                : [collectionElementType, firstLambdaReturn, nonNullableDestType]
            let didBindSource = bindBundledListSourceFunction(typeArguments: toTypeArgs, locals: &locals)
                || bindBundledIterableSourceFunction(typeArguments: toTypeArgs, locals: &locals)
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
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-BOUND",
                        "Type argument does not satisfy upper bound constraint.",
                        range: ast.arena.exprRange(id)
                    )
                    let failedType = isInPlaceMutation ? sema.types.unitType : (safeCall ? sema.types.nullableAnyType : sema.types.anyType)
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
            }
            if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorType], locals: &locals) {
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
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-BOUND",
                        "Type argument does not satisfy upper bound constraint.",
                        range: ast.arena.exprRange(id)
                    )
                    let failedType = isInPlaceMutation ? sema.types.unitType : (safeCall ? sema.types.nullableAnyType : sema.types.anyType)
                    sema.bindings.bindExprType(id, type: failedType)
                    return failedType
                }
            }
            if !bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                _ = bindBundledIterableSourceFunction(typeArguments: [collectionElementType], locals: &locals)
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
                    , locals: &locals)
                } else if case .nameRef = argExpr {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: nil)
                    let argType = sema.bindings.exprType(for: args[0].expr) ?? sema.types.anyType
                    let argKind = sema.types.kind(of: argType)
                    if case .functionType = argKind {
                        _ = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType],
                            matchingParameterType: functionExpectedType
                        , locals: &locals)
                    } else {
                        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                        _ = bindBundledListSourceFunction(
                            typeArguments: [collectionElementType],
                            matchingParameterType: comparatorExpectedType ?? sema.types.nothingType
                        , locals: &locals)
                    }
                } else {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: comparatorExpectedType)
                    _ = bindBundledListSourceFunction(
                        typeArguments: [collectionElementType],
                        matchingParameterType: comparatorExpectedType ?? sema.types.nothingType
                    , locals: &locals)
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
                if isComparatorTypedArgument(args[0].expr, locals: &locals) {
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
            } else if !isSequenceReceiver, bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            // KUU-542: the bundled Iterable *With overloads take a
            // Comparator parameter, so a function-typed comparator (an
            // invalid Kotlin call shape) must stay unbound rather than
            // misdispatching through the source declaration.
            if isComparatorTypedArgument(args[0].expr, locals: &locals) {
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
            } else if bindBundledListSourceFunction(typeArguments: [collectionElementType, selectorResultType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[1].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[1].expr)
                }
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
            // KUU-542: same Comparator-parameter guard as *With above.
            if isComparatorTypedArgument(args[0].expr, locals: &locals) {
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
            if bindBundledListSourceFunction(typeArguments: [collectionElementType], locals: &locals) {
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }

            default:
                break
        }
        return nil
    }
}

// swiftlint:enable cyclomatic_complexity file_length function_body_length
