// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallScopeResultAndFileSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        // use, usePinned and useContents must intercept BEFORE eager arg
        // inference so the lambda argument is inferred with the correct
        // expected type (it vs. receiver this).
        // Skip interception when the receiver type defines a real member
        // with the same name (user-defined members take precedence).
        if request.args.count == 1 {
            let calleeStr = request.interner.resolve(request.calleeName)
            let scopeKind: ScopeFunctionKind? = switch calleeStr {
            case "use" where isCloseableReceiver(receiverType, sema: request.sema): .scopeUse
            case "usePinned": .scopeUsePinned
            case "useContents" where extractCValueCStructContentType(receiverType, sema: request.sema, interner: request.interner) != nil:
                .scopeUseContents
            default: nil
            }
            let hasUserDefinedMember = if scopeKind != nil {
                !driver.helpers.collectMemberFunctionCandidates(
                    named: request.calleeName,
                    receiverType: receiverType,
                    sema: request.sema,
                    interner: request.interner
                ).isEmpty
            } else {
                false
            }
            if let scopeKind, !hasUserDefinedMember {
                let nonNullReceiverType = request.safeCall
                    ? request.sema.types.makeNonNullable(receiverType)
                    : receiverType

                switch scopeKind {
                case .scopeUse:
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: request.expectedType ?? request.sema.types.nullableAnyType
                    )))
                    let lambdaType = driver.inferExpr(
                        request.args[0].expr, ctx: request.ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = request.sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        request.sema.bindings.exprTypes[request.args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = request.sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? request.sema.types.nullableAnyType
                    }
                    // Refine the call result type using the lambda body's concrete type,
                    // but ONLY when no expected type was provided (i.e. expected was
                    // nullableAnyType, the placeholder for "unconstrained").
                    // This lets downstream sema resolve member accesses on the result:
                    //   val lines = bufferedReader().use { reader -> reader.readLines() }
                    //   lines.size  ← resolves because lines is List<String>, not Any
                    // We skip Nothing-typed bodies (always-throw lambdas) to avoid
                    // disrupting the KIR try-finally exception propagation for use{}.
                    let refinedReturnType: TypeID = {
                        guard returnType == request.sema.types.nullableAnyType else { return returnType }
                        guard let lambdaExpr = request.ast.arena.expr(request.args[0].expr),
                              case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr,
                              let bodyType = request.sema.bindings.exprTypes[bodyExprID],
                              bodyType != request.sema.types.anyType
                        else { return returnType }
                        if case .nothing = request.sema.types.kind(of: bodyType) { return returnType }
                        return bodyType
                    }()
                    let finalType = request.safeCall ? request.sema.types.makeNullable(refinedReturnType) : refinedReturnType
                    // KUU-3915: bind the stdlib `use` overload this call
                    // resolves to. Lowering still expands `.use {}` as an
                    // intrinsic try/finally scope and never consults the
                    // binding, but post-validation needs the chosen (inline)
                    // callee to treat the block as an inline-parameter
                    // lambda — suspend calls and non-local returns inside
                    // `use {}` keep the caller's context.
                    if let useSymbol = resolveUseScopeCallee(
                        receiverType: nonNullReceiverType,
                        sema: request.sema,
                        interner: request.interner
                    ) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: useSymbol,
                            substitutedTypeArguments: [nonNullReceiverType, returnType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    request.sema.bindings.markScopeFunctionExpr(request.id, kind: scopeKind)
                    // markCollectionHOFLambdaExpr is required here to force the lambda through
                    // the capturing-lambda lowering path (needsClosureParam=true), which ensures
                    // exception propagation works correctly for use{} lambdas that may throw.
                    // Without this, a non-capturing lambda (e.g. `{ error("boom") }`) goes through
                    // lowerNonCapturingLambda (isInline:true) which breaks try/catch around use{}.
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case .scopeUsePinned:
                    // usePinned: like `use`, but the lambda receives Pinned<T> (the pinned
                    // handle) instead of the receiver itself, and lowering calls pin()/unpin()
                    // instead of close(). Requires the synthetic kotlinx.cinterop.Pinned class
                    // to already be registered (always true — see registerSyntheticCInteropStubs).
                    let pinnedFQName: [InternedString] = [
                        request.interner.intern("kotlinx"), request.interner.intern("cinterop"), request.interner.intern("Pinned"),
                    ]
                    guard let pinnedClassSymbol = request.sema.symbols.lookup(fqName: pinnedFQName),
                          let usePinnedSymbol = request.sema.symbols.lookup(fqName: [
                              request.interner.intern("kotlinx"), request.interner.intern("cinterop"), request.calleeName,
                          ])
                    else {
                        break
                    }
                    let pinnedOfReceiverType = request.sema.types.make(.classType(ClassType(
                        classSymbol: pinnedClassSymbol,
                        args: [.invariant(nonNullReceiverType)],
                        nullability: .nonNull
                    )))
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [pinnedOfReceiverType],
                        returnType: request.expectedType ?? request.sema.types.nullableAnyType
                    )))
                    let lambdaType = driver.inferExpr(
                        request.args[0].expr, ctx: request.ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = request.sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        request.sema.bindings.exprTypes[request.args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = request.sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? request.sema.types.nullableAnyType
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(returnType) : returnType
                    // Interception still needs the inline parameter contract for
                    // return-path validation and capturing-lambda KIR lowering.
                    request.sema.bindings.bindCall(request.id, binding: CallBinding(
                        chosenCallee: usePinnedSymbol,
                        substitutedTypeArguments: [nonNullReceiverType, returnType],
                        parameterMapping: [0: 0]
                    ))
                    request.sema.bindings.markScopeFunctionExpr(request.id, kind: scopeKind)
                    // Force the capturing-lambda lowering path so try/finally exception
                    // propagation around the block call works correctly (mirrors scopeUse).
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case .scopeUseContents:
                    guard let contentType = extractCValueCStructContentType(
                        nonNullReceiverType,
                        sema: request.sema,
                        interner: request.interner
                    ) else {
                        break
                    }
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        receiver: contentType,
                        params: [],
                        returnType: request.expectedType ?? request.sema.types.nullableAnyType
                    )))
                    let receiverCtx = request.ctx.with(implicitReceiverType: contentType)
                    let lambdaType = driver.inferExpr(
                        request.args[0].expr, ctx: receiverCtx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = request.sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        request.sema.bindings.exprTypes[request.args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = request.sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? request.sema.types.nullableAnyType
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(returnType) : returnType
                    request.sema.bindings.markScopeFunctionExpr(request.id, kind: scopeKind)
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case .scopeContext, .scopeMemScoped:
                    break // context/memScoped are handled in inferCallExpr (top-level functions)
                }
            }
        }

        // Result<T> members require special handling because the generic type
        // parameter T needs to be extracted from the receiver's Result<T> type
        // and used to construct the expected lambda parameter types.
        if request.args.count >= 1, request.args.count <= 2 {
            let calleeStr = request.interner.resolve(request.calleeName)
            let resultMemberNames = request.knownNames.resultMemberNames
            let explicitTypeArgumentsMatchResultMember: Bool = {
                guard !request.explicitTypeArgs.isEmpty else { return true }
                guard let resultMember = lookupResultMember(calleeStr, sema: request.sema, interner: request.interner),
                      let signature = request.sema.symbols.functionSignature(for: resultMember),
                      signature.classTypeParameterCount <= signature.typeParameterSymbols.count
                else {
                    return false
                }
                let memberTypeParameterCount = signature.typeParameterSymbols.count
                    - signature.classTypeParameterCount
                return request.explicitTypeArgs.count == memberTypeParameterCount
            }()
            if resultMemberNames.contains(request.calleeName),
               explicitTypeArgumentsMatchResultMember,
               let resultElementType = extractResultElementType(receiverType, sema: request.sema, interner: request.interner)
            {
                let throwableType = driver.helpers.throwableType(sema: request.sema, interner: request.interner) ?? request.sema.types.anyType
                let nonNullReceiverType = request.safeCall ? request.sema.types.makeNonNullable(receiverType) : receiverType

                switch calleeStr {
                case "onSuccess" where request.args.count == 1:
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: request.sema.types.unitType
                    )))
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    if let onSuccessSymbol = lookupResultMember("onSuccess", sema: request.sema, interner: request.interner) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: onSuccessSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case "onFailure" where request.args.count == 1:
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: request.sema.types.unitType
                    )))
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    if let onFailureSymbol = lookupResultMember("onFailure", sema: request.sema, interner: request.interner) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: onFailureSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case "getOrElse" where request.args.count == 1:
                    // Kotlin's getOrElse is `<R, T : R>`: the fallback may
                    // return any supertype of the Result element, so the
                    // lambda must not be pinned to T — `Result<T>.getOrElse
                    // { Other() }` is legal and yields R = lub(T, Other).
                    // A Result<Nothing> has no successful value to constrain
                    // the join at all.
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: request.expectedType ?? request.sema.types.nullableAnyType
                    )))
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    if let getOrElseSymbol = lookupResultMember("getOrElse", sema: request.sema, interner: request.interner) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: getOrElseSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let inferredFallbackType = inferredLambdaReturnType(argExpr: request.args[0].expr, ast: request.ast, sema: request.sema)
                    let returnType = request.sema.types.lub([resultElementType, inferredFallbackType])
                    let finalType = request.safeCall ? request.sema.types.makeNullable(returnType) : returnType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case "getOrDefault" where request.args.count == 1:
                    // Kotlin permits a fallback supertype of the Result element.
                    // Nothing cannot constrain the fallback of a failure-only Result.
                    let defaultExpectedType: TypeID? = if case .nothing = request.sema.types.kind(of: resultElementType) {
                        request.expectedType
                    } else {
                        resultElementType
                    }
                    let defaultType = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: defaultExpectedType)
                    let returnType = request.sema.types.lub([resultElementType, defaultType])
                    if let getOrDefaultSymbol = lookupResultMember("getOrDefault", sema: request.sema, interner: request.interner) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: getOrDefaultSymbol,
                            substitutedTypeArguments: [returnType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(returnType) : returnType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case "map" where request.args.count == 1:
                    let contextualResult = request.expectedType.flatMap {
                        extractResultElementType($0, sema: request.sema, interner: request.interner)
                    }
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: contextualResult ?? request.sema.types.nullableAnyType
                    )))
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    let lambdaType = driver.inferExpr(
                        request.args[0].expr, ctx: request.ctx, locals: &locals,
                        expectedType: lambdaExpectedType, inferLambdaResultType: contextualResult == nil
                    )
                    let mappedType: TypeID = if case let .functionType(fnType) = request.sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        request.sema.types.anyType
                    }
                    if let mapSymbol = lookupResultMember("map", sema: request.sema, interner: request.interner) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: mapSymbol,
                            substitutedTypeArguments: [resultElementType, mappedType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let mappedResultType = makeResultType(elementType: mappedType, sema: request.sema, interner: request.interner) ?? request.sema.types.anyType
                    let finalType = request.safeCall ? request.sema.types.makeNullable(mappedResultType) : mappedResultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case "recover" where request.args.count == 1:
                    let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: request.expectedType.flatMap {
                            extractResultElementType($0, sema: request.sema, interner: request.interner)
                        } ?? request.sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    let recoveredType: TypeID = if case let .functionType(fnType) = request.sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        request.sema.types.anyType
                    }
                    if let recoverSymbol = lookupResultMember("recover", sema: request.sema, interner: request.interner) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: recoverSymbol,
                            substitutedTypeArguments: [resultElementType, recoveredType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let recoverResultType = makeResultType(
                        elementType: recoveredType,
                        sema: request.sema,
                        interner: request.interner
                    ) ?? request.sema.types.anyType
                    let finalType = request.safeCall ? request.sema.types.makeNullable(recoverResultType) : recoverResultType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                case "fold" where request.args.count == 2:
                    // `R` is shared by both transforms, so it must stay open
                    // until both lambda bodies have been analysed. Seeding the
                    // failure transform's expected return with the success
                    // transform's inferred return type pins `R` to the first
                    // lambda's result and rejects valid Kotlin —
                    // `fold({ it + 1 }, { it.message })` infers `R` as the join
                    // of `Int` and `String?` on the JVM.
                    let callbackReturnHint = request.expectedType ?? request.sema.types.nullableAnyType
                    let onSuccessExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: callbackReturnHint
                    )))
                    let onSuccessType = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: onSuccessExpectedType)
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                    let onSuccessReturnType: TypeID = if case let .functionType(fnType) = request.sema.types.kind(of: onSuccessType) {
                        fnType.returnType
                    } else {
                        request.sema.types.anyType
                    }
                    let onFailureExpectedType = request.sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: callbackReturnHint
                    )))
                    _ = driver.inferExpr(request.args[1].expr, ctx: request.ctx, locals: &locals, expectedType: onFailureExpectedType)
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[1].expr)
                    let onFailureReturnType = inferredLambdaReturnType(argExpr: request.args[1].expr, ast: request.ast, sema: request.sema)
                    let foldReturnType = request.expectedType
                        ?? request.sema.types.lub([onSuccessReturnType, onFailureReturnType])
                    if let foldSymbol = lookupResultMember("fold", sema: request.sema, interner: request.interner) {
                        request.sema.bindings.bindCall(request.id, binding: CallBinding(
                            chosenCallee: foldSymbol,
                            substitutedTypeArguments: [resultElementType, foldReturnType],
                            parameterMapping: [0: 0, 1: 1]
                        ))
                    }
                    let finalType = request.safeCall ? request.sema.types.makeNullable(foldReturnType) : foldReturnType
                    request.sema.bindings.bindExprType(request.id, type: finalType)
                    return finalType

                default:
                    break
                }
            }
        }



        do {
            let calleeStr = request.interner.resolve(request.calleeName)
            if calleeStr == "forEachBlock",
               isFileType(receiverType, sema: request.sema, interner: request.interner),
               request.args.count == 1 || request.args.count == 2
            {
                let listSymbol = request.sema.symbols.lookupByShortName(request.interner.intern("List")).first
                let listOfIntType: TypeID = if let listSym = listSymbol {
                    request.sema.types.make(.classType(ClassType(
                        classSymbol: listSym,
                        args: [.out(request.sema.types.intType)],
                        nullability: .nonNull
                    )))
                } else { request.sema.types.anyType }
                let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                    params: [listOfIntType, request.sema.types.intType],
                    returnType: request.sema.types.unitType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let lambdaArgIndex = request.args.count == 2 ? 1 : 0
                if request.args.count == 2 {
                    _ = driver.inferExpr(request.args[0].expr, ctx: request.ctx, locals: &locals, expectedType: request.sema.types.intType)
                }
                if let lambdaExpr = request.ast.arena.expr(request.args[lambdaArgIndex].expr), case .lambdaLiteral = lambdaExpr {
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[lambdaArgIndex].expr)
                }
                _ = driver.inferExpr(request.args[lambdaArgIndex].expr, ctx: request.ctx, locals: &locals, expectedType: lambdaExpectedType)
                let finalType = request.safeCall ? request.sema.types.makeNullable(request.sema.types.unitType) : request.sema.types.unitType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        // File.forEachLine/useLines require the lambda to use the collection HOF
        // closure ABI (closureRaw prepended), and the lambda's implicit `it` must
        // be correctly resolved.
        // STDLIB-IO-FN-040: also handles `BufferedReader.useLines { lines -> T }`
        // because the synthetic stub registers `useLines` on `java.io.BufferedReader`
        // with the same `(List<String>) -> Any` signature.
        // STDLIB-IO-FN-017: also handles `BufferedReader.forEachLine { line -> Unit }`
        // via the same HOF closure ABI — action receives `String`, returns `Unit`.
        if request.args.count == 1 {
            let calleeStr = request.interner.resolve(request.calleeName)
            let isFileReceiver = isFileType(receiverType, sema: request.sema, interner: request.interner)
            let isBufferedReader = isBufferedReaderType(receiverType, sema: request.sema, interner: request.interner)
            let isReaderUseLines = !isFileReceiver
                && calleeStr == "useLines"
                && isBufferedReader
            let isReaderForEachLine = !isFileReceiver
                && calleeStr == "forEachLine"
                && isBufferedReader
            if (isFileReceiver && (calleeStr == "forEachLine" || calleeStr == "useLines"))
                || isReaderUseLines
                || isReaderForEachLine
            {
                if let lambdaExpr = request.ast.arena.expr(request.args[0].expr), case .lambdaLiteral = lambdaExpr {
                    request.sema.bindings.markCollectionHOFLambdaExpr(request.args[0].expr)
                }
                let lambdaParamType: TypeID
                let lambdaReturnType: TypeID
                let callReturnType: TypeID
                if calleeStr == "forEachLine" {
                    lambdaParamType = request.sema.types.stringType
                    lambdaReturnType = request.sema.types.unitType
                    callReturnType = request.sema.types.unitType
                } else {
                    let listSymbol = request.sema.symbols.lookupByShortName(request.interner.intern("List")).first
                    lambdaParamType = if let listSym = listSymbol {
                        request.sema.types.make(.classType(ClassType(
                            classSymbol: listSym,
                            args: [.out(request.sema.types.stringType)],
                            nullability: .nonNull
                        )))
                    } else {
                        request.sema.types.anyType
                    }
                    // Keep an unconstrained result distinct from a concrete Any
                    // result.  The lambda body must be allowed to infer T so the
                    // result can be used in a following member access, e.g.
                    // `file.useLines { it.toList() }.size`.
                    lambdaReturnType = request.expectedType ?? request.sema.types.nullableAnyType
                    callReturnType = request.expectedType ?? request.sema.types.nullableAnyType
                }
                let lambdaExpectedType = request.sema.types.make(.functionType(FunctionType(
                    params: [lambdaParamType],
                    returnType: lambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let inferredLambdaType = driver.inferExpr(
                    request.args[0].expr, ctx: request.ctx, locals: &locals,
                    expectedType: lambdaExpectedType
                )
                let finalReturnType: TypeID
                if calleeStr == "useLines" {
                    let inferredReturnType: TypeID = if case let .functionType(fnType) = request.sema.types.kind(of: inferredLambdaType) {
                        fnType.returnType
                    } else {
                        callReturnType
                    }
                    // `inferLambdaLiteralExpr` retains the placeholder in the
                    // function type when T is unconstrained.  Refine the call
                    // result from the lambda body in that case, just as the
                    // residual `use` path does above.
                    if request.expectedType == nil,
                       inferredReturnType == request.sema.types.nullableAnyType,
                       let lambdaExpr = request.ast.arena.expr(request.args[0].expr),
                       case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr,
                       let bodyType = request.sema.bindings.exprType(for: bodyExprID),
                       bodyType != request.sema.types.anyType
                    {
                        if case .nothing = request.sema.types.kind(of: bodyType) {
                            finalReturnType = inferredReturnType
                        } else {
                            finalReturnType = bodyType
                        }
                    } else {
                        finalReturnType = inferredReturnType
                    }
                } else {
                    finalReturnType = callReturnType
                }

                // File.forEachLine/useLines are bundled Kotlin source functions.
                // This special path owns lambda inference, so it must also bind the
                // call to the source symbol; otherwise lowering leaves a raw
                // `forEachLine`/`useLines` linker name instead of inlining the body.
                let fileIOFunction = request.sema.symbols.lookupAll(fqName: [
                    request.interner.intern("kotlin"),
                    request.interner.intern("io"),
                    request.calleeName,
                ]).first { candidate in
                    guard let signature = request.sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.receiverType == request.sema.types.makeNonNullable(receiverType)
                        && signature.parameterTypes.count == 1
                }
                if let fileIOFunction {
                    let substitutions = calleeStr == "useLines" ? [finalReturnType] : []
                    request.sema.bindings.bindCall(request.id, binding: CallBinding(
                        chosenCallee: fileIOFunction,
                        substitutedTypeArguments: substitutions,
                        parameterMapping: [0: 0]
                    ))
                    request.sema.bindings.bindCallableTarget(request.id, target: .symbol(fileIOFunction))
                }
                let finalType = request.safeCall ? request.sema.types.makeNullable(finalReturnType) : finalReturnType
                request.sema.bindings.bindExprType(request.id, type: finalType)
                return finalType
            }
        }

        return nil
    }
}
