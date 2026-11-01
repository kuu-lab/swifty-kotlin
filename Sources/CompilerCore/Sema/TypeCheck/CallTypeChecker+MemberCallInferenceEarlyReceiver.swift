// swiftlint:disable function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallEarlyReceiverSpecials(
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
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        // KUU-4063: `flatMap`/`flatMapIndexed` select between two bundled
        // overloads that differ only in the transform's return type
        // (`(T) -> Sequence<R>` vs `(T) -> Iterable<R>`). The selection must
        // happen here for Sequence receivers (the collection fast path later
        // only binds the first declaration, so a range/Iterable transform
        // crashed at runtime) and for List receivers (regular overload
        // resolution commits to the `List.flatMap*` specialization and never
        // retries the `Iterable.flatMap*` variants).
        let flatMapMemberName = interner.resolve(calleeName)
        if (flatMapMemberName == "flatMap" || flatMapMemberName == "flatMapIndexed"),
           args.count == 1,
           isSequenceLikeType(receiverType, sema: sema, interner: interner)
        {
            let receiverElementType: TypeID = if case let .classType(classType) = sema.types.kind(
                of: sema.types.makeNonNullable(receiverType)
            ), let firstArg = classType.args.first {
                switch firstArg {
                case let .invariant(type), let .in(type), let .out(type):
                    type
                case .star:
                    sema.types.anyType
                }
            } else {
                sema.types.anyType
            }
            let lambdaParameterTypes: [TypeID] = flatMapMemberName == "flatMapIndexed"
                ? [sema.types.intType, receiverElementType]
                : [receiverElementType]
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: lambdaParameterTypes,
                returnType: sema.types.anyType,
                isSuspend: false,
                nullability: .nonNull
            )))
            if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
            }
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            let lambdaBodyType = inferredLambdaReturnType(
                argExpr: args[0].expr,
                ast: ast,
                sema: sema
            )
            let flattenedElementType = flatMapTransformElementType(
                lambdaArgExpr: args[0].expr,
                returnType: lambdaBodyType,
                ast: ast,
                sema: sema,
                interner: interner
            )
            if let sourceCallee = sourceBackedSequenceFlatMapOverload(
                named: flatMapMemberName,
                lambdaBodyType: lambdaBodyType,
                sema: sema,
                interner: interner
            ) {
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: sourceCallee,
                        substitutedTypeArguments: [receiverElementType, flattenedElementType],
                        parameterMapping: [0: 0]
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(sourceCallee))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            } else if let owner = driver.helpers.nominalSymbol(
                of: sema.types.makeNonNullable(receiverType),
                types: sema.types
            ),
                let ownerSymbol = sema.symbols.symbol(owner)
            {
                let memberFQName = ownerSymbol.fqName + [calleeName]
                if let fallbackCallee = sema.symbols.lookupAll(fqName: memberFQName).first(where: { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          sema.symbols.parentSymbol(for: candidate) == owner,
                          let signature = sema.symbols.functionSignature(for: candidate)
                    else {
                        return false
                    }
                    return signature.parameterTypes.count == 1
                }) {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: fallbackCallee,
                            substitutedTypeArguments: [],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(fallbackCallee))
                }
            }
            sema.bindings.markCollectionExpr(id)
            let resultType = makeSyntheticSequenceType(
                symbols: sema.symbols,
                types: sema.types,
                interner: interner,
                elementType: flattenedElementType
            )
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        // KUU-4063: non-Sequence receivers hit two overload holes:
        //  - a statically `Collection<T>`-typed receiver left `flatMap`'s
        //    callee unbound for every transform shape (the fast path only
        //    binds exact Iterable/List receivers), so the call lowered to a
        //    bare `_flatMap` symbol and failed at link time;
        //  - `flatMapIndexed` is excluded from the collection fast path for
        //    List receivers, and regular overload resolution commits to the
        //    `List.flatMapIndexed` specialization without retrying the
        //    `Iterable.flatMapIndexed*` variants when the transform returns
        //    a Sequence or a non-List Iterable (KSWIFTK-TYPE-0001).
        // Bind the bundled `Iterable.flatMap*` overload whose transform
        // return kind matches the lambda body here, mirroring the Sequence
        // receiver selection above. `flatMapIndexed` on Collection/Set/
        // Iterable-static receivers already resolves through regular
        // overload resolution, so only the List receiver shape is claimed.
        if (flatMapMemberName == "flatMap" || flatMapMemberName == "flatMapIndexed"),
           args.count == 1,
           !isSequenceLikeType(receiverType, sema: sema, interner: interner)
        {
            let classifier = receiverClassifier(sema: sema, interner: interner)
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
                let receiverElementType: TypeID = if case let .classType(classType) = sema.types.kind(
                    of: sema.types.makeNonNullable(receiverType)
                ), let firstArg = classType.args.first {
                    switch firstArg {
                    case let .invariant(type), let .in(type), let .out(type):
                        type
                    case .star:
                        sema.types.anyType
                    }
                } else {
                    sema.types.anyType
                }
                let lambdaParameterTypes: [TypeID] = flatMapMemberName == "flatMapIndexed"
                    ? [sema.types.intType, receiverElementType]
                    : [receiverElementType]
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: lambdaParameterTypes,
                    returnType: sema.types.anyType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let lambdaBodyType = inferredLambdaReturnType(
                    argExpr: args[0].expr,
                    ast: ast,
                    sema: sema
                )
                // A concrete `List` receiver keeps the `List.flatMap*`
                // specialization for List-returning transforms; other
                // receivers claim any flattenable transform since nothing
                // else binds their call.
                let transformIsFlattenable = flatMapTransformIsFlattenable(
                    lambdaArgExpr: args[0].expr,
                    returnType: lambdaBodyType,
                    ast: ast,
                    sema: sema,
                    interner: interner
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
                       sema: sema,
                       interner: interner
                   )
                {
                    let flattenedElementType = flatMapTransformElementType(
                        lambdaArgExpr: args[0].expr,
                        returnType: lambdaBodyType,
                        ast: ast,
                        sema: sema,
                        interner: interner
                    )
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: sourceCallee,
                            substitutedTypeArguments: [receiverElementType, flattenedElementType],
                            parameterMapping: [0: 0]
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(sourceCallee))
                    if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                        sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                    }
                    let resultType: TypeID = if let listSymbol = lookupStdlibSymbol(
                        "List",
                        symbols: sema.symbols,
                        interner: interner
                    ) {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSymbol,
                            args: [.invariant(flattenedElementType)],
                            nullability: .nonNull
                        )))
                    } else {
                        sema.types.anyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
                // The call stays on the regular resolution/fast-path route:
                // undo the speculative native-HOF lambda marking so the
                // lambda is materialized as a boxed callable, matching the
                // callee the later stages will bind.
                if let lambdaExpr = ast.arena.expr(args[0].expr), lambdaExpr.isLambdaOrCallableRef {
                    sema.bindings.unmarkCollectionHOFLambdaExpr(args[0].expr)
                }
            }
        }
        if let boundContinuationCall = tryContinuationSyntheticMemberCall(
            id,
            calleeName: calleeName,
            receiverType: receiverType,
            args: args,
            range: range,
            ctx: ctx,
            locals: &locals
        ) {
            return boundContinuationCall
        }

        if let result = tryInferKClassReceiverMemberCall(
            id, receiverType: receiverType, calleeName: calleeName, args: args,
            explicitTypeArgs: explicitTypeArgs, range: range, ctx: ctx, locals: &locals
        ) {
            return result
        }

        if args.isEmpty,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
           locals[receiverName] == nil,
           !receiverQualifierIsTypeAlias(receiverID: receiverID, ctx: ctx),
           let ownerSymbol = sema.bindings.identifierSymbol(for: receiverID),
           let owner = sema.symbols.symbol(ownerSymbol),
           owner.kind == .class || owner.kind == .interface || owner.kind == .enumClass,
           let staticMember = resolveClassNameMemberValue(
               ownerNominalSymbol: ownerSymbol,
               memberName: calleeName,
               sema: sema
           ),
           // An explicit `()` on a nested `object` is a function invocation,
           // not a value read — fall through so `invoke` can dispatch
           // (KUU-3662).
           !(ast.arena.isExplicitCall(id)
               && sema.symbols.symbol(staticMember.symbol)?.kind == .object)
        {
            if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
               !ctx.visibilityChecker.isAccessible(
                   memberSymbol,
                   fromFile: ctx.currentFileID,
                   enclosingClass: ctx.enclosingClassSymbol
               )
            {
                driver.helpers.emitVisibilityError(
                    for: memberSymbol,
                    name: interner.resolve(calleeName),
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
            sema.bindings.bindExprType(id, type: staticMember.type)
            return staticMember.type
        }
        return nil
    }

    /// Returns `nil` when the bundled source declaration is unavailable, letting the
    /// caller fall back to the synthetic runtime-backed member.
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

    /// Bundled `Iterable.flatMap*` overload whose transform return kind
    /// matches the lambda body. Only `kotlin.collections.Iterable` receivers
    /// qualify — concrete `List<T>`-receiver specializations keep their own
    /// dispatch path for List-returning transforms.
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

    /// True when the flatMap/flatMapIndexed transform result is a flattenable
    /// shape the bundled overloads iterate over: an Iterable, a Sequence, or
    /// a range/progression (whose nominal types opt out of the Iterable
    /// subtype check for owner-dispatch reasons).
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

    /// Element type the flatMap result flattens to. Range expressions expose
    /// their element through `nominalRangeElementType` or the range-expr
    /// bindings rather than a collection type argument.
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
