
extension CallTypeChecker {
    struct PreparedCallArguments {
        let argTypes: [TypeID]
        let lambdaLiteralIndices: Set<Int>
        let inputOnlyLambdaIndices: Set<Int>
        let blockedLambdaRefinement: Bool
        /// True when a bare (no declared parameter list) lambda argument relies on an
        /// implicit single parameter (`it`) whose type can't be fixed before overload
        /// resolution, because the remaining candidates each expect exactly one
        /// parameter but disagree on its type (DEBT-SEMA-004). Unlike
        /// `blockedLambdaRefinement`, which only forces an ambiguity diagnostic when a
        /// candidate opts in via `@OverloadResolutionByLambdaReturnType`, this case is
        /// unresolvable regardless of that annotation: there is no locally-known type
        /// to check the lambda body against.
        let hasUnresolvableImplicitLambdaParameter: Bool
    }

    func prepareCallArguments(
        args: [CallArgument],
        candidates: [SymbolID],
        preInferredNonLambdaArgTypes: [Int: TypeID] = [:],
        expectedTypeOverrides: [Int: TypeID] = [:],
        contextualCallResultType: TypeID? = nil,
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        lambdaContextOverrides: [Int: TypeInferenceContext] = [:],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> PreparedCallArguments {
        let ast = ctx.ast
        let sema = ctx.sema

        var inferredNonLambdaArgTypes = preInferredNonLambdaArgTypes
        var lambdaLiteralIndices: Set<Int> = []
        var inputOnlyLambdaIndices: Set<Int> = []
        var blockedLambdaRefinement = false
        var hasUnresolvableImplicitLambdaParameter = false
        var contextualArgExpectedTypes = [TypeID?](repeating: nil, count: args.count)

        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral:
                lambdaLiteralIndices.insert(index)
            case .callableRef:
                break
            case .intLiteral:
                // Always re-infer an unsuffixed int literal against the surviving
                // candidates' parameter type, even if a previous pass already gave
                // it a default Int. This lets member calls like
                // `shortArray.binarySearch(20)` narrow to Short/Byte.
                let literalExpectedType = uniformNumericLiteralParameterType(
                    at: index,
                    argumentLabel: argument.label,
                    candidates: candidates,
                    sema: sema
                )
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals, expectedType: literalExpectedType
                )
            case .uintLiteral:
                // Contextualize suffixed unsigned literals too. Kotlin narrows
                // constants such as 1u to UByte/UShort parameters when the value
                // fits, which is needed by source-backed unsigned extensions.
                let literalExpectedType = uniformUnsignedLiteralParameterType(
                    at: index,
                    argumentLabel: argument.label,
                    candidates: candidates,
                    sema: sema
                )
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals, expectedType: literalExpectedType
                )
            case .unaryExpr(let op, let operandID, _):
                guard (op == .unaryPlus || op == .unaryMinus),
                      case .intLiteral = ast.arena.expr(operandID)
                else {
                    if inferredNonLambdaArgTypes[index] == nil {
                        inferredNonLambdaArgTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
                    }
                    continue
                }
                // Constant-folded unary +/- over an int literal should see the
                // candidates' parameter type, just like a bare int literal, so
                // `byteArrayOf(1, -1)` and `shortArrayOf(1, -1)` resolve.
                let literalExpectedType = uniformNumericLiteralParameterType(
                    at: index,
                    argumentLabel: argument.label,
                    candidates: candidates,
                    sema: sema
                )
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals, expectedType: literalExpectedType
                )
            default:
                if inferredNonLambdaArgTypes[index] != nil {
                    continue
                }
                inferredNonLambdaArgTypes[index] = driver.inferExpr(
                    argument.expr, ctx: ctx, locals: &locals,
                    expectedType: expectedTypeOverrides[index]
                )
            }
        }

        // Class-name values must denote their companions before they constrain
        // receiver lambdas, e.g. the block in `with(Duration) { ... }`.
        for (index, argument) in args.enumerated() {
            if let type = inferredNonLambdaArgTypes[index],
               let companionType = driver.helpers.retypeClassNameAsCompanionValue(
                   argument.expr, currentType: type, ast: ast, sema: sema
               )
            {
                inferredNonLambdaArgTypes[index] = companionType
            }
        }

        for (index, argument) in args.enumerated() {
            if let type = inferredNonLambdaArgTypes[index] {
                inferredNonLambdaArgTypes[index] = sourceLevelRangeArgumentType(
                    argument.expr, inferredType: type, ctx: ctx
                )
            }
        }

        if lambdaLiteralIndices.count > 1 {
            blockedLambdaRefinement = true
        }

        // Each argument's expected type is computed and applied before moving to
        // the next one, so an already-inferred lambda constrains the arguments
        // that follow it: in `fold({ k, e -> ... }, { k, acc, e -> ... })` the
        // accumulator type is only pinned down by the first lambda's return type.
        var argTypes = [TypeID](repeating: sema.types.errorType, count: args.count)
        for (index, argument) in args.enumerated() {
            defer { ctx.dataFlow.localStability.inPlaceLambdaScopes.remove(argument.expr) }
            if let override = expectedTypeOverrides[index] {
                contextualArgExpectedTypes[index] = override
            } else if let argumentExpr = ast.arena.expr(argument.expr) {
                let narrowedCandidates = narrowedCallCandidates(
                    candidates: candidates,
                    args: args,
                    inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                    receiverType: receiverType,
                    ctx: ctx
                )
                let expectedTypeCandidates = narrowedCandidates.isEmpty ? candidates : narrowedCandidates

                switch argumentExpr {
                case .intLiteral:
                    contextualArgExpectedTypes[index] = uniformNumericLiteralParameterType(
                        at: index,
                        argumentLabel: argument.label,
                        candidates: expectedTypeCandidates,
                        sema: sema
                    )
                case .uintLiteral:
                    contextualArgExpectedTypes[index] = uniformUnsignedLiteralParameterType(
                        at: index,
                        argumentLabel: argument.label,
                        candidates: expectedTypeCandidates,
                        sema: sema
                    )
                case .unaryExpr(let op, let operandID, _):
                    if (op == .unaryPlus || op == .unaryMinus),
                       case .intLiteral = ast.arena.expr(operandID)
                    {
                        contextualArgExpectedTypes[index] = uniformNumericLiteralParameterType(
                            at: index,
                            argumentLabel: argument.label,
                            candidates: expectedTypeCandidates,
                            sema: sema
                        )
                    }
                case .callableRef:
                    contextualArgExpectedTypes[index] = callableReferenceExpectedType(
                        at: index,
                        argumentLabel: argument.label,
                        candidates: expectedTypeCandidates,
                        explicitTypeArgs: explicitTypeArgs,
                        sema: sema
                    )
                case let .lambdaLiteral(lambdaParams, _, _, _):
                    // Prove non-escaping invocation before checking the lambda body.
                    if !expectedTypeCandidates.isEmpty, expectedTypeCandidates.allSatisfy({ candidate in
                        guard let signature = sema.symbols.functionSignature(for: candidate),
                              argument.label != nil || signature.parameterTypes.count == args.count,
                              let parameterIndex = parameterIndexForCallArgument(
                                  at: index, label: argument.label, in: signature, sema: sema
                              )
                        else { return false }
                        return ctx.dataFlow.localStability.isInPlaceParameter(
                            parameterIndex, function: candidate, sema: sema
                        )
                    }) {
                        ctx.dataFlow.localStability.inPlaceLambdaScopes.insert(argument.expr)
                    }
                    let expectation = lambdaLiteralExpectedType(
                        at: index,
                        argumentCount: args.count,
                        argumentLabel: argument.label,
                        candidates: expectedTypeCandidates,
                        explicitTypeArgs: explicitTypeArgs,
                        receiverType: receiverType,
                        inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                        resolver: ctx.resolver,
                        sema: sema
                    )
                    // For a generic scope function such as `T.let(block: (T) -> R): R`,
                    // the expected call result fixes R before the lambda body is
                    // inferred. Keep the receiver-derived T in the expected lambda
                    // while replacing only its matching return type parameter.
                    let contextualLambdaType: TypeID? = {
                        // Only a definitely non-null expected result can fix R: for `R?` returns
                        // and safe calls (`x?.let {}` expected `Int?`) the expectation says
                        // nothing certain about the lambda's own result type.
                        guard let contextualCallResultType,
                              sema.types.makeNonNullable(contextualCallResultType) == contextualCallResultType,
                              candidates.count == 1,
                              let signature = sema.symbols.functionSignature(for: candidates[0]),
                              sema.types.makeNonNullable(signature.returnType) == signature.returnType,
                              case let .typeParam(resultParam) = sema.types.kind(of: signature.returnType),
                              let expectedLambdaType = expectation.type,
                              case let .functionType(fn) = sema.types.kind(of: expectedLambdaType),
                              case let .typeParam(lambdaResultParam) = sema.types.kind(of: fn.returnType),
                              lambdaResultParam.symbol == resultParam.symbol,
                              // `reduce<S, T : S>` also feeds S back into the lambda
                              // parameters; fixing it early conflicts with T's bound.
                              !fn.params.contains(where: { sema.types.typeContainsTypeParam($0, symbol: resultParam.symbol) }),
                              !(fn.receiver.map { sema.types.typeContainsTypeParam($0, symbol: resultParam.symbol) } ?? false)
                        else { return expectation.type }
                        return sema.types.make(.functionType(FunctionType(
                            contextReceivers: fn.contextReceivers,
                            receiver: fn.receiver,
                            params: fn.params,
                            returnType: lambdaResultParam.nullability == .nullable
                                ? sema.types.makeNullable(contextualCallResultType)
                                : contextualCallResultType,
                            isSuspend: fn.isSuspend,
                            nullability: fn.nullability,
                            throws: fn.throws
                        )))
                    }()
                    contextualArgExpectedTypes[index] = contextualLambdaType
                    if let contextualLambdaType, expectedTypeCandidates.count == 1,
                       let candidate = expectedTypeCandidates.first,
                       let signature = sema.symbols.functionSignature(for: candidate)
                    {
                        contextualArgExpectedTypes[index] = applyDispatchReceiverClassTypeArgs(
                            to: contextualLambdaType, signature: signature, candidate: candidate, ctx: ctx
                        )
                    }
                    if declaresConcreteLambdaParameterTypes(
                        at: index,
                        argumentCount: args.count,
                        argumentLabel: argument.label,
                        candidates: expectedTypeCandidates,
                        sema: sema
                    ) {
                        sema.bindings.markSourceDeclaredExpectedType(argument.expr)
                    }
                    if expectation.isInputOnly {
                        inputOnlyLambdaIndices.insert(index)
                    }
                    if expectation.blocksRefinement {
                        blockedLambdaRefinement = true
                        // A lambda with no declared parameter list (`{ it }` or `{ ... }`)
                        // has no locally-known type to fall back on; if the surviving
                        // candidates each want exactly one parameter but disagree on its
                        // type, there is no way to check the body without guessing which
                        // overload was meant.
                        if lambdaParams.isEmpty,
                           expectation.hasAmbiguousImplicitParameterShape,
                           lambdaBodyUsesImplicitIt(argument.expr, ctx: ctx)
                        {
                            hasUnresolvableImplicitLambdaParameter = true
                        }
                    }
                default:
                    break
                }
            }

            if let contextualExpectedType = contextualArgExpectedTypes[index] {
                let inferenceContext = lambdaContextOverrides[index] ?? ctx
                let inferredType = driver.inferExpr(
                    argument.expr,
                    ctx: inferenceContext,
                    locals: &locals,
                    expectedType: contextualExpectedType
                )
                if inputOnlyLambdaIndices.contains(index) {
                    argTypes[index] = rebuildLambdaLiteralType(
                        exprID: argument.expr,
                        inferredType: inferredType,
                        contextualExpectedType: contextualExpectedType,
                        sema: sema
                    )
                } else {
                    argTypes[index] = inferredType
                }
            } else if let cached = inferredNonLambdaArgTypes[index] {
                argTypes[index] = cached
            } else {
                argTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }
            argTypes[index] = sourceLevelRangeArgumentType(
                argument.expr, inferredType: argTypes[index], ctx: ctx
            )
            inferredNonLambdaArgTypes[index] = argTypes[index]
        }

        let refinedArgTypes = args.enumerated().map { index, argument -> TypeID in
            let type = argTypes[index]
            // A bare `ClassName` argument denotes the class's companion object.
            if !lambdaLiteralIndices.contains(index),
               let companionType = driver.helpers.retypeClassNameAsCompanionValue(
                   argument.expr, currentType: type, ast: ast, sema: sema
               )
            {
                return companionType
            }
            return type
        }

        return PreparedCallArguments(
            argTypes: collectPostponedArgumentConstraints(
                args: args, argTypes: refinedArgTypes, candidates: candidates,
                ctx: ctx
            ),
            lambdaLiteralIndices: lambdaLiteralIndices,
            inputOnlyLambdaIndices: inputOnlyLambdaIndices,
            blockedLambdaRefinement: blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: hasUnresolvableImplicitLambdaParameter
        )
    }

    func resolveCallRespectingLambdaReturnType(
        candidates: [SymbolID],
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        calleeName: InternedString,
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]] = [:],
        lambdaLiteralIndices: Set<Int>,
        inputOnlyLambdaIndices: Set<Int>,
        blockedLambdaRefinement: Bool,
        hasUnresolvableImplicitLambdaParameter: Bool,
        ctx: TypeInferenceContext
    ) -> ResolvedCall {
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
            return CallArg(
                label: argument.label,
                isSpread: argument.isSpread,
                type: type,
                signedIntegerLiteral: literal.signed,
                unsignedIntegerLiteral: literal.unsigned
            )
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: resolvedArgs,
            explicitTypeArgs: explicitTypeArgs,
            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
        )

        let hasRefinementAnnotation = candidates.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        })
        let functionParameterArgumentPositions = Set(args.indices.filter { argIndex in
            candidates.contains { candidate in
                guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                let parameterType: TypeID?
                if lambdaLiteralIndices.contains(argIndex) {
                    parameterType = lambdaParameterTypeForArgument(
                        at: argIndex,
                        argumentCount: args.count,
                        argumentLabel: args[argIndex].label,
                        in: signature,
                        sema: ctx.sema
                    )
                } else {
                    parameterType = parameterTypeForArgument(at: argIndex, in: signature)
                }
                guard let parameterType else { return false }
                if case .functionType = ctx.sema.types.kind(of: parameterType) {
                    return true
                }
                return false
            }
        })
        let functionTypedArgumentIndices = Set(args.indices.filter { index in
            guard case .functionType = ctx.sema.types.kind(of: argTypes[index]) else {
                return false
            }
            guard let expr = ctx.ast.arena.expr(args[index].expr) else {
                return false
            }
            if case .callableRef = expr {
                return false
            }
            return true
        })

        if blockedLambdaRefinement, hasRefinementAnnotation || hasUnresolvableImplicitLambdaParameter {
            return ambiguousCallResult(range: range, candidateSymbols: candidates, sema: ctx.sema)
        }

        let contextualExpectedType = overloadResolutionExpectedType(from: expectedType, sema: ctx.sema)

        guard !inputOnlyLambdaIndices.isEmpty else {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: contextualExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                ctx: ctx.semaCtx
            )
        }

        // These ambiguity checks only apply when lambda-return-type overload
        // resolution is actually attempted (inputOnlyLambdaIndices is non-empty).
        // Running them earlier would incorrectly reject single-candidate calls.
        if functionParameterArgumentPositions.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range, candidateSymbols: candidates, sema: ctx.sema)
        }
        if functionTypedArgumentIndices.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range, candidateSymbols: candidates, sema: ctx.sema)
        }

        let overloadResolutionExpectedType: TypeID? = nil

        let probe = ctx.resolver.probeCall(
            candidates: candidates,
            call: call,
            expectedType: overloadResolutionExpectedType,
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: candidateArgumentTypes,
            ignoringLambdaReturnTypeArgumentIndices: inputOnlyLambdaIndices,
            ctx: ctx.semaCtx
        )
        let viableSymbols = probe.viableCandidates.map(\.symbol)
        if viableSymbols.isEmpty {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                ctx: ctx.semaCtx
            )
        }
        if viableSymbols.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                ctx: ctx.semaCtx
            )
        }
        guard lambdaLiteralIndices.count == 1,
              let lambdaIndex = lambdaLiteralIndices.first,
              inputOnlyLambdaIndices.contains(lambdaIndex)
        else {
            return ambiguousCallResult(range: range, candidateSymbols: viableSymbols, sema: ctx.sema)
        }
        // When all viable candidates share the same input-only HOF shape, the
        // apparent ambiguity is structural — not semantic. Fall back to the standard
        // resolver which picks the most specific receiver type.
        if viableSymbols.allSatisfy({
            Self.inputOnlyExternalLinkNames.contains(ctx.sema.symbols.externalLinkName(for: $0) ?? "")
        }) {
            return ctx.resolver.resolveCall(
                candidates: viableSymbols,
                call: call,
                expectedType: contextualExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                ctx: ctx.semaCtx
            )
        }
        guard viableSymbols.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        }) else {
            return ambiguousCallResult(range: range, candidateSymbols: viableSymbols, sema: ctx.sema)
        }

        let refinedCandidates = refineCandidatesByLambdaReturnType(
            candidateSymbols: viableSymbols,
            lambdaArgumentIndex: lambdaIndex,
            argType: argTypes[lambdaIndex],
            argumentCount: args.count,
            argumentLabel: args[lambdaIndex].label,
            sema: ctx.sema
        )
        if refinedCandidates.isEmpty {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                ctx: ctx.semaCtx
            )
        }
        if refinedCandidates.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: refinedCandidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                ctx: ctx.semaCtx
            )
        }
        return ambiguousCallResult(range: range, candidateSymbols: refinedCandidates, sema: ctx.sema)
    }

    func overloadResolutionExpectedType(from expectedType: TypeID?, sema: SemaModule) -> TypeID? {
        // Unit contexts accept and discard any expression result, so Unit must
        // not act as a return-type constraint while choosing an overload.
        guard expectedType != sema.types.unitType else {
            return nil
        }
        return expectedType
    }

    private func narrowedCallCandidates(
        candidates: [SymbolID],
        args: [CallArgument],
        inferredNonLambdaArgTypes: [Int: TypeID],
        receiverType: TypeID?,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema

        // A candidate that declares an extension/member receiver can never be
        // chosen when the call site has no receiver at all (explicit or
        // implicit) -- Resolution.swift's buildReceiverConstraints rejects it
        // outright in that case. Without pruning it here too, an unqualified
        // call such as `measureTimedValue { ... }` still sees an unrelated
        // same-named extension (e.g. `TimeSource.measureTimedValue`) as a live
        // candidate for the lambda's expected type, corrupting it even though
        // that extension can never actually be selected. A present-but-
        // mismatched receiver is left to final resolution, unchanged.
        let effectiveReceiverType = receiverType ?? ctx.implicitReceiverType
        let candidates = effectiveReceiverType != nil
            ? candidates
            : candidates.filter {
                sema.symbols.symbol($0)?.kind == .constructor
                    || sema.symbols.functionSignature(for: $0)?.receiverType == nil
            }

        var narrowed = candidates.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count),
                  let parameterMapping = parameterMappingForCallArguments(args, in: signature, ctx: ctx)
            else {
                return false
            }
            for (otherIndex, inferredType) in inferredNonLambdaArgTypes {
                guard args.indices.contains(otherIndex),
                      let parameterIndex = parameterMapping[otherIndex],
                      let parameterType = contextualCallArgumentType(
                          args[otherIndex],
                          parameterIndex: parameterIndex,
                          in: signature,
                          ctx: ctx
                      )
                else {
                    return false
                }
                let isNamedVarargArray = args[otherIndex].label != nil
                    && signature.valueParameterIsVararg.indices.contains(parameterIndex)
                    && signature.valueParameterIsVararg[parameterIndex]
                if args[otherIndex].isSpread || isNamedVarargArray {
                    // The final resolver checks the array shape and, for
                    // generic arrays, constrains the vararg element type.
                    // Comparing this array with the element parameter here
                    // prematurely prunes every viable candidate.
                    continue
                }
                if sema.types.isSubtype(inferredType, parameterType) {
                    continue
                }
                if !args[otherIndex].isSpread,
                   integerLiteralFitsParameter(args[otherIndex].expr, parameterType: parameterType, ctx: ctx)
                {
                    continue
                }
                // A parameter whose type is still an unsubstituted type
                // parameter (`initialValue: R`) never passes a subtype check
                // before inference runs, so judge those positions by shape:
                // reject incompatible function or nominal type shapes.
                guard typeMentionsTypeParameter(parameterType, sema: sema) else {
                    return false
                }
                if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)),
                   !isFunctionTypeLike(inferredType, sema: sema)
                {
                    return false
                }
                if !args[otherIndex].isSpread,
                   case let .classType(parameterClass) = sema.types.kind(of: parameterType),
                   case let .classType(argumentClass) = sema.types.kind(of: inferredType),
                   !sema.types.isNominalSubtypeSymbol(argumentClass.classSymbol, of: parameterClass.classSymbol)
                {
                    return false
                }
            }
            // Overloads that differ only in the arity of a function-typed
            // parameter (Grouping.fold's initialValue vs. initialValueSelector
            // forms) can be told apart before inference when the lambda spells
            // out its parameters: a `{ a, b -> ... }` argument can only match a
            // two-parameter function type. Without this the surviving
            // candidates disagree on the lambda's shape and no expected type is
            // pushed into the body, leaving its parameters untyped.
            for (argIndex, argument) in args.enumerated() {
                guard case let .lambdaLiteral(lambdaParams, _, _, _) = ctx.ast.arena.expr(argument.expr)
                else {
                    continue
                }
                guard let parameterType = lambdaParameterTypeForArgument(
                    at: argIndex,
                    argumentCount: args.count,
                    argumentLabel: argument.label,
                    in: signature,
                    sema: sema
                ),
                      case let .functionType(functionType) = sema.types.kind(
                          of: sema.types.makeNonNullable(parameterType)
                      )
                else {
                    if !lambdaParams.isEmpty {
                        return false
                    }
                    continue
                }
                // Without a parameter list, only zero parameters or a single
                // implicit `it` can be supplied, never two or more.
                if lambdaParams.isEmpty {
                    if functionType.params.count > 1 {
                        return false
                    }
                } else if functionType.params.count != lambdaParams.count {
                    return false
                }
            }
            return true
        }

        // Prune candidates whose declared receiver the call-site receiver can
        // never satisfy: `onEach` is declared on `Sequence`, `Iterable`,
        // `Map`, and `CharSequence`, but a `String` receiver can only ever
        // select the `CharSequence` overload. Infeasible siblings still go
        // through final resolution unchanged — leaving them in this set only
        // corrupts the lambda's expected type with irreconcilable parameter
        // shapes and leaves implicit `it` untyped.
        let receiverFeasible = narrowed.filter { candidate in
            if sema.symbols.symbol(candidate)?.kind == .constructor {
                return true
            }
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return receiverConstraintIsFeasible(
                signature: signature,
                receiverType: effectiveReceiverType,
                sema: sema
            )
        }
        narrowed = receiverFeasible.isEmpty ? narrowed : receiverFeasible

        // A bare lambda literal is itself a function value. When overloads
        // differ between a function-typed parameter and an unconstrained type
        // parameter at the same position, prefer the function-typed candidates
        // so the lambda receives a single contextual type. Otherwise a generic
        // overload can also bind its type parameter to the lambda's function
        // type, leaving equivalent candidates and untyped `it` parameters in
        // later lambdas. This is a general shape rule, not a stdlib-name rule.
        let emptyLambdaIndices = args.indices.filter { argIndex in
            guard case let .lambdaLiteral(lambdaParams, _, _, _) = ctx.ast.arena.expr(args[argIndex].expr),
                  lambdaParams.isEmpty
            else {
                return false
            }
            return true
        }
        let lambdaShapeIndices = emptyLambdaIndices.filter { argIndex in
            let hasFunctionCandidate = narrowed.contains { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                          at: argIndex,
                          argumentCount: args.count,
                          argumentLabel: args[argIndex].label,
                          in: signature,
                          sema: sema
                      )
                else {
                    return false
                }
                return isFunctionTypeLike(parameterType, sema: sema)
            }
            let hasNonFunctionCandidate = narrowed.contains { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                          at: argIndex,
                          argumentCount: args.count,
                          argumentLabel: args[argIndex].label,
                          in: signature,
                          sema: sema
                      )
                else {
                    return false
                }
                return !isFunctionTypeLike(parameterType, sema: sema)
            }
            return hasFunctionCandidate && hasNonFunctionCandidate
        }
        let lambdaShapeNarrowed = narrowed.filter { candidate in
            lambdaShapeIndices.allSatisfy { argIndex in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                          at: argIndex,
                          argumentCount: args.count,
                          argumentLabel: args[argIndex].label,
                          in: signature,
                          sema: sema
                      )
                else {
                    return false
                }
                return isFunctionTypeLike(parameterType, sema: sema)
            }
        }
        if !lambdaShapeNarrowed.isEmpty,
           lambdaShapeNarrowed.count < narrowed.count
        {
            return lambdaShapeNarrowed
        }

        // A null-only producer has no non-null lower bound from which the
        // generic `() -> T?` overload can infer T. Kotlin resolves this case
        // through the bottom-type overload, but that overload must not win for
        // ordinary producers such as `{ 42 }`.
        let nullOnlyLambdaIndices = emptyLambdaIndices.filter { argIndex in
            lambdaBodyIsNullLiteral(args[argIndex].expr, ctx: ctx)
        }
        let nullProducerNarrowed = narrowed.filter { candidate in
            nullOnlyLambdaIndices.allSatisfy { argIndex in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      let parameterType = lambdaParameterTypeForArgument(
                          at: argIndex,
                          argumentCount: args.count,
                          argumentLabel: args[argIndex].label,
                          in: signature,
                          sema: sema
                      ),
                      case let .functionType(functionType) = sema.types.kind(
                          of: sema.types.makeNonNullable(parameterType)
                      )
                else {
                    return false
                }
                return functionType.returnType == sema.types.nullableNothingType
            }
        }
        if !nullOnlyLambdaIndices.isEmpty,
           !nullProducerNarrowed.isEmpty,
           nullProducerNarrowed.count < narrowed.count
        {
            return nullProducerNarrowed
        }

        return narrowed.isEmpty ? candidates : narrowed
    }

    /// Whether the call-site receiver can ever satisfy the candidate's declared
    /// receiver. Used only to keep the lambda expected-type candidate set free
    /// of same-named overloads that final resolution could never select.
    private func receiverConstraintIsFeasible(
        signature: FunctionSignature,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> Bool {
        guard let receiverType,
              let declaredReceiver = signature.receiverType
        else {
            return true
        }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        let nonNullDeclared = sema.types.makeNonNullable(declaredReceiver)
        if case let .typeParam(receiverTypeParam) = sema.types.kind(of: nonNullDeclared) {
            // Bare type-parameter receiver (`C : Iterable<T>`, `S : CharSequence`):
            // judge feasibility by the parameter's upper bounds after
            // substituting the receiver variable itself, so F-bounded contracts
            // (`T : Comparable<T>`) still hold. Bounds that stay type parameters
            // (`C : R`) constrain a different variable and are skipped.
            let bounds = sema.symbols.typeParameterUpperBounds(for: receiverTypeParam.symbol)
            guard !bounds.isEmpty else {
                return true
            }
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            guard let typeVar = typeVarBySymbol[receiverTypeParam.symbol] else {
                return true
            }
            let substitution: [TypeVarID: TypeID] = [typeVar: nonNullReceiver]
            for bound in bounds {
                let substitutedBound = sema.types.substituteTypeParameters(
                    in: bound,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                let nonNullBound = sema.types.makeNonNullable(substitutedBound)
                if case .typeParam = sema.types.kind(of: nonNullBound) {
                    continue
                }
                if let boundClass = resolveClassType(nonNullBound, sema: sema),
                   let actualClass = resolveClassType(nonNullReceiver, sema: sema)
                {
                    if actualClass.classSymbol != boundClass.classSymbol,
                       !sema.types.isNominalSubtypeSymbol(
                           actualClass.classSymbol,
                           of: boundClass.classSymbol
                       )
                    {
                        return false
                    }
                    continue
                }
                if !sema.types.isSubtype(nonNullReceiver, nonNullBound) {
                    return false
                }
            }
            return true
        }
        guard let declaredClass = resolveClassType(nonNullDeclared, sema: sema),
              let actualClass = resolveClassType(nonNullReceiver, sema: sema)
        else {
            // Non-nominal actual receiver (e.g. primitive String) or an opaque
            // declared receiver: fall back to the subtype oracle.
            return sema.types.isSubtype(nonNullReceiver, nonNullDeclared)
        }
        return declaredClass.classSymbol == actualClass.classSymbol
            || sema.types.isNominalSubtypeSymbol(
                actualClass.classSymbol,
                of: declaredClass.classSymbol
            )
    }

    /// Whether the only candidate for the call declares this argument as a
    /// function type whose parameter types are written out concretely in source
    /// (no type parameter left for inference to substitute). Such a signature
    /// is authoritative even where it says `Any`, unlike the `Any` inference
    /// falls back to when a type variable stays unsolved (BUG-163).
    private func declaresConcreteLambdaParameterTypes(
        at index: Int,
        argumentCount: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> Bool {
        guard candidates.count == 1,
              let candidate = candidates.first,
              sema.symbols.isSourceBackedSymbol(candidate),
              let signature = sema.symbols.functionSignature(for: candidate),
              let parameterType = lambdaParameterTypeForArgument(
                  at: index,
                  argumentCount: argumentCount,
                  argumentLabel: argumentLabel,
                  in: signature,
                  sema: sema
              ),
              case let .functionType(declared) = sema.types.kind(of: parameterType)
        else {
            return false
        }
        return !declared.params.contains { typeMentionsTypeParameter($0, sema: sema) }
    }

    /// Whether `type` can be passed where a function type is expected, covering
    /// both plain function types and SAM-convertible interfaces.
    private func isFunctionTypeLike(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(type)) {
            return true
        }
        return driver.helpers.samFunctionType(for: type, sema: sema) != nil
    }

    private func rebuildLambdaLiteralType(
        exprID: ExprID,
        inferredType: TypeID,
        contextualExpectedType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard case let .lambdaLiteral(_, bodyExpr, _, _) = driver.ast.arena.expr(exprID),
              case let .functionType(functionType) = sema.types.kind(of: contextualExpectedType),
              let bodyType = sema.bindings.exprType(for: bodyExpr)
        else {
            return inferredType
        }

        return sema.types.make(.functionType(FunctionType(
            receiver: functionType.receiver,
            params: functionType.params,
            returnType: bodyType,
            isSuspend: functionType.isSuspend,
            nullability: functionType.nullability
        )))
    }

    private func refineCandidatesByLambdaReturnType(
        candidateSymbols: [SymbolID],
        lambdaArgumentIndex: Int,
        argType: TypeID,
        argumentCount: Int,
        argumentLabel: InternedString?,
        sema: SemaModule
    ) -> [SymbolID] {
        guard case let .functionType(argumentFunctionType) = sema.types.kind(of: argType) else {
            return candidateSymbols
        }

        return candidateSymbols.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = lambdaParameterTypeForArgument(
                      at: lambdaArgumentIndex,
                      argumentCount: argumentCount,
                      argumentLabel: argumentLabel,
                      in: signature,
                      sema: sema
                  ),
                  case let .functionType(parameterFunctionType) = sema.types.kind(of: parameterType)
            else {
                return false
            }
            return sema.types.isSubtype(argumentFunctionType.returnType, parameterFunctionType.returnType)
        }
    }

    private func hasOverloadResolutionByLambdaReturnTypeAnnotation(
        symbol: SymbolID,
        sema: SemaModule
    ) -> Bool {
        sema.symbols.annotations(for: symbol).contains { annotation in
            KnownCompilerAnnotation.overloadResolutionByLambdaReturnType.matches(annotation.annotationFQName)
        }
    }

    private func ambiguousCallResult(
        range: SourceRange,
        candidateSymbols: [SymbolID],
        sema: SemaModule
    ) -> ResolvedCall {
        ResolvedCall(
            chosenCallee: nil,
            substitutedTypeArguments: [:],
            parameterMapping: [:],
            diagnostic: Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0003",
                message: "Ambiguous overload resolution.",
                primaryRange: range,
                secondaryRanges: sema.symbols.sortedDeclSites(of: candidateSymbols)
            )
        )
    }
}
