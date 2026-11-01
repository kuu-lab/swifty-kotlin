// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func tryInferMemberCallScopeResultAndFileSpecials(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let calleeName = request.calleeName
        let args = request.args
        let ctx = request.ctx
        let expectedType = request.expectedType
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        // use, usePinned and useContents must intercept BEFORE eager arg
        // inference so the lambda argument is inferred with the correct
        // expected type (it vs. receiver this).
        // Skip interception when the receiver type defines a real member
        // with the same name (user-defined members take precedence).
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let scopeKind: ScopeFunctionKind? = switch calleeStr {
            case "use" where isCloseableReceiver(receiverType, sema: sema): .scopeUse
            case "usePinned": .scopeUsePinned
            case "useContents" where extractCValueCStructContentType(receiverType, sema: sema, interner: interner) != nil:
                .scopeUseContents
            default: nil
            }
            let hasUserDefinedMember = if scopeKind != nil {
                !driver.helpers.collectMemberFunctionCandidates(
                    named: calleeName,
                    receiverType: receiverType,
                    sema: sema,
                    interner: interner
                ).isEmpty
            } else {
                false
            }
            if let scopeKind, !hasUserDefinedMember {
                let nonNullReceiverType = safeCall
                    ? sema.types.makeNonNullable(receiverType)
                    : receiverType

                switch scopeKind {
                case .scopeUse:
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [nonNullReceiverType],
                        returnType: expectedType ?? sema.types.nullableAnyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.nullableAnyType
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
                        guard returnType == sema.types.nullableAnyType else { return returnType }
                        guard let lambdaExpr = ast.arena.expr(args[0].expr),
                              case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr,
                              let bodyType = sema.bindings.exprTypes[bodyExprID],
                              bodyType != sema.types.anyType
                        else { return returnType }
                        if case .nothing = sema.types.kind(of: bodyType) { return returnType }
                        return bodyType
                    }()
                    let finalType = safeCall ? sema.types.makeNullable(refinedReturnType) : refinedReturnType
                    // KUU-3915: bind the stdlib `use` overload this call
                    // resolves to. Lowering still expands `.use {}` as an
                    // intrinsic try/finally scope and never consults the
                    // binding, but post-validation needs the chosen (inline)
                    // callee to treat the block as an inline-parameter
                    // lambda — suspend calls and non-local returns inside
                    // `use {}` keep the caller's context.
                    if let useSymbol = resolveUseScopeCallee(
                        receiverType: nonNullReceiverType,
                        sema: sema,
                        interner: interner
                    ) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: useSymbol,
                            substitutedTypeArguments: [nonNullReceiverType, returnType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    // markCollectionHOFLambdaExpr is required here to force the lambda through
                    // the capturing-lambda lowering path (needsClosureParam=true), which ensures
                    // exception propagation works correctly for use{} lambdas that may throw.
                    // Without this, a non-capturing lambda (e.g. `{ error("boom") }`) goes through
                    // lowerNonCapturingLambda (isInline:true) which breaks try/catch around use{}.
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeUsePinned:
                    // usePinned: like `use`, but the lambda receives Pinned<T> (the pinned
                    // handle) instead of the receiver itself, and lowering calls pin()/unpin()
                    // instead of close(). Requires the synthetic kotlinx.cinterop.Pinned class
                    // to already be registered (always true — see registerSyntheticCInteropStubs).
                    let pinnedFQName: [InternedString] = [
                        interner.intern("kotlinx"), interner.intern("cinterop"), interner.intern("Pinned"),
                    ]
                    guard let pinnedClassSymbol = sema.symbols.lookup(fqName: pinnedFQName),
                          let usePinnedSymbol = sema.symbols.lookup(fqName: [
                              interner.intern("kotlinx"), interner.intern("cinterop"), calleeName,
                          ])
                    else {
                        break
                    }
                    let pinnedOfReceiverType = sema.types.make(.classType(ClassType(
                        classSymbol: pinnedClassSymbol,
                        args: [.invariant(nonNullReceiverType)],
                        nullability: .nonNull
                    )))
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [pinnedOfReceiverType],
                        returnType: expectedType ?? sema.types.nullableAnyType
                    )))
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: ctx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.nullableAnyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    // Interception still needs the inline parameter contract for
                    // return-path validation and capturing-lambda KIR lowering.
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: usePinnedSymbol,
                        substitutedTypeArguments: [nonNullReceiverType, returnType],
                        parameterMapping: [0: 0]
                    ))
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    // Force the capturing-lambda lowering path so try/finally exception
                    // propagation around the block call works correctly (mirrors scopeUse).
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeUseContents:
                    guard let contentType = extractCValueCStructContentType(
                        nonNullReceiverType,
                        sema: sema,
                        interner: interner
                    ) else {
                        break
                    }
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        receiver: contentType,
                        params: [],
                        returnType: expectedType ?? sema.types.nullableAnyType
                    )))
                    let receiverCtx = ctx.with(implicitReceiverType: contentType)
                    let lambdaType = driver.inferExpr(
                        args[0].expr, ctx: receiverCtx, locals: &locals,
                        expectedType: lambdaExpectedType
                    )
                    let returnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.bindings.exprTypes[args[0].expr].flatMap { typeID in
                            if case let .functionType(fnType) = sema.types.kind(of: typeID) {
                                return fnType.returnType
                            }
                            return nil
                        } ?? sema.types.nullableAnyType
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.markScopeFunctionExpr(id, kind: scopeKind)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case .scopeContext, .scopeMemScoped:
                    break // context/memScoped are handled in inferCallExpr (top-level functions)
                }
            }
        }

        // Result<T> members require special handling because the generic type
        // parameter T needs to be extracted from the receiver's Result<T> type
        // and used to construct the expected lambda parameter types.
        if args.count >= 1, args.count <= 2 {
            let calleeStr = interner.resolve(calleeName)
            let resultMemberNames: Set = [
                "onSuccess", "onFailure", "getOrElse", "getOrDefault", "map", "fold", "recover",
            ]
            let explicitTypeArgumentsMatchResultMember: Bool = {
                guard !request.explicitTypeArgs.isEmpty else { return true }
                guard let resultMember = lookupResultMember(calleeStr, sema: sema, interner: interner),
                      let signature = sema.symbols.functionSignature(for: resultMember),
                      signature.classTypeParameterCount <= signature.typeParameterSymbols.count
                else {
                    return false
                }
                let memberTypeParameterCount = signature.typeParameterSymbols.count
                    - signature.classTypeParameterCount
                return request.explicitTypeArgs.count == memberTypeParameterCount
            }()
            if resultMemberNames.contains(calleeStr),
               explicitTypeArgumentsMatchResultMember,
               let resultElementType = extractResultElementType(receiverType, sema: sema, interner: interner)
            {
                let throwableType = driver.helpers.throwableType(sema: sema, interner: interner) ?? sema.types.anyType
                let nonNullReceiverType = safeCall ? sema.types.makeNonNullable(receiverType) : receiverType

                switch calleeStr {
                case "onSuccess" where args.count == 1:
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let onSuccessSymbol = lookupResultMember("onSuccess", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: onSuccessSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "onFailure" where args.count == 1:
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: sema.types.unitType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let onFailureSymbol = lookupResultMember("onFailure", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: onFailureSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(nonNullReceiverType) : nonNullReceiverType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "getOrElse" where args.count == 1:
                    // A Result<Nothing> has no successful value to constrain T.
                    // Infer the fallback naturally in that case, matching the
                    // bottom-type behavior of Kotlin's generic getOrElse API.
                    let isBottomResult = if case .nothing(.nonNull) = sema.types.kind(of: resultElementType) {
                        true
                    } else {
                        false
                    }
                    let fallbackExpectedType = isBottomResult
                        ? (expectedType ?? sema.types.nullableAnyType)
                        : resultElementType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: fallbackExpectedType
                    )))
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    if let getOrElseSymbol = lookupResultMember("getOrElse", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: getOrElseSymbol,
                            substitutedTypeArguments: [resultElementType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let inferredFallbackType = isBottomResult
                        ? inferredLambdaReturnType(argExpr: args[0].expr, ast: ast, sema: sema)
                        : resultElementType
                    let finalType = safeCall ? sema.types.makeNullable(inferredFallbackType) : inferredFallbackType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "getOrDefault" where args.count == 1:
                    // Kotlin permits a fallback supertype of the Result element.
                    // Nothing cannot constrain the fallback of a failure-only Result.
                    let defaultExpectedType: TypeID? = if case .nothing = sema.types.kind(of: resultElementType) {
                        expectedType
                    } else {
                        resultElementType
                    }
                    let defaultType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: defaultExpectedType)
                    let returnType = sema.types.lub([resultElementType, defaultType])
                    if let getOrDefaultSymbol = lookupResultMember("getOrDefault", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: getOrDefaultSymbol,
                            substitutedTypeArguments: [returnType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "map" where args.count == 1:
                    // Note: only intercept for Result receiver, not for collections
                    // expectedType is Result<R>, so extract R for the lambda return type
                    let lambdaReturnType = expectedType.flatMap { extractResultElementType($0, sema: sema, interner: interner) } ?? sema.types.anyType
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: lambdaReturnType
                    )))
                    let lambdaType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    let mappedType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    if let mapSymbol = lookupResultMember("map", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: mapSymbol,
                            substitutedTypeArguments: [resultElementType, mappedType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let mappedResultType = makeResultType(elementType: mappedType, sema: sema, interner: interner) ?? sema.types.anyType
                    let finalType = safeCall ? sema.types.makeNullable(mappedResultType) : mappedResultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "recover" where args.count == 1:
                    let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: expectedType.flatMap {
                            extractResultElementType($0, sema: sema, interner: interner)
                        } ?? sema.types.anyType
                    )))
                    let lambdaType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    let recoveredType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: lambdaType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    if let recoverSymbol = lookupResultMember("recover", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: recoverSymbol,
                            substitutedTypeArguments: [resultElementType, recoveredType],
                            parameterMapping: [0: 0]
                        ))
                    }
                    let recoverResultType = makeResultType(
                        elementType: recoveredType,
                        sema: sema,
                        interner: interner
                    ) ?? sema.types.anyType
                    let finalType = safeCall ? sema.types.makeNullable(recoverResultType) : recoverResultType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                case "fold" where args.count == 2:
                    let onSuccessExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [resultElementType],
                        returnType: expectedType ?? sema.types.anyType
                    )))
                    let onSuccessType = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: onSuccessExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                    let foldReturnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: onSuccessType) {
                        fnType.returnType
                    } else {
                        sema.types.anyType
                    }
                    let onFailureExpectedType = sema.types.make(.functionType(FunctionType(
                        params: [throwableType],
                        returnType: foldReturnType
                    )))
                    _ = driver.inferExpr(args[1].expr, ctx: ctx, locals: &locals, expectedType: onFailureExpectedType)
                    sema.bindings.markCollectionHOFLambdaExpr(args[1].expr)
                    if let foldSymbol = lookupResultMember("fold", sema: sema, interner: interner) {
                        sema.bindings.bindCall(id, binding: CallBinding(
                            chosenCallee: foldSymbol,
                            substitutedTypeArguments: [resultElementType, foldReturnType],
                            parameterMapping: [0: 0, 1: 1]
                        ))
                    }
                    let finalType = safeCall ? sema.types.makeNullable(foldReturnType) : foldReturnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType

                default:
                    break
                }
            }
        }



        do {
            let calleeStr = interner.resolve(calleeName)
            if calleeStr == "forEachBlock",
               isFileType(receiverType, sema: sema, interner: interner),
               args.count == 1 || args.count == 2
            {
                let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                let listOfIntType: TypeID = if let listSym = listSymbol {
                    sema.types.make(.classType(ClassType(
                        classSymbol: listSym,
                        args: [.out(sema.types.intType)],
                        nullability: .nonNull
                    )))
                } else { sema.types.anyType }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [listOfIntType, sema.types.intType],
                    returnType: sema.types.unitType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let lambdaArgIndex = args.count == 2 ? 1 : 0
                if args.count == 2 {
                    _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                }
                if let lambdaExpr = ast.arena.expr(args[lambdaArgIndex].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[lambdaArgIndex].expr)
                }
                _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
                let finalType = safeCall ? sema.types.makeNullable(sema.types.unitType) : sema.types.unitType
                sema.bindings.bindExprType(id, type: finalType)
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
        if args.count == 1 {
            let calleeStr = interner.resolve(calleeName)
            let isFileReceiver = isFileType(receiverType, sema: sema, interner: interner)
            let isBufferedReader = isBufferedReaderType(receiverType, sema: sema, interner: interner)
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
                if let lambdaExpr = ast.arena.expr(args[0].expr), case .lambdaLiteral = lambdaExpr {
                    sema.bindings.markCollectionHOFLambdaExpr(args[0].expr)
                }
                let lambdaParamType: TypeID
                let lambdaReturnType: TypeID
                let callReturnType: TypeID
                if calleeStr == "forEachLine" {
                    lambdaParamType = sema.types.stringType
                    lambdaReturnType = sema.types.unitType
                    callReturnType = sema.types.unitType
                } else {
                    let listSymbol = sema.symbols.lookupByShortName(interner.intern("List")).first
                    lambdaParamType = if let listSym = listSymbol {
                        sema.types.make(.classType(ClassType(
                            classSymbol: listSym,
                            args: [.out(sema.types.stringType)],
                            nullability: .nonNull
                        )))
                    } else {
                        sema.types.anyType
                    }
                    // Keep an unconstrained result distinct from a concrete Any
                    // result.  The lambda body must be allowed to infer T so the
                    // result can be used in a following member access, e.g.
                    // `file.useLines { it.toList() }.size`.
                    lambdaReturnType = expectedType ?? sema.types.nullableAnyType
                    callReturnType = expectedType ?? sema.types.nullableAnyType
                }
                let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                    params: [lambdaParamType],
                    returnType: lambdaReturnType,
                    isSuspend: false,
                    nullability: .nonNull
                )))
                let inferredLambdaType = driver.inferExpr(
                    args[0].expr, ctx: ctx, locals: &locals,
                    expectedType: lambdaExpectedType
                )
                let finalReturnType: TypeID
                if calleeStr == "useLines" {
                    let inferredReturnType: TypeID = if case let .functionType(fnType) = sema.types.kind(of: inferredLambdaType) {
                        fnType.returnType
                    } else {
                        callReturnType
                    }
                    // `inferLambdaLiteralExpr` retains the placeholder in the
                    // function type when T is unconstrained.  Refine the call
                    // result from the lambda body in that case, just as the
                    // residual `use` path does above.
                    if expectedType == nil,
                       inferredReturnType == sema.types.nullableAnyType,
                       let lambdaExpr = ast.arena.expr(args[0].expr),
                       case let .lambdaLiteral(_, bodyExprID, _, _) = lambdaExpr,
                       let bodyType = sema.bindings.exprType(for: bodyExprID),
                       bodyType != sema.types.anyType
                    {
                        if case .nothing = sema.types.kind(of: bodyType) {
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
                let fileIOFunction = sema.symbols.lookupAll(fqName: [
                    interner.intern("kotlin"),
                    interner.intern("io"),
                    calleeName,
                ]).first { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate) else {
                        return false
                    }
                    return signature.receiverType == sema.types.makeNonNullable(receiverType)
                        && signature.parameterTypes.count == 1
                }
                if let fileIOFunction {
                    let substitutions = calleeStr == "useLines" ? [finalReturnType] : []
                    sema.bindings.bindCall(id, binding: CallBinding(
                        chosenCallee: fileIOFunction,
                        substitutedTypeArguments: substitutions,
                        parameterMapping: [0: 0]
                    ))
                    sema.bindings.bindCallableTarget(id, target: .symbol(fileIOFunction))
                }
                let finalType = safeCall ? sema.types.makeNullable(finalReturnType) : finalReturnType
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        return nil
    }
}
