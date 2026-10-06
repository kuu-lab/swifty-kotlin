/// Helpers split from `CallTypeChecker.swift`:
/// Re-inference of nested generic call arguments whose element type collapsed
/// to `Nothing` before the enclosing call's constraint set was known.
///
/// Argument type checking is eager: `mutableListOf()` infers
/// `MutableList<Nothing>` with no expected type, and that `Nothing` then
/// poisons the enclosing call's constraints (`C : MutableCollection<in T>`
/// cannot be satisfied) or fails the post-solve bound check. kotlinc keeps
/// the nested call's type variable in the outer constraint set instead, so
/// `collectInto(mutableListOf(), 1)` infers `MutableList<Int>`.
///
/// The helpers here recover the same result at the TypeCheck layer: when a
/// call fails to resolve, find arguments that are still-inferable nested
/// calls (no explicit type arguments) whose inferred type contains
/// `Nothing`, derive their expected type from the candidate's partially
/// substituted parameter or that parameter's declared bound, re-infer the
/// argument expression, and resolve once more. The retry only runs after a
/// failed resolution, so calls that already work are unaffected.
extension CallTypeChecker {
    /// Whether `type` contains `Nothing` anywhere inside its generic
    /// arguments (e.g. `MutableList<Nothing>`), which marks an uninferred
    /// nested type argument.
    func typeContainsNothingType(_ type: TypeID, sema: SemaModule, depth: Int = 0) -> Bool {
        guard depth < 8 else {
            return false
        }
        switch sema.types.kind(of: type) {
        case .nothing:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return typeContainsNothingType(inner, sema: sema, depth: depth + 1)
                case .star:
                    return false
                }
            }
        case let .intersection(parts):
            return parts.contains { typeContainsNothingType($0, sema: sema, depth: depth + 1) }
        case let .functionType(functionType):
            return functionType.params.contains { typeContainsNothingType($0, sema: sema, depth: depth + 1) }
                || typeContainsNothingType(functionType.returnType, sema: sema, depth: depth + 1)
        default:
            return false
        }
    }

    /// Whether `expr` is a nested call whose type arguments were inferred
    /// (empty explicit type argument list), meaning it can still be steered
    /// by an expected type — unlike `mutableListOf<Nothing>()`, where the
    /// explicit argument must be respected.
    func isInferableNestedCallExpr(_ expr: ExprID, ast: ASTModule) -> Bool {
        guard let argumentExpr = ast.arena.expr(expr) else {
            return false
        }
        switch argumentExpr {
        case let .call(_, typeArgs, _, _):
            return typeArgs.isEmpty
        case let .memberCall(_, _, typeArgs, _, _):
            return typeArgs.isEmpty
        default:
            return false
        }
    }

    /// Positional parameter index for a call argument, honoring labeled
    /// arguments and trailing vararg positions. Returns nil when the
    /// argument cannot be mapped to a declared parameter.
    func parameterIndexForCallArgument(
        at index: Int,
        label: InternedString?,
        in signature: FunctionSignature,
        sema: SemaModule
    ) -> Int? {
        if let label {
            for (parameterIndex, parameterSymbol) in signature.valueParameterSymbols.enumerated()
            where sema.symbols.symbol(parameterSymbol)?.name == label {
                return parameterIndex
            }
            return nil
        }
        if index >= 0, index < signature.parameterTypes.count {
            return index
        }
        if let varargIndex = signature.valueParameterIsVararg.firstIndex(of: true),
           index >= varargIndex,
           varargIndex < signature.parameterTypes.count
        {
            return varargIndex
        }
        return nil
    }

    /// Re-parameterizes the nested call's first-pass (Nothing-poisoned) type
    /// with the argument types demanded by `boundType`, keeping the nested
    /// call's own nominal head. E.g. `MutableList<Nothing>` against
    /// `MutableCollection<in Int>` yields `MutableList<Int>` — re-inferring
    /// the nested call with that expected type then produces the same precise
    /// static type kotlinc computes (`val dest = ...mapTo(mutableListOf())`
    /// binds `MutableList<Int>`, not `MutableCollection<in Int>`).
    /// Returns nil when the nested call's nominal cannot satisfy the bound
    /// (e.g. `List` into `MutableCollection`, or `MutableMap` into a
    /// collection destination), so nominal-mismatched arguments keep their
    /// original failure instead of being adopted through the expected-type
    /// collection-factory coercion.
    func concreteNestedCallExpectedType(
        originalArgumentType: TypeID,
        boundType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        guard case let .classType(originalClassType) = sema.types.kind(of: originalArgumentType),
              case let .classType(boundClassType) = sema.types.kind(of: boundType),
              !originalClassType.args.isEmpty,
              originalClassType.args.count == boundClassType.args.count
        else {
            return nil
        }
        var candidateArgs: [TypeArg] = []
        for boundArg in boundClassType.args {
            switch boundArg {
            case let .invariant(inner), let .out(inner), let .in(inner):
                candidateArgs.append(.invariant(inner))
            case .star:
                return nil
            }
        }
        let candidate = sema.types.make(.classType(ClassType(
            classSymbol: originalClassType.classSymbol,
            args: candidateArgs,
            nullability: originalClassType.nullability
        )))
        guard sema.types.isSubtype(candidate, boundType) else {
            return nil
        }
        return candidate
    }

    /// The expected type for a deferred nested-call argument, derived from
    /// the candidate parameter type after applying the substitution inferred
    /// from the call's other arguments. When the substituted parameter is
    /// still a bare type variable (e.g. `C` in `dest: C`), its declared
    /// upper bounds are tried in order (e.g. `MutableCollection<in T>` ->
    /// `MutableCollection<in Int>`); the first fully concrete bound wins.
    /// The resulting bound is then re-parameterized onto the nested call's
    /// own nominal head via `concreteNestedCallExpectedType`.
    /// Returns nil when no concrete expected type can be derived.
    func deferredArgumentExpectedType(
        parameterType: TypeID,
        argumentType: TypeID,
        signature: FunctionSignature,
        partialSubstitution: [TypeVarID: TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let substitutedParameter = sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: partialSubstitution,
            typeVarBySymbol: typeVarBySymbol
        )
        if !ctx.resolver.containsTypeVariable(
            substitutedParameter,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: sema.types
        ) {
            return concreteNestedCallExpectedType(
                originalArgumentType: argumentType,
                boundType: substitutedParameter,
                sema: sema
            )
        }
        guard case let .typeParam(typeParam) = sema.types.kind(of: substitutedParameter),
              let typeParameterIndex = signature.typeParameterSymbols.firstIndex(of: typeParam.symbol)
        else {
            return nil
        }
        let signatureBounds = typeParameterIndex < signature.typeParameterUpperBoundsList.count
            ? signature.typeParameterUpperBoundsList[typeParameterIndex]
            : []
        let symbolBounds = sema.symbols.typeParameterUpperBounds(for: typeParam.symbol)
            .filter { !signatureBounds.contains($0) }
        for upperBound in signatureBounds + symbolBounds {
            let substitutedBound = sema.types.substituteTypeParameters(
                in: upperBound,
                substitution: partialSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            guard !ctx.resolver.containsTypeVariable(
                substitutedBound,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: sema.types
            ) else {
                continue
            }
            return concreteNestedCallExpectedType(
                originalArgumentType: argumentType,
                boundType: substitutedBound,
                sema: sema
            )
        }
        return nil
    }

    /// Retry overload resolution after re-inferring nested-call arguments
    /// whose inferred type still contains `Nothing`.
    ///
    /// Only invoked after the first resolution produced a diagnostic. Each
    /// candidate contributes a partial substitution probed from the
    /// non-deferred arguments; deferred arguments are then re-inferred under
    /// their derived expected types and the full call is resolved once more.
    /// Returns the successful resolution, or nil to keep the original
    /// diagnostic.
    func retryResolutionReinferringNestedCallArguments(
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
        hasUnresolvableImplicitLambdaParameter: Bool,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> ResolvedCall? {
        let sema = ctx.sema
        let ast = ctx.ast
        var deferredIndices: [Int] = []
        for (index, argument) in args.enumerated() {
            guard !lambdaLiteralIndices.contains(index),
                  index < argTypes.count,
                  typeContainsNothingType(argTypes[index], sema: sema),
                  isInferableNestedCallExpr(argument.expr, ast: ast)
            else {
                continue
            }
            deferredIndices.append(index)
        }
        guard !deferredIndices.isEmpty else {
            return nil
        }
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                continue
            }
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var knownArgumentTypes: [Int: TypeID] = [:]
            for (index, type) in argTypes.enumerated() where !deferredIndices.contains(index) {
                guard let parameterIndex = parameterIndexForCallArgument(
                    at: index,
                    label: args[index].label,
                    in: signature,
                    sema: sema
                ), parameterIndex < signature.parameterTypes.count else {
                    continue
                }
                knownArgumentTypes[parameterIndex] = type
            }
            let partialSubstitution = ctx.resolver.probeArgumentTypeSubstitution(
                signature: signature,
                typeVarBySymbol: typeVarBySymbol,
                knownArgumentTypes: knownArgumentTypes,
                typeSystem: sema.types,
                blameRange: range,
                implicitReceiverType: implicitReceiverType
            )
            let diagnosticsCheckpoint = ctx.semaCtx.diagnostics.checkpoint()
            var retryArgTypes = argTypes
            var didReinfer = false
            for index in deferredIndices {
                guard let parameterIndex = parameterIndexForCallArgument(
                    at: index,
                    label: args[index].label,
                    in: signature,
                    sema: sema
                ), parameterIndex < signature.parameterTypes.count,
                   let expectedArgumentType = deferredArgumentExpectedType(
                       parameterType: signature.parameterTypes[parameterIndex],
                       argumentType: argTypes[index],
                       signature: signature,
                       partialSubstitution: partialSubstitution,
                       typeVarBySymbol: typeVarBySymbol,
                       ctx: ctx
                   )
                else {
                    continue
                }
                retryArgTypes[index] = driver.inferExpr(
                    args[index].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: expectedArgumentType
                )
                didReinfer = true
            }
            guard didReinfer else {
                ctx.semaCtx.diagnostics.rollback(to: diagnosticsCheckpoint)
                continue
            }
            let retried = resolveCallRespectingLambdaReturnType(
                candidates: candidates,
                args: args,
                argTypes: retryArgTypes,
                range: range,
                calleeName: calleeName,
                explicitTypeArgs: explicitTypeArgs,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                lambdaLiteralIndices: lambdaLiteralIndices,
                inputOnlyLambdaIndices: inputOnlyLambdaIndices,
                blockedLambdaRefinement: blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: hasUnresolvableImplicitLambdaParameter,
                ctx: ctx
            )
            if retried.diagnostic == nil {
                return retried
            }
            ctx.semaCtx.diagnostics.rollback(to: diagnosticsCheckpoint)
        }
        return nil
    }
}
