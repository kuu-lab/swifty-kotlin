// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Argument-context preparation for `inferCallExpr`: coroutine-launcher
/// detection and lambda ABI marks, then the expected-type and lambda-context
/// overrides that `prepareCallArguments` consumes.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    /// A single outer candidate supplies an unambiguous expected type for
    /// each nested call argument. Member calls need this context too: their
    /// arguments are first inferred to collect candidates, then prepared again
    /// after the selected receiver and candidate set are known.
    func prepareSingleCandidateNestedCallExpectedTypes(
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        preInferredArgumentTypes: [Int: TypeID] = [:],
        ctx: TypeInferenceContext,
        expectedTypeOverrides: inout [Int: TypeID]
    ) {
        guard candidates.count == 1,
              let candidate = candidates.first,
              let signature = ctx.sema.symbols.functionSignature(for: candidate)
        else {
            return
        }
        let typeVarBySymbol = ctx.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let parameterMapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx)
        for index in args.indices {
            guard isInferableNestedCallExpr(args[index].expr, ast: ctx.ast),
                  let parameterIndex = parameterMapping?[index],
                  parameterIndex < signature.parameterTypes.count,
                  let parameterType = contextualCallArgumentType(
                      args[index], parameterIndex: parameterIndex, in: signature, ctx: ctx
                  ),
                  !ctx.resolver.containsTypeVariable(
                      parameterType,
                      typeVarBySymbol: typeVarBySymbol,
                      typeSystem: ctx.sema.types
                  )
            else {
                continue
            }
            // Constructors and non-generic factories have fixed result types.
            // Keep an incompatible result already inferred without context so
            // an inapplicable member can fall through to an extension overload.
            if let argumentType = preInferredArgumentTypes[index],
               argumentType != ctx.sema.types.errorType,
               let nestedCallee = ctx.sema.bindings.callBinding(for: args[index].expr)?.chosenCallee,
               let nestedSymbol = ctx.sema.symbols.symbol(nestedCallee),
               let nestedSignature = ctx.sema.symbols.functionSignature(for: nestedCallee),
               (nestedSymbol.kind == .constructor && nestedSignature.classTypeParameterCount == 0
                || nestedSymbol.kind == .function && nestedSignature.typeParameterSymbols.isEmpty),
               !ctx.sema.types.isSubtype(argumentType, parameterType)
            {
                continue
            }
            if let existing = expectedTypeOverrides[index], existing != parameterType {
                continue
            }
            // A function-producing call is checked against the SAM's function
            // signature; its returned value is adapted by the outer call.
            expectedTypeOverrides[index] = functionValueSamArgumentExpectedType(
                args[index].expr, parameterType: parameterType, ctx: ctx
            )
        }
    }

    @discardableResult
    func prepareCallExprArgumentContexts(
        args: [CallArgument],
        callRange: SourceRange,
        ctx: TypeInferenceContext,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        candidates: [SymbolID],
        withContextExpectedLambdaType: TypeID?,
        expectedTypeOverrides: inout [Int: TypeID],
        lambdaContextOverrides: inout [Int: TypeInferenceContext]
    ) -> Set<Int> {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)
        var expectedTypeHintIndices: Set<Int> = []


        // Coroutine-specific contextual types and closure ABI marks apply only
        // to coroutine API candidates. Same-named user functions must infer
        // their lambda arguments from their declared parameter types.
        let hasCoroutineLauncherCandidates = !candidates.isEmpty && candidates.allSatisfy { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.fqName.starts(with: [interner.intern("kotlinx"), interner.intern("coroutines")])
        }
        // Canonical source/imported runBlocking is a normal generic function:
        // materialize its block as a suspend value rather than flattening the
        // legacy launcher captures or guessing the block's argument position.
        let isCanonicalRunBlocking = calleeName == knownNames.runBlocking
            && candidates.contains { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.fqName == knownNames.kotlinxCoroutinesRunBlockingFQName
                else { return false }
                return sema.symbols.isSourceBackedSymbol(candidate)
                    || symbol.flags.contains(.importedLibrary)
            }
        let isCoroutineLauncher = hasCoroutineLauncherCandidates && !isCanonicalRunBlocking && (
            calleeName == knownNames.runBlocking
                || calleeName == knownNames.launch
                || calleeName == knownNames.async
                || calleeName == knownNames.coroutineScope
                || calleeName == knownNames.supervisorScope
        )
        let coroutineLauncherExpectedLambdaType: TypeID?
        // STDLIB-CORO-072: Support launch(dispatcher) { } by checking both first and
        // second argument for a trailing lambda. When the first argument is a dispatcher
        // (non-lambda) and the second is a lambda, treat it as the block argument.
        let coroutineLauncherLambdaArgIndex: Int? = {
            guard isCoroutineLauncher
            else { return nil }
            if let firstArgExpr = args.first.flatMap({ ast.arena.expr($0.expr) }),
               case .lambdaLiteral = firstArgExpr {
                return 0
            }
            if args.count >= 2,
               let secondArgExpr = ast.arena.expr(args[1].expr),
               case .lambdaLiteral = secondArgExpr {
                return 1
            }
            return nil
        }()
        if isCoroutineLauncher,
           let lambdaIndex = coroutineLauncherLambdaArgIndex,
           lambdaIndex < args.count
        {
            let lambdaReturnType: TypeID
            if calleeName == knownNames.launch {
                lambdaReturnType = sema.types.unitType
            } else if calleeName == knownNames.async {
                lambdaReturnType = deferredExpectedElementType(expectedType, sema: sema, interner: interner)
                    ?? sema.types.nullableAnyType
            } else {
                lambdaReturnType = expectedType ?? sema.types.nullableAnyType
            }
            coroutineLauncherExpectedLambdaType = sema.types.make(.functionType(FunctionType(
                receiver: coroutineScopeType(sema: sema, interner: interner),
                params: [],
                returnType: lambdaReturnType,
                isSuspend: true,
                nullability: .nonNull
            )))
        } else {
            coroutineLauncherExpectedLambdaType = nil
        }
        // Mark lambda arguments passed to KIR-level coroutine launchers so
        // LambdaLowerer skips the generic escaping-callable-value
        // materialization path for them: CoroutineLoweringPass+
        // LauncherSupport.swift's rewriteLauncherCall expects their captures
        // forwarded via its own launcher-continuation convention (BUG-049),
        // not bundled into a kk_function_create_N closure object. `produce`
        // has its own dedicated builder branch above (CORO-075) with an early
        // return, so it never reaches this general path and is marked there
        // instead.
        if isCoroutineLauncher,
           calleeName == knownNames.runBlocking
               || calleeName == knownNames.launch
               || calleeName == knownNames.async
        {
            if let firstArgExpr = args.first, case .lambdaLiteral = ast.arena.expr(firstArgExpr.expr) {
                sema.bindings.markCoroutineLauncherLambdaExpr(firstArgExpr.expr)
            } else if args.count >= 2, case .lambdaLiteral = ast.arena.expr(args[1].expr) {
                sema.bindings.markCoroutineLauncherLambdaExpr(args[1].expr)
            }
        }

        // A generic destination parameter can be constrained from the call's
        // expected result type even when its argument is an empty factory call:
        // `fun <T, C : MutableCollection<T>> f(destination: C, value: T): C`
        // must contextualize `f(mutableListOf(), 1)` as `C = MutableList<Int>`.
        // The first eager pass intentionally keeps ordinary arguments cheap,
        // so add a targeted override for parameters that are the same type
        // variable returned by the sole viable candidate. The contextual pass
        // then re-infers the nested factory with the concrete target.
        if let expectedType,
           expectedType != sema.types.errorType,
           candidates.count == 1,
           let candidate = candidates.first,
           let signature = sema.symbols.functionSignature(for: candidate),
           case let .typeParam(returnTypeParam) = sema.types.kind(of: signature.returnType)
        {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            if let returnTypeVariable = typeVarBySymbol[returnTypeParam.symbol],
               let parameterMapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx)
            {
                for (argumentIndex, parameterIndex) in parameterMapping {
                    guard signature.parameterTypes.indices.contains(parameterIndex),
                          let parameterType = contextualCallArgumentType(
                              args[argumentIndex], parameterIndex: parameterIndex, in: signature, ctx: ctx
                          )
                    else {
                        continue
                    }
                    guard case let .typeParam(parameterTypeParam) = sema.types.kind(of: parameterType),
                          parameterTypeParam.symbol == returnTypeParam.symbol
                    else {
                        continue
                    }
                    expectedTypeOverrides[argumentIndex] = sema.types.substituteTypeParameters(
                        in: parameterType,
                        substitution: [returnTypeVariable: expectedType],
                        typeVarBySymbol: typeVarBySymbol
                    )
                }
            }
        }
        // A generic factory whose return type is a class parameterized by its
        // own type parameters (`listOf<T>(vararg values: T): List<T>`) can seed
        // those parameters from the call's expected result type before a
        // lambda argument is inferred. Without this, `val xs: List<(Int) ->
        // Int> = listOf({ it + 1 }, ...)` leaves every vararg slot's expected
        // type as the bare, unsubstituted `T`, so a lambda argument's implicit
        // `it` never resolves. Nested generic calls need the same context before
        // checking their own lambdas, e.g. `nullsFirst(compareBy { it.k })`.
        // Lift a subclass return type to the expected nominal owner first:
        // `ParsedValue<X> : ParseResult<X>` must seed X from ParseResult<X>
        // before checking an invariant nested constructor such as Separated.
        // An explicit call-site type argument (`Array<Int>(3) { it }`) always
        // wins over the expected type (`Array<out Any>` here), matching
        // Kotlin's own precedence -- skip this substitution when one is given.
        if explicitTypeArgs.isEmpty,
           let expectedType,
           expectedType != sema.types.errorType,
           case let .classType(expectedClassType) = sema.types.kind(of: expectedType)
        {
            func argType(_ arg: TypeArg) -> TypeID? {
                switch arg {
                case let .invariant(type), let .out(type), let .in(type):
                    type
                case .star:
                    nil
                }
            }
            let expectedVariances = sema.types.normalizedNominalVariances(
                for: expectedClassType.classSymbol, arity: expectedClassType.args.count
            )
            var substitutedTypesByIndex: [Int: Set<TypeID>] = [:]
            var liftedArgumentIndices: Set<Int> = []
            for candidate in candidates {
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      !signature.typeParameterSymbols.isEmpty,
                      case let .classType(returnClassType) = sema.types.kind(of: signature.returnType)
                else {
                    continue
                }
                let isListOfFactory = ctx.cachedSymbol(candidate)?.fqName == [
                    knownNames.kotlin, knownNames.collections, interner.intern("listOf"),
                ]
                let isLiftedReturn = returnClassType.classSymbol != expectedClassType.classSymbol
                guard !isLiftedReturn || ctx.allowsLiftedCallExpectedTypeHints || isListOfFactory else { continue }
                guard let returnArgs = (returnClassType.classSymbol == expectedClassType.classSymbol
                    ? returnClassType.args
                    : sema.types.liftedNominalSupertypeArgs(
                        from: returnClassType.classSymbol,
                        childArgs: returnClassType.args,
                        to: expectedClassType.classSymbol
                    )),
                    returnArgs.count == expectedClassType.args.count
                else {
                    continue
                }
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                var substitution: [TypeVarID: TypeID] = [:]
                var conflictingTypeVariables: Set<TypeVarID> = []
                for (index, (returnArg, expectedArg)) in zip(returnArgs, expectedClassType.args).enumerated() {
                    if isLiftedReturn {
                        // An `in` expectation is a lower bound, so forcing its
                        // exact type into an invariant nested argument can
                        // reject a valid, naturally inferred wider type.
                        switch sema.types.composedProjection(
                            declarationVariance: expectedVariances[index], useSite: expectedArg
                        ) {
                        case .invariant, .out: break
                        case .in, .star, .invalid: continue
                        }
                    }
                    guard let returnArgType = argType(returnArg),
                          let expectedArgType = argType(expectedArg),
                          case let .typeParam(returnTypeParam) = sema.types.kind(of: returnArgType),
                          let typeVar = typeVarBySymbol[returnTypeParam.symbol]
                    else {
                        continue
                    }
                    let contextualType = returnTypeParam.nullability == .nonNull
                        ? expectedArgType : sema.types.makeNonNullable(expectedArgType)
                    // A parameter can appear in several supertype positions,
                    // e.g. Child<T> : Base<T, T>. Different expected arguments
                    // are constraints for the solver, not a last-wins seed.
                    if let existing = substitution[typeVar], existing != contextualType {
                        substitution.removeValue(forKey: typeVar)
                        conflictingTypeVariables.insert(typeVar)
                    } else if !conflictingTypeVariables.contains(typeVar) {
                        substitution[typeVar] = contextualType
                    }
                }
                while isLiftedReturn, !substitution.isEmpty {
                    var unusableSeeds: Set<TypeVarID> = []
                    for (index, symbol) in signature.typeParameterSymbols.enumerated() {
                        guard let variable = typeVarBySymbol[symbol],
                              let seed = substitution[variable] else { continue }
                        let bounds = (signature.typeParameterUpperBoundsList.indices.contains(index)
                            ? signature.typeParameterUpperBoundsList[index] : [])
                            + sema.symbols.typeParameterUpperBounds(for: symbol)
                        for bound in bounds {
                            let substitutedBound = sema.types.substituteTypeParameters(
                                in: bound, substitution: substitution, typeVarBySymbol: typeVarBySymbol
                            )
                            // A covariant result can have a broader expected
                            // argument than the candidate's declared bound.
                            // Let the solver infer a valid narrower argument.
                            if ctx.resolver.containsTypeVariable(
                                substitutedBound, typeVarBySymbol: typeVarBySymbol, typeSystem: sema.types
                            ) || !sema.types.isSubtype(seed, substitutedBound) {
                                unusableSeeds.insert(variable)
                            }
                        }
                    }
                    guard !unusableSeeds.isEmpty else { break }
                    for variable in unusableSeeds { substitution.removeValue(forKey: variable) }
                }
                guard !substitution.isEmpty else { continue }
                guard let parameterMapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx) else {
                    continue
                }
                for index in args.indices {
                    let isLambda: Bool = if case .lambdaLiteral = ast.arena.expr(args[index].expr) {
                        true
                    } else {
                        false
                    }
                    // listOf's ordinary resolver also needs primitive context
                    // before an unsuffixed integer literal defaults to Int/UInt.
                    // Other values retain their actual type for constraint checking.
                    let isListOfIntegerLiteral = isListOfFactory
                        && (isContextualizableIntegerLiteral(args[index].expr, ast: ast)
                        || isContextualizableUnsignedIntegerLiteral(args[index].expr, ast: ast))
                    guard isLambda || isInferableNestedCallExpr(args[index].expr, ast: ast)
                        || isListOfIntegerLiteral,
                          let parameterIndex = parameterMapping[index],
                          let parameterType = contextualCallArgumentType(
                              args[index], parameterIndex: parameterIndex, in: signature, ctx: ctx
                          )
                    else {
                        continue
                    }
                    let substitutedType = sema.types.substituteTypeParameters(
                        in: parameterType,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                    // Enclosing type parameters are valid contextual evidence,
                    // e.g. G<T, T> in `fun <T> make(t: T): W<T> = W(G(t))`.
                    // Only unresolved variables owned by this candidate prevent
                    // contextualizing its nested arguments.
                    guard substitutedType != parameterType,
                          !ctx.resolver.containsTypeVariable(
                              substitutedType,
                              typeVarBySymbol: typeVarBySymbol,
                              typeSystem: sema.types
                          )
                    else {
                        continue
                    }
                    substitutedTypesByIndex[index, default: []].insert(substitutedType)
                    if isLiftedReturn { liftedArgumentIndices.insert(index) }
                }
            }
            // Conflicting contexts from overloads must not depend on candidate
            // order. Only candidates providing usable evidence participate.
            for (index, types) in substitutedTypesByIndex {
                guard types.count == 1, let substitutedType = types.first else { continue }
                if let existing = expectedTypeOverrides[index], existing != substitutedType {
                    continue
                }
                expectedTypeOverrides[index] = substitutedType
                if liftedArgumentIndices.contains(index) { expectedTypeHintIndices.insert(index) }
            }
        }
        // Explicit call-site type arguments carry the same contextual
        // information as an expected return type: `W2<T, Unit>(D(t, 1))`
        // must check the nested `D(t, 1)` against the substituted parameter
        // type `D<T, Unit>`. The block above skips expected-type seeding
        // when explicit args are present because they take precedence, so
        // derive the substitution from the explicit arguments themselves.
        // An override is only applied when every candidate that supplies
        // contextual evidence agrees on the substituted parameter type —
        // otherwise a context derived for one overload would poison the
        // argument for another (e.g. the `Map` overload's expected type
        // breaking `Int`-typed arguments for the `Int` overload).
        if !explicitTypeArgs.isEmpty {
            var substitutedTypesByIndex: [Int: [TypeID]] = [:]
            for candidate in candidates {
                guard let signature = sema.symbols.functionSignature(for: candidate)
                else {
                    continue
                }
                guard let parameterMapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx) else {
                    continue
                }
                let isConstructor = sema.symbols.symbol(candidate)?.kind == .constructor
                let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
                guard signature.typeParameterSymbols.count >= typeArgOffset + explicitTypeArgs.count
                else {
                    continue
                }
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                var substitution: [TypeVarID: TypeID] = [:]
                for (index, explicitTypeArg) in explicitTypeArgs.enumerated() {
                    let symbol = signature.typeParameterSymbols[typeArgOffset + index]
                    guard let typeVar = typeVarBySymbol[symbol] else { continue }
                    substitution[typeVar] = explicitTypeArg
                }
                for index in args.indices {
                    guard isInferableNestedCallExpr(args[index].expr, ast: ast),
                          let parameterIndex = parameterMapping[index],
                          let parameterType = contextualCallArgumentType(
                              args[index], parameterIndex: parameterIndex, in: signature, ctx: ctx
                          )
                    else {
                        continue
                    }
                    let substitutedType = sema.types.substituteTypeParameters(
                        in: parameterType,
                        substitution: substitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                    // A known SAM constructor cannot get its interface type
                    // arguments from an unrelated overload parameter, such as
                    // the Int capacity overload beside Comparator<in T>?.
                    if let samSymbol = inferableSamConstructorSymbol(args[index].expr, ctx: ctx) {
                        guard let contextualClass = resolveClassType(substitutedType, sema: sema),
                              contextualClass.classSymbol == samSymbol
                        else {
                            continue
                        }
                    }
                    // A substituted parameter still carrying candidate-owned
                    // type variables is not usable as contextual evidence;
                    // that candidate abstains rather than vetoing.
                    guard !ctx.resolver.containsTypeVariable(
                        substitutedType,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: sema.types
                    )
                    else {
                        continue
                    }
                    let seen = substitutedTypesByIndex[index] ?? []
                    if !seen.contains(substitutedType) {
                        substitutedTypesByIndex[index] = seen + [substitutedType]
                    }
                }
            }
            for (index, types) in substitutedTypesByIndex {
                guard types.count == 1, let substitutedType = types.first else {
                    continue
                }
                if let existing = expectedTypeOverrides[index], existing != substitutedType {
                    continue
                }
                expectedTypeOverrides[index] = substitutedType
            }
        }
        // With multiple candidates, their parameter types may differ and must
        // not steer a shared argument toward one overload.
        prepareSingleCandidateNestedCallExpectedTypes(
            args: args,
            callRange: callRange,
            candidates: candidates,
            ctx: ctx,
            expectedTypeOverrides: &expectedTypeOverrides
        )
        if let launcherIndex = coroutineLauncherLambdaArgIndex,
           let coroutineLauncherExpectedLambdaType
        {
            expectedTypeOverrides[launcherIndex] = coroutineLauncherExpectedLambdaType
            var builderContext = ctx
            builderContext.isCoroutineBuilderLambdaScope = true
            if let coroutineScopeType = coroutineScopeType(sema: sema, interner: interner) {
                builderContext = builderContext.with(implicitReceiverType: coroutineScopeType)
                if sema.bindings.isCoroutineLauncherLambdaExpr(args[launcherIndex].expr) {
                    sema.bindings.bindCoroutineScopeLambdaReceiverType(args[launcherIndex].expr, type: coroutineScopeType)
                }
            }
            lambdaContextOverrides[launcherIndex] = builderContext
        }
        if let withContextExpectedLambdaType, args.count > 1 {
            expectedTypeOverrides[1] = withContextExpectedLambdaType
        }
        return expectedTypeHintIndices
    }
}
