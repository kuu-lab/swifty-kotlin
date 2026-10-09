/// Helpers split from `CallTypeChecker.swift`:
/// Re-inference of nested generic call arguments whose element type collapsed
/// to `Nothing`, or whose own resolution failed outright, before the
/// enclosing call's constraint set was known.
///
/// Argument type checking is eager: `mutableListOf()` infers
/// `MutableList<Nothing>` with no expected type, and that `Nothing` then
/// poisons the enclosing call's constraints (`C : MutableCollection<in T>`
/// cannot be satisfied) or fails the post-solve bound check. kotlinc keeps
/// the nested call's type variable in the outer constraint set instead, so
/// `collectInto(mutableListOf(), 1)` infers `MutableList<Int>`.
///
/// A nested call can also fail entirely when a type parameter only appears
/// in positions the expected type would fix: `D(t, 1)` inside
/// `W1(D(t, 1), 0)` cannot infer `R` on its own and reports
/// `KSWIFTK-SEMA-INFER`, leaving the argument typed `error`. The partial
/// substitution probed from the nested call's own arguments (`D<T, R>` with
/// `T` bound from `t`) still lets the outer parameter `D<T, T>` bind its
/// variable from the resolved side, after which `R` is re-inferred as `T`.
///
/// The failed-resolution retry below recovers nested type arguments that
/// collapsed to `Nothing` or the error marker by deriving an expected type
/// from the candidate's partially substituted parameter or declared bound.
/// The candidate-specific path handles a different case: multiple outer
/// overloads may provide different concrete expected types for the same
/// inferable nested call.
struct CandidateSpecificNestedCallArgumentTypes {
    let argumentTypesByCandidate: [SymbolID: [Int: TypeID]]
    let expectedTypesByCandidate: [SymbolID: [Int: TypeID]]
}

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

    /// Whether `type` contains the error marker anywhere inside its generic
    /// arguments — the residue of a nested call whose own inference failed
    /// (e.g. `D(t, 1)` reporting `KSWIFTK-SEMA-INFER` before the enclosing
    /// call's expected type was known).
    func typeContainsErrorType(_ type: TypeID, sema: SemaModule, depth: Int = 0) -> Bool {
        guard depth < 8 else {
            return false
        }
        if type == sema.types.errorType {
            return true
        }
        switch sema.types.kind(of: type) {
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return typeContainsErrorType(inner, sema: sema, depth: depth + 1)
                case .star:
                    return false
                }
            }
        case let .intersection(parts):
            return parts.contains { typeContainsErrorType($0, sema: sema, depth: depth + 1) }
        case let .functionType(functionType):
            return functionType.params.contains { typeContainsErrorType($0, sema: sema, depth: depth + 1) }
                || typeContainsErrorType(functionType.returnType, sema: sema, depth: depth + 1)
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

    /// Re-infer a nested call against each concrete outer overload parameter so
    /// overload resolution can test each candidate with its own contextual type.
    /// This avoids eliminating candidates from one eagerly inferred argument type.
    func candidateSpecificNestedCallArgumentTypes(
        candidates: [SymbolID],
        args: [CallArgument],
        originalExpectedTypeOverrides: [Int: TypeID],
        lambdaLiteralIndices: Set<Int>,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> CandidateSpecificNestedCallArgumentTypes? {
        guard candidates.count > 1 else {
            return nil
        }
        let nestedArgumentIndices = args.indices.filter { index in
            !lambdaLiteralIndices.contains(index)
                && !args[index].isSpread
                && isInferableNestedCallExpr(args[index].expr, ast: ctx.ast)
        }
        guard !nestedArgumentIndices.isEmpty else {
            return nil
        }

        var expectedTypesByCandidate: [SymbolID: [Int: TypeID]] = [:]
        for candidate in candidates {
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
                return nil
            }
            let typeVarBySymbol = ctx.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var candidateExpectedTypes: [Int: TypeID] = [:]
            for index in nestedArgumentIndices {
                guard let parameterIndex = parameterIndexForCallArgument(
                    at: index,
                    label: args[index].label,
                    in: signature,
                    sema: ctx.sema
                ), parameterIndex < signature.parameterTypes.count else {
                    return nil
                }
                let expectedType = signature.parameterTypes[parameterIndex]
                guard expectedType != ctx.sema.types.errorType,
                      !ctx.resolver.containsTypeVariable(
                          expectedType,
                          typeVarBySymbol: typeVarBySymbol,
                          typeSystem: ctx.sema.types
                      )
                else {
                    return nil
                }
                candidateExpectedTypes[index] = expectedType
            }
            expectedTypesByCandidate[candidate] = candidateExpectedTypes
        }

        let hasCandidateSpecificExpectation = nestedArgumentIndices.contains { index in
            var distinctTypes: [TypeID] = []
            for candidate in candidates {
                guard let type = expectedTypesByCandidate[candidate]?[index],
                      !distinctTypes.contains(type)
                else {
                    continue
                }
                distinctTypes.append(type)
            }
            return distinctTypes.count > 1
        }
        guard hasCandidateSpecificExpectation else {
            return nil
        }

        var argumentTypesByCandidate: [SymbolID: [Int: TypeID]] = [:]
        for candidate in candidates {
            guard let candidateExpectedTypes = expectedTypesByCandidate[candidate] else {
                return nil
            }
            var candidateArgumentTypes: [Int: TypeID] = [:]
            for index in nestedArgumentIndices {
                guard let expectedType = candidateExpectedTypes[index] else {
                    return nil
                }
                let checkpoint = ctx.semaCtx.diagnostics.checkpoint()
                var candidateLocals = locals
                let argumentType = driver.inferExpr(
                    args[index].expr,
                    ctx: ctx,
                    locals: &candidateLocals,
                    expectedType: expectedType
                )
                let emittedError = ctx.semaCtx.diagnostics.diagnostics.dropFirst(checkpoint).contains {
                    $0.severity == .error
                }
                ctx.semaCtx.diagnostics.rollback(to: checkpoint)
                guard !emittedError,
                      argumentType != ctx.sema.types.errorType,
                      !typeContainsErrorType(argumentType, sema: ctx.sema)
                else {
                    for restoreIndex in nestedArgumentIndices {
                        var restoreLocals = locals
                        _ = driver.inferExpr(
                            args[restoreIndex].expr,
                            ctx: ctx,
                            locals: &restoreLocals,
                            expectedType: originalExpectedTypeOverrides[restoreIndex]
                        )
                    }
                    return nil
                }
                candidateArgumentTypes[index] = argumentType
            }
            argumentTypesByCandidate[candidate] = candidateArgumentTypes
        }
        return CandidateSpecificNestedCallArgumentTypes(
            argumentTypesByCandidate: argumentTypesByCandidate,
            expectedTypesByCandidate: expectedTypesByCandidate
        )
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

    /// A best-effort partial type for a nested call whose own resolution
    /// failed (its recorded expression type is the error marker). Probes the
    /// nested callee's own arguments and substitutes what they already prove,
    /// keeping the callee's still-unresolved type parameters in place:
    /// `D(t, 1)` with `t: T` yields `D<T, R>` where `R` stays a parameter.
    ///
    /// The enclosing candidate can then decompose that partial type against
    /// its parameter (`D<T, T>`) and bind the positions the nested call did
    /// resolve, which is what a unified constraint system would see. The
    /// returned `unboundTypeVarBySymbol` marks the nested callee parameters
    /// left unresolved — constraints mentioning them equate a free variable
    /// with an enclosing one and must be dropped before solving.
    /// Returns nil for member calls and for candidates that cannot produce a
    /// partial type.
    func partiallyInferredNestedCallType(
        _ expr: ExprID,
        ctx: TypeInferenceContext
    ) -> (type: TypeID, unboundTypeVarBySymbol: [SymbolID: TypeVarID])? {
        let sema = ctx.sema
        let ast = ctx.ast
        guard case let .call(calleeID, _, nestedArgs, _) = ast.arena.expr(expr),
              case let .nameRef(calleeName, _) = ast.arena.expr(calleeID)
        else {
            return nil
        }
        // A callee name can resolve to the class symbol rather than its
        // constructors (`D(t, 1)` looks up `D`, the class), so expand nominal
        // symbols into their `<init>` overloads the way `inferCallExpr` does.
        let nameMatches = ctx.cachedScopeLookup(calleeName)
        var nestedCandidates = ctx.filterByVisibility(
            nameMatches.filter { candidate in
                let kind = ctx.cachedSymbol(candidate)?.kind
                return kind == .function || kind == .constructor
            }
        ).visible
        for symbolID in nameMatches {
            guard let symbol = ctx.cachedSymbol(symbolID),
                  symbol.kind == .class || symbol.kind == .enumClass,
                  !symbol.flags.contains(.abstractType)
            else {
                continue
            }
            let initName = ctx.interner.intern("<init>")
            nestedCandidates += ctx.filterByVisibility(
                sema.symbols.lookupAll(fqName: symbol.fqName + [initName])
            ).visible
        }
        for candidate in nestedCandidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  !signature.typeParameterSymbols.isEmpty
            else {
                continue
            }
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var knownArgumentTypes: [Int: TypeID] = [:]
            for (index, nestedArg) in nestedArgs.enumerated() {
                guard let parameterIndex = parameterIndexForCallArgument(
                    at: index,
                    label: nestedArg.label,
                    in: signature,
                    sema: sema
                ),
                    let argumentType = sema.bindings.exprType(for: nestedArg.expr),
                    argumentType != sema.types.errorType
                else {
                    continue
                }
                knownArgumentTypes[parameterIndex] = argumentType
            }
            let partialSubstitution = ctx.resolver.probeArgumentTypeSubstitution(
                signature: signature,
                typeVarBySymbol: typeVarBySymbol,
                knownArgumentTypes: knownArgumentTypes,
                typeSystem: sema.types,
                blameRange: ast.arena.exprRange(expr)
            )
            let partialType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: partialSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            var unboundTypeVarBySymbol: [SymbolID: TypeVarID] = [:]
            for symbol in signature.typeParameterSymbols {
                guard let variable = typeVarBySymbol[symbol] else { continue }
                if partialSubstitution[variable] == nil {
                    unboundTypeVarBySymbol[symbol] = variable
                }
            }
            return (partialType, unboundTypeVarBySymbol)
        }
        return nil
    }

    /// Whether either operand of `constraint` is a type that still mentions
    /// one of the nested callee's unresolved type parameters. Such a
    /// constraint would equate a free variable with an enclosing candidate's
    /// variable, so it is not usable as outer inference evidence.
    private func constraintMentionsUnboundNestedParameters(
        _ constraint: VariableConstraint,
        unboundTypeVarBySymbol: [SymbolID: TypeVarID],
        ctx: TypeInferenceContext
    ) -> Bool {
        func mentions(_ operand: ConstraintOperand) -> Bool {
            guard case let .type(type) = operand else { return false }
            return ctx.resolver.containsTypeVariable(
                type,
                typeVarBySymbol: unboundTypeVarBySymbol,
                typeSystem: ctx.sema.types
            )
        }
        return mentions(constraint.left) || mentions(constraint.right)
    }

    /// Retry overload resolution after re-inferring nested-call arguments
    /// whose inferred type still contains `Nothing` or failed outright.
    ///
    /// Only invoked after the first resolution produced a diagnostic. Each
    /// candidate contributes a partial substitution probed from the
    /// non-deferred arguments plus the resolved positions of any
    /// failed nested call; deferred arguments are then re-inferred under
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
                  typeContainsNothingType(argTypes[index], sema: sema)
                      || typeContainsErrorType(argTypes[index], sema: sema),
                  isInferableNestedCallExpr(argument.expr, ast: ast)
            else {
                continue
            }
            deferredIndices.append(index)
        }
        guard !deferredIndices.isEmpty else {
            return nil
        }
        // Nested calls that failed their first pass carry no usable argument
        // type; probe their own arguments once per call so every candidate's
        // parameter position can still constrain the outer type variables
        // the resolved positions align with.
        var nestedEvidence: [Int: (type: TypeID, unboundTypeVarBySymbol: [SymbolID: TypeVarID])] = [:]
        for index in deferredIndices where typeContainsErrorType(argTypes[index], sema: sema) {
            if let evidence = partiallyInferredNestedCallType(args[index].expr, ctx: ctx) {
                nestedEvidence[index] = evidence
            }
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
            var partialSubstitution = ctx.resolver.probeArgumentTypeSubstitution(
                signature: signature,
                typeVarBySymbol: typeVarBySymbol,
                knownArgumentTypes: knownArgumentTypes,
                typeSystem: sema.types,
                blameRange: range,
                implicitReceiverType: implicitReceiverType
            )
            // Fold in the resolved positions of each failed nested call:
            // `D<T, R>` against parameter `D<T, T>` binds the outer `T` from
            // the nested call's own evidence. Positions still held by the
            // nested callee's unbound parameters are dropped — they would
            // equate a free variable with the enclosing one.
            for (index, evidence) in nestedEvidence {
                guard let parameterIndex = parameterIndexForCallArgument(
                    at: index,
                    label: args[index].label,
                    in: signature,
                    sema: sema
                ), parameterIndex < signature.parameterTypes.count else {
                    continue
                }
                let evidenceConstraints = ctx.resolver.decomposeSubtypeConstraint(
                    subtype: evidence.type,
                    supertype: signature.parameterTypes[parameterIndex],
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: sema.types,
                    blameRange: range
                ).filter {
                    !constraintMentionsUnboundNestedParameters(
                        $0,
                        unboundTypeVarBySymbol: evidence.unboundTypeVarBySymbol,
                        ctx: ctx
                    )
                }
                guard !evidenceConstraints.isEmpty else {
                    continue
                }
                let evidenceSolution = ConstraintSolver().solve(
                    vars: ctx.resolver.usedTypeVariables(from: evidenceConstraints),
                    constraints: evidenceConstraints,
                    typeSystem: sema.types
                )
                guard evidenceSolution.isSuccess else {
                    continue
                }
                for (variable, boundType) in evidenceSolution.substitution
                where partialSubstitution[variable] == nil && boundType != sema.types.errorType {
                    partialSubstitution[variable] = boundType
                }
            }
            let diagnosticsCheckpoint = ctx.semaCtx.diagnostics.checkpoint()
            var retryArgTypes = argTypes
            var reinferredIndices: [Int] = []
            for index in deferredIndices {
                guard let parameterIndex = parameterIndexForCallArgument(
                    at: index,
                    label: args[index].label,
                    in: signature,
                    sema: sema
                ), parameterIndex < signature.parameterTypes.count,
                   let expectedArgumentType = deferredArgumentExpectedType(
                       parameterType: signature.parameterTypes[parameterIndex],
                       argumentType: nestedEvidence[index]?.type ?? argTypes[index],
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
                reinferredIndices.append(index)
            }
            guard !reinferredIndices.isEmpty else {
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
                // The re-inferred arguments succeeded, so the failed first
                // pass's diagnostics inside their ranges (e.g. the nested
                // call's `KSWIFTK-SEMA-INFER`) are stale — drop them.
                for index in reinferredIndices {
                    if let argumentRange = ast.arena.exprRange(args[index].expr) {
                        ctx.semaCtx.diagnostics.removeErrorDiagnostics(containedIn: argumentRange)
                    }
                }
                return retried
            }
            ctx.semaCtx.diagnostics.rollback(to: diagnosticsCheckpoint)
        }
        return nil
    }
}
