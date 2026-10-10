
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

    private struct LambdaParameterCandidate {
        let originalType: TypeID
        let functionType: FunctionType
    }

    func prepareCallArguments(
        args: [CallArgument],
        callRange: SourceRange,
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
                    callRange: callRange,
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
                        args: args,
                        callRange: callRange,
                        candidates: expectedTypeCandidates,
                        explicitTypeArgs: explicitTypeArgs,
                        receiverType: receiverType,
                        inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                        resolver: ctx.resolver,
                        sema: sema,
                        ctx: ctx
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
                        args: args,
                        callRange: callRange,
                        candidates: expectedTypeCandidates,
                        sema: sema,
                        ctx: ctx
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
                args: args, range: callRange, argTypes: refinedArgTypes, candidates: candidates,
                ctx: ctx
            ),
            lambdaLiteralIndices: lambdaLiteralIndices,
            inputOnlyLambdaIndices: inputOnlyLambdaIndices,
            blockedLambdaRefinement: blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: hasUnresolvableImplicitLambdaParameter
        )
    }

    func sourceLevelRangeArgumentType(
        _ expr: ExprID,
        inferredType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        // Preserve the scalar binding for range lowering, but use the nominal
        // type for argument constraints, including generic upper bounds.
        guard sema.bindings.isRangeExpr(expr) || sema.bindings.isFloatingPointRangeExpr(expr),
              case .primitive = sema.types.kind(of: sema.types.makeNonNullable(inferredType)),
              let rangeType = floatingPointRangeArgumentType(
                  expr, ast: ctx.ast, sema: sema, interner: ctx.interner
              ) ?? sourceLevelRangeMemberLookupType(
                  receiverExpr: expr,
                  receiverType: inferredType,
                  sema: sema,
                  interner: ctx.interner
              )
        else {
            return inferredType
        }
        return sema.types.nullability(of: inferredType) == .nullable
            ? sema.types.makeNullable(rangeType)
            : rangeType
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
            return CallArg.source(
                argument, type: type, callRange: range, ast: ctx.ast,
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
                        args: args,
                        callRange: range,
                        in: signature,
                        ctx: ctx
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
            args: args,
            callRange: range,
            sema: ctx.sema,
            ctx: ctx
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

    func integerLiteralValues(
        _ exprID: ExprID,
        ast: ASTModule
    ) -> (signed: Int64?, unsigned: UInt64?) {
        switch ast.arena.expr(exprID) {
        case let .intLiteral(value, _):
            return (value, nil)
        case let .uintLiteral(value, _):
            return (nil, value)
        case let .unaryExpr(op, operand, _) where op == .unaryMinus || op == .unaryPlus:
            guard case let .intLiteral(value, _) = ast.arena.expr(operand) else {
                return (nil, nil)
            }
            if op == .unaryMinus {
                let (negated, overflow) = value.multipliedReportingOverflow(by: -1)
                return (overflow ? nil : negated, nil)
            }
            return (value, nil)
        default:
            return (nil, nil)
        }
    }

    func contextualizeResolvedIntegerArguments(
        args: [CallArgument],
        resolved: ResolvedCall,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) {
        guard let chosen = resolved.chosenCallee,
              let signature = ctx.sema.symbols.functionSignature(for: chosen)
        else { return }
        let typeVarBySymbol = ctx.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        for (index, argument) in args.enumerated() where !argument.isSpread {
            let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
            guard literal.signed != nil || literal.unsigned != nil,
                  let parameterIndex = resolved.parameterMapping[index],
                  signature.parameterTypes.indices.contains(parameterIndex)
            else { continue }
            let parameterType = ctx.sema.types.substituteTypeParameters(
                in: signature.parameterTypes[parameterIndex],
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
            _ = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals, expectedType: parameterType)
        }
    }

    func overloadResolutionExpectedType(from expectedType: TypeID?, sema: SemaModule) -> TypeID? {
        // Unit contexts accept and discard any expression result, so Unit must
        // not act as a return-type constraint while choosing an overload.
        guard expectedType != sema.types.unitType else {
            return nil
        }
        return expectedType
    }

    /// Returns the expected numeric type (Long/UInt/ULong/Byte/Short) for an
    /// unsuffixed int-literal argument if every candidate agrees on that
    /// parameter being one of those types, so the literal can be widened before
    /// overload resolution instead of defaulting to Int and rejecting every
    /// candidate. Returns nil (leaving the literal as Int) when candidates
    /// disagree or none expect a wideable numeric type — the normal Int-literal
    /// path and existing overload resolution still handle those cases.
    func uniformNumericLiteralParameterType(
        at index: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        var result: TypeID?
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = parameterTypeForArgument(
                      at: index,
                      argumentLabel: argumentLabel,
                      in: signature,
                      sema: sema
                  )
            else {
                return nil
            }
            let nonNullParameterType = sema.types.makeNonNullable(parameterType)
            guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullParameterType)
            else {
                // A parameter of non-numeric type can never accept an integer
                // literal -- it does not veto narrowing to a numeric overload
                // (e.g. `onTimeout(30)` with `Long` and `Duration` overloads).
                continue
            }
            // A plain `Int` candidate absorbs the literal as an exact match
            // and must not be pre-empted by narrowing.
            if primitive == .int {
                return nil
            }
            guard primitive == .long || primitive == .uint || primitive == .ulong ||
                  primitive == .byte || primitive == .short
            else {
                // Float/Double/other primitives cannot take an integer literal.
                continue
            }
            if let result, result != nonNullParameterType {
                return nil
            }
            result = nonNullParameterType
        }
        return result
    }

    private func parameterTypeForArgument(
        at index: Int,
        argumentLabel: InternedString?,
        in signature: FunctionSignature,
        sema: SemaModule
    ) -> TypeID? {
        guard let argumentLabel else {
            return parameterTypeForArgument(at: index, in: signature)
        }
        for (parameterIndex, parameterSymbol) in signature.valueParameterSymbols.enumerated() {
            if sema.symbols.symbol(parameterSymbol)?.name == argumentLabel,
               parameterIndex < signature.parameterTypes.count
            {
                return signature.parameterTypes[parameterIndex]
            }
        }
        return nil
    }

    /// Builds the same source-argument to parameter mapping that final overload
    /// resolution uses. The older index-only helpers cannot distinguish a
    /// positional vararg element from a later defaulted parameter once the
    /// argument list crosses the vararg slot.
    func parameterMappingForCallArguments(
        _ args: [CallArgument],
        in signature: FunctionSignature,
        callRange: SourceRange,
        ctx: TypeInferenceContext
    ) -> [Int: Int]? {
        let sema = ctx.sema
        let callArgs = args.map { argument in
            CallArg.source(
                argument, type: sema.bindings.exprTypes[argument.expr] ?? sema.types.anyType,
                callRange: callRange, ast: ctx.ast
            )
        }
        return ctx.resolver.buildParameterMapping(
            signature: signature,
            callArgs: callArgs,
            symbols: sema.symbols,
            typeSystem: sema.types,
            isCallableArgument: { index in
                guard args.indices.contains(index) else { return false }
                if case .lambdaLiteral = ctx.ast.arena.expr(args[index].expr) {
                    return true
                }
                if case .callableRef = ctx.ast.arena.expr(args[index].expr) {
                    return true
                }
                guard let type = sema.bindings.exprTypes[args[index].expr] else {
                    return false
                }
                if case .functionType = sema.types.kind(of: type) {
                    return true
                }
                return false
            }
        )
    }

    /// The expected source type of one nested call argument. A spread argument
    /// and a named vararg argument carry the complete array at the call site;
    /// their contextual type is therefore the vararg array, not its element.
    func contextualCallArgumentType(
        _ argument: CallArgument,
        parameterIndex: Int,
        in signature: FunctionSignature,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        guard signature.parameterTypes.indices.contains(parameterIndex) else {
            return nil
        }
        let parameterType = signature.parameterTypes[parameterIndex]
        let isVararg = signature.valueParameterIsVararg.indices.contains(parameterIndex)
            && signature.valueParameterIsVararg[parameterIndex]
        guard isVararg, argument.isSpread || argument.label != nil else {
            return parameterType
        }
        if let primitiveArrayType = primitiveVarargArrayType(
            elementType: parameterType,
            sema: ctx.sema,
            interner: ctx.interner
        ) {
            return primitiveArrayType
        }
        let arrayName = ctx.interner.intern("Array")
        guard let arraySymbol = ctx.sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), arrayName]) else {
            return nil
        }
        return ctx.sema.types.make(.classType(ClassType(
            classSymbol: arraySymbol,
            args: [.out(parameterType)],
            nullability: .nonNull
        )))
    }

    /// Returns the single unsigned parameter type shared by all candidates for a
    /// suffixed unsigned literal. Unlike unsuffixed integer literals, Kotlin
    /// allows a constant UInt literal to narrow to UByte/UShort or widen to
    /// ULong when the expected parameter type requires it.
    func uniformUnsignedLiteralParameterType(
        at index: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        var result: TypeID?
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = parameterTypeForArgument(
                      at: index,
                      argumentLabel: argumentLabel,
                      in: signature,
                      sema: sema
                  )
            else {
                return nil
            }
            let nonNullParameterType = sema.types.makeNonNullable(parameterType)
            guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullParameterType)
            else {
                continue
            }
            if primitive == .uint {
                return nil
            }
            guard primitive == .ubyte || primitive == .ushort ||
                  primitive == .uint || primitive == .ulong
            else {
                continue
            }
            if let result, result != nonNullParameterType {
                return nil
            }
            result = nonNullParameterType
        }
        return result
    }

    private func narrowedCallCandidates(
        candidates: [SymbolID],
        args: [CallArgument],
        callRange: SourceRange,
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
                  let parameterMapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx)
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
                    args: args,
                    callRange: callRange,
                    in: signature,
                    ctx: ctx
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
                          args: args,
                          callRange: callRange,
                          in: signature,
                          ctx: ctx
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
                          args: args,
                          callRange: callRange,
                          in: signature,
                          ctx: ctx
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
                          args: args,
                          callRange: callRange,
                          in: signature,
                          ctx: ctx
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
                          args: args,
                          callRange: callRange,
                          in: signature,
                          ctx: ctx
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

    func integerLiteralFitsParameter(
        _ exprID: ExprID,
        parameterType: TypeID,
        ctx: TypeInferenceContext
    ) -> Bool {
        let values = integerLiteralValues(exprID, ast: ctx.ast)
        let types = ctx.sema.types
        guard case let .primitive(primitive, _) = types.kind(of: types.makeNonNullable(parameterType)) else {
            return false
        }
        if let value = values.signed {
            switch primitive {
            case .byte: return (-128...127).contains(value)
            case .short: return (-32768...32767).contains(value)
            case .long: return true
            default: return false
            }
        }
        if let value = values.unsigned {
            switch primitive {
            case .ubyte: return value <= UInt64(UInt8.max)
            case .ushort: return value <= UInt64(UInt16.max)
            case .ulong: return true
            default: return false
            }
        }
        return false
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

    /// Applies explicit type arguments to a parameter type from a given signature.
    /// When explicit type args are provided, substitutes them into the parameter type.
    /// - Parameter typeArgOffset: Index into `signature.typeParameterSymbols` at which the
    ///   explicit type args begin. For constructors this is 0 (explicit args map to the class's
    ///   own type parameters). For non-constructor member functions this should be
    ///   `signature.classTypeParameterCount`, so that the explicit args skip the leading class
    ///   type parameters (which are inferred from the receiver) and map only to the function's
    ///   own type parameters.
    private func applyExplicitTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        explicitTypeArgs: [TypeID],
        sema: SemaModule
    ) -> TypeID {
        guard !explicitTypeArgs.isEmpty, !signature.typeParameterSymbols.isEmpty else {
            return parameterType
        }
        let isConstructor = sema.symbols.symbol(candidate)?.kind == .constructor
        let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (idx, explicitTypeArg) in explicitTypeArgs.enumerated() {
            let symbolIndex = typeArgOffset + idx
            guard symbolIndex < signature.typeParameterSymbols.count else { break }
            let sym = signature.typeParameterSymbols[symbolIndex]
            if let typeVar = typeVarBySymbol[sym] {
                substitution[typeVar] = explicitTypeArg
            }
        }
        guard !substitution.isEmpty else { return parameterType }
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    func applyDispatchReceiverClassTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard signature.classTypeParameterCount > 0,
              let owner = sema.symbols.parentSymbol(for: candidate)
        else { return parameterType }
        let receivers = ctx.implicitReceiverStack.reversed().map(\.type)
            + [ctx.implicitReceiverType].compactMap { $0 }
            + ctx.outerReceiverTypes.reversed().map(\.type)
        for receiver in receivers {
            guard let receiverClass = resolveClassType(receiver, sema: sema),
                  let ownerArgs = sema.types.liftedNominalSupertypeArgs(
                      from: receiverClass.classSymbol,
                      childArgs: receiverClass.args,
                      to: owner
                  ),
                  ownerArgs.count >= signature.classTypeParameterCount
            else { continue }
            let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, symbol) in signature.typeParameterSymbols
                .prefix(signature.classTypeParameterCount)
                .enumerated()
            {
                guard let variable = variables[symbol] else { continue }
                switch ownerArgs[index] {
                case let .invariant(type), let .in(type), let .out(type):
                    substitution[variable] = type
                case .star:
                    break
                }
            }
            return sema.types.substituteTypeParameters(
                in: parameterType, substitution: substitution, typeVarBySymbol: variables
            )
        }
        return parameterType
    }

    /// Substitutes the class type parameters used in `signature.receiverType`
    /// with the concrete generic arguments of the call-site `receiverType`. This
    /// lets trailing-lambda expected types be computed with the receiver's
    /// generic substitutions already applied, so `it` in `xs.map { it * 10 }`
    /// is seen as `Int` rather than `T`.
    ///
    /// For member functions whose declared receiver type is not available in the
    /// signature, the leading `classTypeParameterCount` type parameters are taken
    /// to be the class type parameters and are substituted from the call-site
    /// receiver's concrete class arguments.
    func applyReceiverClassTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard sema.symbols.symbol(candidate)?.kind != .constructor,
              !signature.typeParameterSymbols.isEmpty,
              let callSiteReceiverType = receiverType,
              let callSiteClass = resolveClassType(callSiteReceiverType, sema: sema)
        else {
            return parameterType
        }

        let declaredClassArgs: [TypeArg]
        let concreteClassArgs: [TypeArg]
        if let signatureReceiverType = signature.receiverType,
           let declaredClass = resolveClassType(signatureReceiverType, sema: sema) {
            if declaredClass.classSymbol == callSiteClass.classSymbol,
               declaredClass.args.count == callSiteClass.args.count {
                declaredClassArgs = declaredClass.args
                concreteClassArgs = callSiteClass.args
            } else if sema.types.isNominalSubtypeSymbol(callSiteClass.classSymbol, of: declaredClass.classSymbol) {
                declaredClassArgs = declaredClass.args
                guard let lifted = sema.types.liftedNominalSupertypeArgs(
                    from: callSiteClass.classSymbol,
                    childArgs: callSiteClass.args,
                    to: declaredClass.classSymbol
                ), lifted.count == declaredClassArgs.count else {
                    return parameterType
                }
                concreteClassArgs = lifted
            } else {
                return parameterType
            }
        } else if signature.classTypeParameterCount > 0,
                  callSiteClass.args.count >= signature.classTypeParameterCount {
            declaredClassArgs = signature.typeParameterSymbols.prefix(signature.classTypeParameterCount).map {
                .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
            }
            if let owner = sema.symbols.parentSymbol(for: candidate),
               let lifted = sema.types.liftedNominalSupertypeArgs(
                   from: callSiteClass.classSymbol, childArgs: callSiteClass.args, to: owner
               ) {
                concreteClassArgs = lifted
            } else {
                concreteClassArgs = Array(callSiteClass.args.prefix(signature.classTypeParameterCount))
            }
        } else {
            return parameterType
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for index in 0 ..< declaredClassArgs.count {
            let declaredArg: TypeID
            switch declaredClassArgs[index] {
            case let .invariant(type), let .out(type), let .in(type):
                declaredArg = type
            case .star:
                continue
            }
            guard case let .typeParam(declaredTypeParam) = sema.types.kind(of: declaredArg),
                  let typeVar = typeVarBySymbol[declaredTypeParam.symbol]
            else {
                continue
            }
            let concreteType: TypeID = switch concreteClassArgs[index] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
            }
            substitution[typeVar] = concreteType
        }
        guard !substitution.isEmpty else { return parameterType }
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// Substitutes the receiver type parameter of `signature` with the concrete
    /// call-site receiver type. For extension functions like `fun <T> T.apply(block: T.() -> Unit)`,
    /// the lambda's expected type `T.() -> Unit` must become `ConcreteType.() -> Unit`
    /// before the lambda body is type-checked so that unqualified member access on
    /// the implicit receiver resolves correctly.
    private func applyFunctionReceiverTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard let receiverType,
              let declaredReceiver = signature.receiverType,
              !signature.typeParameterSymbols.isEmpty
        else {
            return parameterType
        }
        let nonNullDeclaredReceiver = sema.types.makeNonNullable(declaredReceiver)
        guard case let .typeParam(receiverTypeParam) = sema.types.kind(of: nonNullDeclaredReceiver) else {
            return parameterType
        }
        // Class type parameters at the start of the list are handled by applyReceiverClassTypeArgs.
        if let index = signature.typeParameterSymbols.firstIndex(of: receiverTypeParam.symbol),
           index < signature.classTypeParameterCount {
            return parameterType
        }
        // `T` captures the full receiver type; only `T?` strips nullability
        // before substituting T (e.g. `nullable.also { it }` versus `T?.ext`).
        let substitutionReceiverType = declaredReceiver == nonNullDeclaredReceiver
            ? receiverType
            : sema.types.makeNonNullable(receiverType)
        // Avoid circular substitution when the concrete receiver still references the same type parameter.
        guard !sema.types.typeContainsTypeParam(substitutionReceiverType, symbol: receiverTypeParam.symbol) else {
            return parameterType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        guard let typeVar = typeVarBySymbol[receiverTypeParam.symbol] else {
            return parameterType
        }
        let substitution: [TypeVarID: TypeID] = [typeVar: substitutionReceiverType]
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    /// Substitutes `parameterType`'s type parameters using bindings inferred
    /// from the call's non-lambda arguments, which are already type-checked by
    /// the time a lambda argument's expected type is computed. Without this,
    /// a generic higher-order function's lambda parameter keeps the raw,
    /// unsubstituted type parameter as its static type (e.g. `T` instead of
    /// `Int`), which then fails operator/member resolution inside the lambda
    /// body even though the type is fully determined by the other arguments.
    private func applyInferredArgumentTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        inferredNonLambdaArgTypes: [Int: TypeID],
        resolver: OverloadResolver?,
        sema: SemaModule
    ) -> TypeID {
        guard let resolver,
              !inferredNonLambdaArgTypes.isEmpty,
              !signature.typeParameterSymbols.isEmpty
        else {
            return parameterType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution = resolver.probeArgumentTypeSubstitution(
            signature: signature,
            typeVarBySymbol: typeVarBySymbol,
            knownArgumentTypes: inferredNonLambdaArgTypes,
            typeSystem: sema.types
        )
        guard !substitution.isEmpty else { return parameterType }
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func callableReferenceExpectedType(
        at index: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        sema: SemaModule
    ) -> TypeID? {
        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let parameterIndex = parameterIndexForCallArgument(
               at: index, label: argumentLabel, in: signature, sema: sema
           ),
           parameterIndex < signature.parameterTypes.count
        {
            let rawType = signature.parameterTypes[parameterIndex]
            return applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
        }

        var matchingParameterTypes: [TypeID] = []
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterIndex = parameterIndexForCallArgument(
                      at: index, label: argumentLabel, in: signature, sema: sema
                  ),
                  parameterIndex < signature.parameterTypes.count
            else {
                continue
            }
            let parameterType = applyExplicitTypeArgs(
                to: signature.parameterTypes[parameterIndex],
                signature: signature,
                candidate: candidate,
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
            if case .functionType = sema.types.kind(of: parameterType) {
                matchingParameterTypes.append(parameterType)
            } else if driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil {
                matchingParameterTypes.append(parameterType)
            }
        }
        guard let firstType = matchingParameterTypes.first else {
            return nil
        }
        let allSame = matchingParameterTypes.dropFirst().allSatisfy { $0 == firstType }
        return allSame ? firstType : nil
    }

    private static let inputOnlyExternalLinkNames: Set<String> = [
    ]

    /// Whether the only candidate for the call declares this argument as a
    /// function type whose parameter types are written out concretely in source
    /// (no type parameter left for inference to substitute). Such a signature
    /// is authoritative even where it says `Any`, unlike the `Any` inference
    /// falls back to when a type variable stays unsolved (BUG-163).
    private func declaresConcreteLambdaParameterTypes(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard candidates.count == 1,
              let candidate = candidates.first,
              sema.symbols.isSourceBackedSymbol(candidate),
              let signature = sema.symbols.functionSignature(for: candidate),
              let parameterType = lambdaParameterTypeForArgument(
                  at: index,
                  args: args,
                  callRange: callRange,
                  in: signature,
                  ctx: ctx
              ),
              case let .functionType(declared) = sema.types.kind(of: parameterType)
        else {
            return false
        }
        return !declared.params.contains { typeMentionsTypeParameter($0, sema: sema) }
    }

    /// Uses final overload resolution's mapping for both parenthesized arguments
    /// and a trailing lambda, including named arguments and omitted varargs.
    private func lambdaParameterTypeForArgument(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        in signature: FunctionSignature,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        guard let mapping = parameterMappingForCallArguments(
            args, in: signature, callRange: callRange, ctx: ctx
        ), let parameterIndex = mapping[index],
              signature.parameterTypes.indices.contains(parameterIndex)
        else {
            return nil
        }
        return signature.parameterTypes[parameterIndex]
    }

    private func lambdaLiteralExpectedType(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> (
        type: TypeID?,
        isInputOnly: Bool,
        blocksRefinement: Bool,
        hasAmbiguousImplicitParameterShape: Bool
    ) {
        // When all candidates share the same input-only HOF shape, pick the
        // first candidate and treat the lambda as input-only so that its return type is
        // not used for constraint solving — matches what the single-candidate path does.
        if !candidates.isEmpty,
           candidates.allSatisfy({
               Self.inputOnlyExternalLinkNames.contains(sema.symbols.externalLinkName(for: $0) ?? "")
           }),
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let rawType = lambdaParameterTypeForArgument(
               at: index,
               args: args,
               callRange: callRange,
               in: signature,
               ctx: ctx
           )
        {
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
            let receiverSubstituted = applyReceiverClassTypeArgs(
                to: explicitSubstituted,
                signature: signature,
                candidate: candidates[0],
                receiverType: receiverType,
                sema: sema
            )
            let substituted = applyFunctionReceiverTypeArgs(
                to: receiverSubstituted,
                signature: signature,
                receiverType: receiverType,
                sema: sema
            )
            return (substituted, true, false, false)
        }

        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let rawType = lambdaParameterTypeForArgument(
               at: index,
               args: args,
               callRange: callRange,
               in: signature,
               ctx: ctx
           )
        {
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
            let receiverSubstituted = applyReceiverClassTypeArgs(
                to: explicitSubstituted,
                signature: signature,
                candidate: candidates[0],
                receiverType: receiverType,
                sema: sema
            )
            let functionReceiverSubstituted = applyFunctionReceiverTypeArgs(
                to: receiverSubstituted,
                signature: signature,
                receiverType: receiverType,
                sema: sema
            )
            let substituted = applyInferredArgumentTypeArgs(
                to: functionReceiverSubstituted,
                signature: signature,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                resolver: resolver,
                sema: sema
            )
            return (substituted, false, false, false)
        }

        let parameterCandidates = lambdaParameterCandidates(
            at: index,
            args: args,
            callRange: callRange,
            candidates: candidates,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: receiverType,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            resolver: resolver,
            sema: sema,
            ctx: ctx
        )
        guard !parameterCandidates.isEmpty else {
            return (nil, false, false, false)
        }

        if let first = parameterCandidates.first,
           parameterCandidates.dropFirst().allSatisfy({ $0.originalType == first.originalType })
        {
            return (first.originalType, false, false, false)
        }

        guard let sharedType = sharedLambdaInputOnlyType(
            from: parameterCandidates,
            types: sema.types
        ) else {
            // Candidates whose parameter type still mentions a type parameter
            // (e.g. `Sequence<T>.onEach` seen through a `String` receiver) can
            // never pin down a usable shape at this call site. When the
            // fully-concrete subset agrees on one shape, use it -- the
            // remaining candidates are infeasible or will unify to the same
            // shape once final resolution binds their type parameters.
            let concreteCandidates = parameterCandidates.filter {
                !typeMentionsTypeParameter($0.originalType, sema: sema)
            }
            if let firstConcrete = concreteCandidates.first,
               !concreteCandidates.isEmpty,
               concreteCandidates.dropFirst().allSatisfy({ $0.originalType == firstConcrete.originalType })
            {
                return (firstConcrete.originalType, false, false, false)
            }
            // The candidates disagree on this lambda's parameter shape, so no single
            // expected type can be pushed down. When every surviving candidate still
            // expects exactly one, genuinely concrete parameter type, a bare lambda
            // here would need an implicit `it` whose type cannot be determined
            // before an overload is chosen (DEBT-SEMA-004) -- e.g. `(Int) -> String`
            // vs. `(String) -> Int`. Candidates whose parameter type still mentions a
            // type parameter are excluded: two independently-registered overloads
            // (e.g. a source declaration and a synthetic vararg sibling) can each
            // mint their own distinct type-parameter symbol for what is conceptually
            // the same generic slot, so raw TypeID inequality there reflects how the
            // signatures happened to be built rather than a real shape conflict --
            // unlike concrete types, where inequality always means a real conflict.
            let isImplicitSingleParameterAmbiguous = parameterCandidates.allSatisfy { candidate in
                guard candidate.functionType.params.count == 1,
                      let onlyParam = candidate.functionType.params.first
                else {
                    return false
                }
                return !typeMentionsTypeParameter(onlyParam, sema: sema)
            }
            return (nil, false, parameterCandidates.count > 1, isImplicitSingleParameterAmbiguous)
        }
        return (sharedType, true, false, false)
    }

    /// Whether `type` can be passed where a function type is expected, covering
    /// both plain function types and SAM-convertible interfaces.
    private func isFunctionTypeLike(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(type)) {
            return true
        }
        return driver.helpers.samFunctionType(for: type, sema: sema) != nil
    }

    /// Recursively checks whether `type` (or any nested type argument / function
    /// parameter / return type) is or mentions a type parameter. Used to keep
    /// implicit-`it` ambiguity detection scoped to genuinely concrete, conflicting
    /// parameter types rather than misreading distinct type-parameter symbols that
    /// happen to represent the same generic slot as a real conflict.
    func typeMentionsTypeParameter(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .typeParam:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    typeMentionsTypeParameter(inner, sema: sema)
                case .star:
                    false
                }
            }
        case let .functionType(functionType):
            return functionType.params.contains { typeMentionsTypeParameter($0, sema: sema) }
                || typeMentionsTypeParameter(functionType.returnType, sema: sema)
                || (functionType.receiver.map { typeMentionsTypeParameter($0, sema: sema) } ?? false)
        case let .intersection(members):
            return members.contains { typeMentionsTypeParameter($0, sema: sema) }
        default:
            return false
        }
    }

    private func lambdaParameterCandidates(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> [LambdaParameterCandidate] {
        candidates.compactMap { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let rawParameterType = lambdaParameterTypeForArgument(
                      at: index,
                      args: args,
                      callRange: callRange,
                      in: signature,
                      ctx: ctx
                  )
            else {
                return nil
            }
            // Substitute the same way the single-candidate path does, so a
            // generic receiver's arguments reach the lambda's expected type
            // (`Iterable<T>.f(transform: (T) -> R)` called on `List<Int>` must
            // expose `it: Int`, not the bare declaration type parameter `T`).
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawParameterType,
                signature: signature,
                candidate: candidate,
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
            let receiverSubstituted = applyReceiverClassTypeArgs(
                to: explicitSubstituted,
                signature: signature,
                candidate: candidate,
                receiverType: receiverType,
                sema: sema
            )
            let functionReceiverSubstituted = applyFunctionReceiverTypeArgs(
                to: receiverSubstituted,
                signature: signature,
                receiverType: receiverType,
                sema: sema
            )
            let parameterType = applyInferredArgumentTypeArgs(
                to: functionReceiverSubstituted,
                signature: signature,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                resolver: resolver,
                sema: sema
            )
            guard case let .functionType(functionType) = sema.types.kind(of: parameterType) else {
                return nil
            }
            return LambdaParameterCandidate(
                originalType: parameterType,
                functionType: functionType
            )
        }
    }

    private func sharedLambdaInputOnlyType(
        from candidates: [LambdaParameterCandidate],
        types: TypeSystem
    ) -> TypeID? {
        guard let first = candidates.first else {
            return nil
        }
        let sharedInputs = candidates.dropFirst().allSatisfy { candidate in
            functionTypesShareInputShape(first.functionType, candidate.functionType)
        }
        guard sharedInputs else {
            return nil
        }
        return types.make(.functionType(FunctionType(
            receiver: first.functionType.receiver,
            params: first.functionType.params,
            returnType: types.nullableAnyType,
            isSuspend: first.functionType.isSuspend,
            nullability: first.functionType.nullability
        )))
    }

    private func functionTypesShareInputShape(
        _ lhs: FunctionType,
        _ rhs: FunctionType
    ) -> Bool {
        guard lhs.isSuspend == rhs.isSuspend,
              lhs.params.count == rhs.params.count,
              lhs.receiver == rhs.receiver
        else {
            return false
        }
        return zip(lhs.params, rhs.params).allSatisfy { $0 == $1 }
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
        args: [CallArgument],
        callRange: SourceRange,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        guard case let .functionType(argumentFunctionType) = sema.types.kind(of: argType) else {
            return candidateSymbols
        }

        return candidateSymbols.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = lambdaParameterTypeForArgument(
                      at: lambdaArgumentIndex,
                      args: args,
                      callRange: callRange,
                      in: signature,
                      ctx: ctx
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

    private func lambdaBodyUsesImplicitIt(
        _ lambdaExprID: ExprID,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard case let .lambdaLiteral(_, body, _, _) = ctx.ast.arena.expr(lambdaExprID) else {
            return false
        }
        var visited: Set<Int32> = []
        return expressionUsesImplicitIt(body, ctx: ctx, visited: &visited)
    }

    private func lambdaBodyIsNullLiteral(
        _ lambdaExprID: ExprID,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard case let .lambdaLiteral(_, body, _, _) = ctx.ast.arena.expr(lambdaExprID),
              case .nullLiteral = ctx.ast.arena.expr(body)
        else {
            return false
        }
        return true
    }

    // A no-arrow lambda only has an unresolvable implicit parameter when its
    // body actually references `it`; `{ null }` is a zero-parameter producer.
    private func expressionUsesImplicitIt(
        _ exprID: ExprID,
        ctx: TypeInferenceContext,
        visited: inout Set<Int32>
    ) -> Bool {
        guard visited.insert(exprID.rawValue).inserted,
              let expr = ctx.ast.arena.expr(exprID)
        else {
            return false
        }
        func visit(_ child: ExprID) -> Bool {
            return self.expressionUsesImplicitIt(child, ctx: ctx, visited: &visited)
        }
        switch expr {
        case let .nameRef(name, _):
            return name == ctx.interner.intern("it")
        case let .stringTemplate(parts, _):
            return parts.contains { part in
                if case let .expression(child) = part { return visit(child) }
                return false
            }
        case let .forExpr(_, iterable, body, _, _):
            return visit(iterable) || visit(body)
        case let .whileExpr(condition, body, _, _):
            return visit(condition) || visit(body)
        case let .doWhileExpr(body, condition, _, _):
            return visit(body) || visit(condition)
        case let .localDecl(_, _, _, initializer, _, _):
            return initializer.map(visit) ?? false
        case let .localAssign(_, value, _):
            return visit(value)
        case let .memberAssign(receiver, _, value, _):
            return visit(receiver) || visit(value)
        case let .indexedAssign(receiver, indices, value, _):
            return visit(receiver) || indices.contains(where: visit) || visit(value)
        case let .call(callee, _, args, _):
            return visit(callee) || args.contains { visit($0.expr) }
        case let .memberCall(receiver, _, _, args, _):
            return visit(receiver) || args.contains { visit($0.expr) }
        case let .indexedAccess(receiver, indices, _):
            return visit(receiver) || indices.contains(where: visit)
        case let .binary(_, lhs, rhs, _):
            return visit(lhs) || visit(rhs)
        case let .whenExpr(subject, branches, elseExpr, _):
            return (subject.map(visit) ?? false)
                || branches.contains { branch in
                    branch.conditions.contains(where: visit)
                        || (branch.guard_.map(visit) ?? false)
                        || visit(branch.body)
                }
                || (elseExpr.map(visit) ?? false)
        case let .returnExpr(value, _, _):
            return value.map(visit) ?? false
        case let .ifExpr(condition, thenExpr, elseExpr, _):
            return visit(condition) || visit(thenExpr) || (elseExpr.map(visit) ?? false)
        case let .tryExpr(body, catchClauses, finallyExpr, _):
            return visit(body)
                || catchClauses.contains { visit($0.body) }
                || (finallyExpr.map(visit) ?? false)
        case let .unaryExpr(_, operand, _), let .nullAssert(operand, _):
            return visit(operand)
        case let .isCheck(value, _, _, _), let .asCast(value, _, _, _):
            return visit(value)
        case let .safeMemberCall(receiver, _, _, args, _):
            return visit(receiver) || args.contains { visit($0.expr) }
        case let .compoundAssign(_, _, value, _):
            return visit(value)
        case let .indexedCompoundAssign(_, receiver, indices, value, _):
            return visit(receiver) || indices.contains(where: visit) || visit(value)
        case let .memberCompoundAssign(_, receiver, _, value, _):
            return visit(receiver) || visit(value)
        case let .throwExpr(value, _):
            return visit(value)
        case .lambdaLiteral, .localFunDecl:
            return false
        case let .callableRef(receiver, _, _):
            return receiver.map(visit) ?? false
        case let .blockExpr(statements, trailingExpr, _):
            return statements.contains(where: visit) || (trailingExpr.map(visit) ?? false)
        case let .inExpr(lhs, rhs, _), let .notInExpr(lhs, rhs, _):
            return visit(lhs) || visit(rhs)
        case let .destructuringDecl(_, _, initializer, _):
            return visit(initializer)
        case let .forDestructuringExpr(_, iterable, body, _):
            return visit(iterable) || visit(body)
        case let .objectLiteral(_, declID, _):
            guard let declID,
                  let decl = ctx.ast.arena.decl(declID),
                  case let .objectDecl(objectDecl) = decl
            else {
                return false
            }
            return objectDecl.memberProperties.contains { propertyID in
                guard let property = ctx.ast.arena.decl(propertyID),
                      case let .propertyDecl(propertyDecl) = property,
                      let initializer = propertyDecl.initializer
                else { return false }
                return visit(initializer)
            }
        case let .localNominalDecl(declID, _):
            // KUU-555: an implicit `it` can only reach a local nominal through
            // expressions evaluated in the enclosing scope — supertype ctor
            // args for a local `object`, plus member property initializers
            // for both kinds.
            guard let decl = ctx.ast.arena.decl(declID) else {
                return false
            }
            let rootExprs: [ExprID]
            switch decl {
            case let .objectDecl(objectDecl):
                rootExprs = objectDecl.superTypeConstructorArgs.map(\.expr)
                    + objectDecl.memberProperties.compactMap { propertyID in
                        guard let property = ctx.ast.arena.decl(propertyID),
                              case let .propertyDecl(propertyDecl) = property
                        else { return nil }
                        return propertyDecl.initializer
                    }
            case let .classDecl(classDecl):
                rootExprs = classDecl.superTypeEntries
                    .flatMap(\.constructorArgs).map(\.expr)
                    + classDecl.memberProperties.compactMap { propertyID in
                        guard let property = ctx.ast.arena.decl(propertyID),
                              case let .propertyDecl(propertyDecl) = property
                        else { return nil }
                        return propertyDecl.initializer
                    }
            default:
                rootExprs = []
            }
            return rootExprs.contains(where: visit)
        case .nullLiteral, .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral,
             .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral,
             .stringLiteral, .breakExpr, .continueExpr,
             .superRef, .thisRef:
            return false
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
