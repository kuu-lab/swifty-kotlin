// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Argument-context preparation for `inferCallExpr`: coroutine-launcher
/// detection and lambda ABI marks, then the expected-type and lambda-context
/// overrides that `prepareCallArguments` consumes.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func prepareCallExprArgumentContexts(
        args: [CallArgument],
        ctx: TypeInferenceContext,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        candidates: [SymbolID],
        withContextExpectedLambdaType: TypeID?,
        expectedTypeOverrides: inout [Int: TypeID],
        lambdaContextOverrides: inout [Int: TypeInferenceContext]
    ) {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)


        // Coroutine-specific contextual types and closure ABI marks apply only
        // to coroutine API candidates. Same-named user functions must infer
        // their lambda arguments from their declared parameter types.
        let hasCoroutineLauncherCandidates = !candidates.isEmpty && candidates.allSatisfy { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.fqName.starts(with: [interner.intern("kotlinx"), interner.intern("coroutines")])
        }
        let isCoroutineLauncher = hasCoroutineLauncherCandidates && (
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
               let parameterMapping = parameterMappingForCallArguments(args, in: signature, ctx: ctx)
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
            for candidate in candidates {
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      !signature.typeParameterSymbols.isEmpty,
                      case let .classType(returnClassType) = sema.types.kind(of: signature.returnType),
                      returnClassType.classSymbol == expectedClassType.classSymbol,
                      returnClassType.args.count == expectedClassType.args.count
                else {
                    continue
                }
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                var substitution: [TypeVarID: TypeID] = [:]
                for (returnArg, expectedArg) in zip(returnClassType.args, expectedClassType.args) {
                    guard let returnArgType = argType(returnArg),
                          let expectedArgType = argType(expectedArg),
                          case let .typeParam(returnTypeParam) = sema.types.kind(of: returnArgType),
                          let typeVar = typeVarBySymbol[returnTypeParam.symbol]
                    else {
                        continue
                    }
                    substitution[typeVar] = returnTypeParam.nullability == .nonNull
                        ? expectedArgType : sema.types.makeNonNullable(expectedArgType)
                }
                guard !substitution.isEmpty else { continue }
                guard let parameterMapping = parameterMappingForCallArguments(args, in: signature, ctx: ctx) else {
                    continue
                }
                for index in args.indices {
                    let isLambda: Bool = if case .lambdaLiteral = ast.arena.expr(args[index].expr) {
                        true
                    } else {
                        false
                    }
                    guard isLambda || isInferableNestedCallExpr(args[index].expr, ast: ast),
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
                    if let existing = expectedTypeOverrides[index], existing != substitutedType {
                        continue
                    }
                    expectedTypeOverrides[index] = substitutedType
                }
            }
        }
        // Explicit call-site type arguments carry the same contextual
        // information as an expected return type: `W2<T, Unit>(D(t, 1))`
        // must check the nested `D(t, 1)` against the substituted parameter
        // type `D<T, Unit>`. The block above skips expected-type seeding
        // when explicit args are present because they take precedence, so
        // derive the substitution from the explicit arguments themselves.
        // An override is only applied when every candidate that maps the
        // argument position agrees on the substituted parameter type —
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
                guard let parameterMapping = parameterMappingForCallArguments(args, in: signature, ctx: ctx) else {
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
        // A single outer candidate provides an unambiguous expected type for
        // each nested call argument. Forward it before eager inference so
        // `accept(Box(Impl()))` can infer `Box<Thing>` from `accept`'s
        // `Box<Thing>` parameter instead of committing to invariant `Box<Impl>`.
        // With multiple candidates, their parameter types may differ and must
        // not steer a shared argument toward one overload.
        if candidates.count == 1,
           let candidate = candidates.first,
           let signature = sema.symbols.functionSignature(for: candidate)
        {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let parameterMapping = parameterMappingForCallArguments(args, in: signature, ctx: ctx)
            for index in args.indices {
                guard isInferableNestedCallExpr(args[index].expr, ast: ast),
                      let parameterIndex = parameterMapping?[index],
                      parameterIndex < signature.parameterTypes.count
                else {
                    continue
                }
                guard let parameterType = contextualCallArgumentType(
                    args[index], parameterIndex: parameterIndex, in: signature, ctx: ctx
                ) else {
                    continue
                }
                guard !ctx.resolver.containsTypeVariable(
                    parameterType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: sema.types
                ) else {
                    continue
                }
                if let existing = expectedTypeOverrides[index], existing != parameterType {
                    continue
                }
                expectedTypeOverrides[index] = parameterType
            }
        }
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
    }
}
