// swiftlint:disable function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func inferFlatMapTransformArgument(
        _ argumentExpr: ExprID,
        parameterTypes: [TypeID],
        expectedCallResultType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        let interner = ctx.interner
        var returnCandidates: [TypeID] = []
        if let expectedCallResultType {
            let nonNullExpected = sema.types.makeNonNullable(expectedCallResultType)
            let elementType = extractIterableOrSequenceElementType(
                nonNullExpected, sema: sema, interner: interner
            )
            if elementType != sema.types.anyType {
                let expectedIsSequence = isSequenceLikeType(
                    nonNullExpected, sema: sema, interner: interner
                )
                let iterableType = lookupStdlibSymbol(
                    "Iterable", symbols: sema.symbols, interner: interner
                ).map {
                    sema.types.make(.classType(ClassType(
                        classSymbol: $0,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                }
                let sequenceType = lookupStdlibSymbol(
                    "Sequence", symbols: sema.symbols, interner: interner
                ).map {
                    sema.types.make(.classType(ClassType(
                        classSymbol: $0,
                        args: [.invariant(elementType)],
                        nullability: .nonNull
                    )))
                }
                let ordered = expectedIsSequence
                    ? [sequenceType, iterableType]
                    : [iterableType, sequenceType]
                returnCandidates = ordered.compactMap { $0 }
            }
        }
        returnCandidates.append(sema.types.anyType)
        for returnType in returnCandidates {
            let checkpoint = sema.diagnostics.checkpoint()
            var attemptLocals = locals
            let functionType = sema.types.make(.functionType(FunctionType(
                params: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                argumentExpr, ctx: ctx, locals: &attemptLocals, expectedType: functionType
            )
            let emittedError = sema.diagnostics.diagnostics
                .dropFirst(checkpoint)
                .contains { $0.severity == .error }
            if !emittedError {
                locals = attemptLocals
                return
            }
            if returnType == sema.types.anyType {
                locals = attemptLocals
                return
            }
            sema.diagnostics.rollback(to: checkpoint)
        }
    }

    func inferFirstNotNullTransformArgument(
        _ argumentExpr: ExprID,
        parameterTypes: [TypeID],
        expectedCallResultType: TypeID?,
        fallbackReturnType: TypeID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        let sema = ctx.sema
        var returnCandidates: [TypeID] = []
        if let expectedCallResultType {
            // Both `firstNotNullOf` and `firstNotNullOfOrNull` transforms return
            // `R?`, so the lambda body's expected return is always nullable. A
            // non-null seed (e.g. `Unit` for a discarded result) would trigger
            // Unit-coercion that discards the body's `null` and break
            // null-skipping, diverging from kotlinc.
            let nonNullExpected = sema.types.makeNonNullable(expectedCallResultType)
            let seeded = sema.types.makeNullable(nonNullExpected)
            if seeded != sema.types.anyType,
               seeded != sema.types.nullableAnyType,
               seeded != fallbackReturnType
            {
                returnCandidates.append(seeded)
            }
        }
        returnCandidates.append(fallbackReturnType)
        guard returnCandidates.count > 1 else {
            let functionType = sema.types.make(.functionType(FunctionType(
                params: parameterTypes,
                returnType: fallbackReturnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                argumentExpr, ctx: ctx, locals: &locals, expectedType: functionType
            )
            return
        }
        for returnType in returnCandidates {
            let checkpoint = sema.diagnostics.checkpoint()
            var attemptLocals = locals
            let functionType = sema.types.make(.functionType(FunctionType(
                params: parameterTypes,
                returnType: returnType,
                isSuspend: false,
                nullability: .nonNull
            )))
            _ = driver.inferExpr(
                argumentExpr, ctx: ctx, locals: &attemptLocals, expectedType: functionType
            )
            let emittedError = sema.diagnostics.diagnostics
                .dropFirst(checkpoint)
                .contains { $0.severity == .error }
            if !emittedError {
                locals = attemptLocals
                return
            }
            if returnType == fallbackReturnType {
                locals = attemptLocals
                return
            }
            sema.diagnostics.rollback(to: checkpoint)
        }
    }

    func tryInferMemberCallEarlyReceiverSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let flatMapMemberName = request.interner.resolve(request.calleeName)
        if (flatMapMemberName == "flatMap" || flatMapMemberName == "flatMapIndexed"),
           request.args.count == 1,
           isSequenceLikeType(receiverType, sema: request.sema, interner: request.interner)
        {
            let receiverElementType: TypeID = if case let .classType(classType) = request.sema.types.kind(
                of: request.sema.types.makeNonNullable(receiverType)
            ), let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    request.sema.types.anyType
                }
            } else {
                request.sema.types.anyType
            }
            let lambdaParameterTypes: [TypeID] = flatMapMemberName == "flatMapIndexed"
                ? [request.sema.types.intType, receiverElementType]
                : [receiverElementType]
            if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
            }
            inferFlatMapTransformArgument(
                request.args[0].expr,
                parameterTypes: lambdaParameterTypes,
                expectedCallResultType: request.expectedType,
                ctx: request.ctx,
                locals: &locals
            )
            let lambdaBodyType = inferredLambdaReturnType(
                argExpr: request.args[0].expr,
                ast: request.ast,
                sema: request.sema
            )
            let flattenedElementType = flatMapTransformElementType(
                lambdaArgExpr: request.args[0].expr,
                returnType: lambdaBodyType,
                ast: request.ast,
                sema: request.sema,
                interner: request.interner
            )
            if let sourceCallee = sourceBackedSequenceFlatMapOverload(
                named: flatMapMemberName,
                lambdaBodyType: lambdaBodyType,
                sema: request.sema,
                interner: request.interner
            ) {
                request.sema.bindings.bindCall(
                    request.id,
                    binding: CallBinding(
                        chosenCallee: sourceCallee,
                        substitutedTypeArguments: [receiverElementType, flattenedElementType],
                        parameterMapping: [0: 0]
                    )
                )
                request.sema.bindings.bindCallableTarget(request.id, target: .symbol(sourceCallee))
                if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    request.sema.bindings.unmarkCollectionHOFLambdaExpr(request.args[0].expr)
                }
            } else if let owner = driver.helpers.nominalSymbol(
                of: request.sema.types.makeNonNullable(receiverType),
                types: request.sema.types
            ),
                let ownerSymbol = request.sema.symbols.symbol(owner)
            {
                let memberFQName = ownerSymbol.fqName + [request.calleeName]
                if let fallbackCallee = request.sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let symbol = request.sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          request.sema.symbols.parentSymbol(for: candidate) == owner,
                          let signature = request.sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.parameterTypes.count == 1
                }) {
                    request.sema.bindings.bindCall(
                        request.id,
                        binding: CallBinding(
                            chosenCallee: fallbackCallee,
                            substitutedTypeArguments: [],
                            parameterMapping: [0: 0]
                        )
                    )
                    request.sema.bindings.bindCallableTarget(request.id, target: .symbol(fallbackCallee))
                }
            }
            request.sema.bindings.markCollectionExpr(request.id)
            let resultType = makeSyntheticSequenceType(
                symbols: request.sema.symbols,
                types: request.sema.types,
                interner: request.interner,
                elementType: flattenedElementType
            )
            let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }
        if (flatMapMemberName == "flatMap" || flatMapMemberName == "flatMapIndexed"),
           request.args.count == 1,
           !isSequenceLikeType(receiverType, sema: request.sema, interner: request.interner)
        {
            let classifier = receiverClassifier(sema: request.sema, interner: request.interner)
            let receiverIsListLike = classifier.isListLikeType(receiverType)
            // `flatMap` is only claimed for Collection-family receivers —
            // `Collection<T>`/`MutableCollection<T>` are routed into the
            // collection fast path which never binds `flatMap`, while plain
            // `Iterable<T>` receivers already resolve the right bundled
            // overload through regular overload resolution (claiming them
            // here would degrade the recorded lambda type to `(T) -> Any`).
            let claimableReceiver: Bool
            if receiverIsListLike {
                claimableReceiver = true
            } else {
                claimableReceiver = flatMapMemberName == "flatMap"
                    && classifier.isCollectionLikeType(receiverType)
                    && !classifier.isMapLikeCollectionType(receiverType)
                    && !classifier.isSetLikeType(receiverType)
                    && !classifier.isArrayLikeType(receiverType)
            }
            if claimableReceiver {
                let receiverElementType: TypeID = if case let .classType(classType) = request.sema.types.kind(
                    of: request.sema.types.makeNonNullable(receiverType)
                ), let firstArg = classType.args.first {
                    switch firstArg {
                    case let .invariant(type), let .in(type), let .out(type):
                        type
                    case .star:
                        request.sema.types.anyType
                    }
                } else {
                    request.sema.types.anyType
                }
                let lambdaParameterTypes: [TypeID] = flatMapMemberName == "flatMapIndexed"
                    ? [request.sema.types.intType, receiverElementType]
                    : [receiverElementType]
                if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                }
                inferFlatMapTransformArgument(
                    request.args[0].expr,
                    parameterTypes: lambdaParameterTypes,
                    expectedCallResultType: request.expectedType,
                    ctx: request.ctx,
                    locals: &locals
                )
                let lambdaBodyType = inferredLambdaReturnType(
                    argExpr: request.args[0].expr,
                    ast: request.ast,
                    sema: request.sema
                )
                let transformIsFlattenable = flatMapTransformIsFlattenable(
                    lambdaArgExpr: request.args[0].expr,
                    returnType: lambdaBodyType,
                    ast: request.ast,
                    sema: request.sema,
                    interner: request.interner
                )
                let claimCall = if receiverIsListLike {
                    transformIsFlattenable
                        && !classifier.isConcreteListLikeType(lambdaBodyType)
                } else {
                    transformIsFlattenable
                }
                if claimCall,
                   let sourceCallee = sourceBackedIterableFlatMapOverload(
                       named: flatMapMemberName,
                       lambdaBodyType: lambdaBodyType,
                       sema: request.sema,
                       interner: request.interner
                   )
                {
                    let flattenedElementType = flatMapTransformElementType(
                        lambdaArgExpr: request.args[0].expr,
                        returnType: lambdaBodyType,
                        ast: request.ast,
                        sema: request.sema,
                        interner: request.interner
                    )
                    request.sema.bindings.bindCall(
                        request.id,
                        binding: CallBinding(
                            chosenCallee: sourceCallee,
                            substitutedTypeArguments: [receiverElementType, flattenedElementType],
                            parameterMapping: [0: 0]
                        )
                    )
                    request.sema.bindings.bindCallableTarget(request.id, target: .symbol(sourceCallee))
                    if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        request.sema.bindings.unmarkCollectionHOFLambdaExpr(request.args[0].expr)
                    }
                    let resultType: TypeID = if let listSymbol = lookupStdlibSymbol(
                        "List",
                        symbols: request.sema.symbols,
                        interner: request.interner
                    ) {
                        request.sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(flattenedElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        request.sema.types.anyType
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(resultType) : resultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType
                }
                if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    request.sema.bindings.unmarkCollectionHOFLambdaExpr(request.args[0].expr)
                }
            }
        }
        if let boundContinuationCall = tryContinuationSyntheticMemberCall(
            request.id,
            calleeName: request.calleeName,
            receiverType: receiverType,
            args: request.args,
            range: request.range,
            ctx: request.ctx,
            locals: &locals
        ) {
            return boundContinuationCall
        }

        if let result = tryInferKClassReceiverMemberCall(
            request.id, receiverType: receiverType, calleeName: request.calleeName, args: request.args,
            explicitTypeArgs: request.explicitTypeArgs, range: request.range, ctx: request.ctx, locals: &locals
        ) {
            return result
        }

        if request.args.isEmpty,
           case let .nameRef(receiverName, _) = request.ast.arena.expr(request.receiverID),
           locals[receiverName] == nil,
           !receiverQualifierIsTypeAlias(receiverID: request.receiverID, ctx: request.ctx),
           let ownerSymbol = request.sema.bindings.identifierSymbol(for: request.receiverID),
           let owner = request.sema.symbols.symbol(ownerSymbol),
           owner.kind == .class || owner.kind == .interface || owner.kind == .enumClass,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: request.calleeName,
               sema: request.sema
           ),
           !(request.ast.arena.isExplicitCall(request.id)
               && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object)
        {
            if let memberSymbol = request.sema.symbols.symbol(staticMember.symbol),
               !request.ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: request.ctx.currentFileID,
                   enclosingClass: request.ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: memberSymbol,
                    name: request.interner.resolve(request.calleeName),
                    range: request.range,
                    diagnostics: request.ctx.sema.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            request.sema.bindings.bindIdentifier(request.id, symbol: staticMember.symbol)
            request.sema.bindings.bindExprType(request.id, type: staticMember.type)
            return staticMember.type
        }
        return nil
    }

    private func sourceBackedSequenceFlatMapOverload(
        named memberName: String,
        lambdaBodyType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("sequences"),
            interner.intern(memberName),
        ]
        let lambdaReturnsSequence = isSequenceLikeType(lambdaBodyType, sema: sema, interner: interner)
        let candidates = sema.symbols.lookupAll(fqName: fqName).filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  signature.receiverType != nil
            else {
                return false
            }
            return true
        }
        return candidates.first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  case let .functionType(transformType) = sema.types.kind(of: signature.parameterTypes[0])
            else {
                return false
            }
            return isSequenceLikeType(transformType.returnType, sema: sema, interner: interner)
                == lambdaReturnsSequence
        }) ?? candidates.first
    }

    private func sourceBackedIterableFlatMapOverload(
        named memberName: String,
        lambdaBodyType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        let fqName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern(memberName),
        ]
        let iterableFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        let lambdaReturnsSequence = isSequenceLikeType(lambdaBodyType, sema: sema, interner: interner)
        let candidates = sema.symbols.lookupAll(fqName: fqName).filter { candidate in
            guard sema.symbols.symbol(candidate)?.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let receiverType = signature.receiverType,
                  let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
                  receiverSymbol.fqName == iterableFQName
            else {
                return false
            }
            return true
        }
        return candidates.first(where: { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  case let .functionType(transformType) = sema.types.kind(of: signature.parameterTypes[0])
            else {
                return false
            }
            return isSequenceLikeType(transformType.returnType, sema: sema, interner: interner)
                == lambdaReturnsSequence
        }) ?? candidates.first
    }

    private func flatMapTransformIsFlattenable(
        lambdaArgExpr: ExprID,
        returnType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        if isSequenceLikeType(returnType, sema: sema, interner: interner) {
            return true
        }
        if nominalRangeElementType(for: returnType, sema: sema, interner: interner) != nil {
            return true
        }
        if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(lambdaArgExpr),
           sema.bindings.isRangeExpr(bodyExpr)
        {
            return true
        }
        return receiverClassifier(sema: sema, interner: interner).isIterableLikeType(returnType)
    }

    private func flatMapTransformElementType(
        lambdaArgExpr: ExprID,
        returnType: TypeID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        if let nominalElement = nominalRangeElementType(
            for: returnType, sema: sema, interner: interner
        ) {
            return nominalElement
        }
        let extracted = getCollectionElementType(returnType, sema: sema, interner: interner)
        if extracted != sema.types.anyType {
            return extracted
        }
        if case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(lambdaArgExpr),
           sema.bindings.isRangeExpr(bodyExpr)
        {
            return driver.helpers.rangeExprActualElementType(
                for: bodyExpr, bodyType: returnType, sema: sema, interner: interner
            )
        }
        return extracted
    }
}
