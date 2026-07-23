
extension CallTypeChecker {
    struct PreparedCallArguments {
        let argTypes: [TypeID]
        let lambdaLiteralIndices: Set<Int>
        let inputOnlyLambdaIndices: Set<Int>
        let blockedLambdaRefinement: Bool
    }

    private struct LambdaParameterCandidate {
        let originalType: TypeID
        let functionType: FunctionType
    }

    func prepareCallArguments(
        args: [CallArgument],
        candidates: [SymbolID],
        preInferredNonLambdaArgTypes: [Int: TypeID] = [:],
        expectedTypeOverrides: [Int: TypeID] = [:],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> PreparedCallArguments {
        let ast = ctx.ast
        let sema = ctx.sema

        var inferredNonLambdaArgTypes = preInferredNonLambdaArgTypes
        var lambdaLiteralIndices: Set<Int> = []
        var inputOnlyLambdaIndices: Set<Int> = []
        var blockedLambdaRefinement = false
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
                if inferredNonLambdaArgTypes[index] != nil {
                    continue
                }
                // An unsuffixed int literal must see the candidates' parameter
                // type (e.g. Long) before inference, or it defaults to Int and
                // every candidate rejects it (`Millis(1500)` with `value: Long`).
                let literalExpectedType = uniformNumericLiteralParameterType(
                    at: index,
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
                inferredNonLambdaArgTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
            }
        }

        for (index, argument) in args.enumerated() {
            if let override = expectedTypeOverrides[index] {
                contextualArgExpectedTypes[index] = override
                continue
            }

            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            let narrowedCandidates = narrowedCallCandidates(
                candidates: candidates,
                args: args,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                ctx: ctx
            )
            let expectedTypeCandidates = narrowedCandidates.isEmpty ? candidates : narrowedCandidates

            switch argumentExpr {
            case .callableRef:
                contextualArgExpectedTypes[index] = callableReferenceExpectedType(
                    at: index,
                    candidates: expectedTypeCandidates,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                )
            case .lambdaLiteral:
                let expectation = lambdaLiteralExpectedType(
                    at: index,
                    candidates: expectedTypeCandidates,
                    explicitTypeArgs: explicitTypeArgs,
                    receiverType: receiverType,
                    inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                    resolver: ctx.resolver,
                    sema: sema
                )
                contextualArgExpectedTypes[index] = expectation.type
                if expectation.isInputOnly {
                    inputOnlyLambdaIndices.insert(index)
                }
                if expectation.blocksRefinement {
                    blockedLambdaRefinement = true
                }
            default:
                continue
            }
        }

        if lambdaLiteralIndices.count > 1 {
            blockedLambdaRefinement = true
        }

        let argTypes = args.enumerated().map { index, argument -> TypeID in
            if let contextualExpectedType = contextualArgExpectedTypes[index] {
                let inferredType = driver.inferExpr(
                    argument.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: contextualExpectedType
                )
                if inputOnlyLambdaIndices.contains(index) {
                    return rebuildLambdaLiteralType(
                        exprID: argument.expr,
                        inferredType: inferredType,
                        contextualExpectedType: contextualExpectedType,
                        sema: sema
                    )
                }
                return inferredType
            }
            if let cached = inferredNonLambdaArgTypes[index] {
                return cached
            }
            return driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }

        return PreparedCallArguments(
            argTypes: argTypes,
            lambdaLiteralIndices: lambdaLiteralIndices,
            inputOnlyLambdaIndices: inputOnlyLambdaIndices,
            blockedLambdaRefinement: blockedLambdaRefinement
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
        lambdaLiteralIndices: Set<Int>,
        inputOnlyLambdaIndices: Set<Int>,
        blockedLambdaRefinement: Bool,
        ctx: TypeInferenceContext
    ) -> ResolvedCall {
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let call = CallExpr(
            range: range,
            calleeName: calleeName,
            args: resolvedArgs,
            explicitTypeArgs: explicitTypeArgs
        )

        let hasRefinementAnnotation = candidates.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        })
        let functionParameterArgumentPositions = Set(args.indices.filter { argIndex in
            candidates.contains { candidate in
                guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                      let parameterType = parameterTypeForArgument(at: argIndex, in: signature)
                else {
                    return false
                }
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

        if blockedLambdaRefinement, hasRefinementAnnotation {
            return ambiguousCallResult(range: range)
        }

        let contextualExpectedType = overloadResolutionExpectedType(from: expectedType, sema: ctx.sema)

        guard !inputOnlyLambdaIndices.isEmpty else {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: contextualExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }

        // These ambiguity checks only apply when lambda-return-type overload
        // resolution is actually attempted (inputOnlyLambdaIndices is non-empty).
        // Running them earlier would incorrectly reject single-candidate calls.
        if functionParameterArgumentPositions.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range)
        }
        if functionTypedArgumentIndices.count > 1, hasRefinementAnnotation {
            return ambiguousCallResult(range: range)
        }

        let overloadResolutionExpectedType: TypeID? = nil

        let probe = ctx.resolver.probeCall(
            candidates: candidates,
            call: call,
            expectedType: overloadResolutionExpectedType,
            implicitReceiverType: implicitReceiverType,
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
                ctx: ctx.semaCtx
            )
        }
        if viableSymbols.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        guard lambdaLiteralIndices.count == 1,
              let lambdaIndex = lambdaLiteralIndices.first,
              inputOnlyLambdaIndices.contains(lambdaIndex)
        else {
            return ambiguousCallResult(range: range)
        }
        // When all viable candidates share the same input-only HOF link name (e.g.
        // String.zip and CharSequence.zip both map to kk_string_zipTransform), the
        // apparent ambiguity is structural — not semantic. Fall back to the standard
        // resolver which picks the most specific receiver type (String over CharSequence).
        if viableSymbols.allSatisfy({
            Self.inputOnlyExternalLinkNames.contains(ctx.sema.symbols.externalLinkName(for: $0) ?? "")
        }) {
            return ctx.resolver.resolveCall(
                candidates: viableSymbols,
                call: call,
                expectedType: contextualExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        guard viableSymbols.contains(where: {
            hasOverloadResolutionByLambdaReturnTypeAnnotation(symbol: $0, sema: ctx.sema)
        }) else {
            return ambiguousCallResult(range: range)
        }

        let refinedCandidates = refineCandidatesByLambdaReturnType(
            candidateSymbols: viableSymbols,
            lambdaArgumentIndex: lambdaIndex,
            argType: argTypes[lambdaIndex],
            sema: ctx.sema
        )
        if refinedCandidates.isEmpty {
            return ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        if refinedCandidates.count == 1 {
            return ctx.resolver.resolveCall(
                candidates: refinedCandidates,
                call: call,
                expectedType: overloadResolutionExpectedType,
                implicitReceiverType: implicitReceiverType,
                ctx: ctx.semaCtx
            )
        }
        return ambiguousCallResult(range: range)
    }

    func overloadResolutionExpectedType(from expectedType: TypeID?, sema: SemaModule) -> TypeID? {
        // Unit contexts accept and discard any expression result, so Unit must
        // not act as a return-type constraint while choosing an overload.
        guard expectedType != sema.types.unitType else {
            return nil
        }
        return expectedType
    }

    /// Returns the expected numeric type (Long/UInt/ULong) for an unsuffixed
    /// int-literal argument if every candidate agrees on that parameter being
    /// one of those types, so the literal can be widened before overload
    /// resolution instead of defaulting to Int and rejecting every candidate.
    /// Returns nil (leaving the literal as Int) when candidates disagree or
    /// none expect a wideable numeric type — the normal Int-literal path and
    /// existing overload resolution still handle those cases.
    private func uniformNumericLiteralParameterType(
        at index: Int,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> TypeID? {
        var result: TypeID?
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = parameterTypeForArgument(at: index, in: signature)
            else {
                return nil
            }
            let nonNullParameterType = sema.types.makeNonNullable(parameterType)
            guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullParameterType),
                  primitive == .long || primitive == .uint || primitive == .ulong
            else {
                return nil
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
        inferredNonLambdaArgTypes: [Int: TypeID],
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let narrowed = candidates.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count)
            else {
                return false
            }
            for (otherIndex, inferredType) in inferredNonLambdaArgTypes {
                guard let parameterType = parameterTypeForArgument(at: otherIndex, in: signature) else {
                    return false
                }
                if !sema.types.isSubtype(inferredType, parameterType) {
                    return false
                }
            }
            return true
        }
        return narrowed.isEmpty ? candidates : narrowed
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

    /// Substitutes the class type parameters used in `signature.receiverType`
    /// with the concrete generic arguments of the call-site `receiverType`. This
    /// lets trailing-lambda expected types be computed with the receiver's
    /// generic substitutions already applied, so `it` in `xs.map { it * 10 }`
    /// is seen as `Int` rather than `T`.
    private func applyReceiverClassTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard sema.symbols.symbol(candidate)?.kind != .constructor,
              !signature.typeParameterSymbols.isEmpty,
              let signatureReceiverType = signature.receiverType,
              let callSiteReceiverType = receiverType,
              let declaredClass = resolveClassType(signatureReceiverType, sema: sema),
              let callSiteClass = resolveClassType(callSiteReceiverType, sema: sema),
              declaredClass.classSymbol == callSiteClass.classSymbol,
              declaredClass.args.count == callSiteClass.args.count
        else {
            return parameterType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for index in 0 ..< declaredClass.args.count {
            let declaredArg: TypeID
            switch declaredClass.args[index] {
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
            let concreteType: TypeID = switch callSiteClass.args[index] {
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
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        sema: SemaModule
    ) -> TypeID? {
        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           index < signature.parameterTypes.count
        {
            let rawType = signature.parameterTypes[index]
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
                  index < signature.parameterTypes.count
            else {
                continue
            }
            let parameterType = signature.parameterTypes[index]
            if driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil {
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
        "kk_string_zipTransform",
        "kk_string_zipTransform_flat",
        "kk_string_zipWithNextTransform",
        "kk_string_zipWithNextTransform_flat",
        "kk_string_chunked_sequence_transform",
        "kk_string_windowedSequence_transform",
    ]

    private func lambdaLiteralExpectedType(
        at index: Int,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        sema: SemaModule
    ) -> (type: TypeID?, isInputOnly: Bool, blocksRefinement: Bool) {
        // When all candidates share the same input-only HOF link name (e.g. String and
                // CharSequence overloads of zip both map to kk_string_zipTransform), pick the
        // first candidate and treat the lambda as input-only so that its return type is
        // not used for constraint solving — matches what the single-candidate path does.
        if !candidates.isEmpty,
           candidates.allSatisfy({
               Self.inputOnlyExternalLinkNames.contains(sema.symbols.externalLinkName(for: $0) ?? "")
           }),
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           index < signature.parameterTypes.count
        {
            let rawType = signature.parameterTypes[index]
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
            let substituted = applyReceiverClassTypeArgs(
                to: explicitSubstituted,
                signature: signature,
                candidate: candidates[0],
                receiverType: receiverType,
                sema: sema
            )
            return (substituted, true, false)
        }

        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           index < signature.parameterTypes.count
        {
            let rawType = signature.parameterTypes[index]
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
            let substituted = applyInferredArgumentTypeArgs(
                to: receiverSubstituted,
                signature: signature,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                resolver: resolver,
                sema: sema
            )
            return (substituted, false, false)
        }

        let parameterCandidates = lambdaParameterCandidates(
            at: index,
            candidates: candidates,
            sema: sema
        )
        guard !parameterCandidates.isEmpty else {
            return (nil, false, false)
        }

        if let first = parameterCandidates.first,
           parameterCandidates.dropFirst().allSatisfy({ $0.originalType == first.originalType })
        {
            return (first.originalType, false, false)
        }

        guard let sharedType = sharedLambdaInputOnlyType(
            from: parameterCandidates,
            types: sema.types
        ) else {
            return (nil, false, parameterCandidates.count > 1)
        }
        return (sharedType, true, false)
    }

    private func lambdaParameterCandidates(
        at index: Int,
        candidates: [SymbolID],
        sema: SemaModule
    ) -> [LambdaParameterCandidate] {
        candidates.compactMap { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  index < signature.parameterTypes.count
            else {
                return nil
            }
            let parameterType = signature.parameterTypes[index]
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
            returnType: types.anyType,
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
        sema: SemaModule
    ) -> [SymbolID] {
        guard case let .functionType(argumentFunctionType) = sema.types.kind(of: argType) else {
            return candidateSymbols
        }

        return candidateSymbols.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterType = parameterTypeForArgument(at: lambdaArgumentIndex, in: signature),
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

    private func ambiguousCallResult(range: SourceRange) -> ResolvedCall {
        ResolvedCall(
            chosenCallee: nil,
            substitutedTypeArguments: [:],
            parameterMapping: [:],
            diagnostic: Diagnostic(
                severity: .error,
                code: "KSWIFTK-SEMA-0003",
                message: "Ambiguous overload resolution.",
                primaryRange: range,
                secondaryRanges: []
            )
        )
    }
}
