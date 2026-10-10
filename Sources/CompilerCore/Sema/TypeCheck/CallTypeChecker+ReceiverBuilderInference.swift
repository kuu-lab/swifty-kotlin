final class BuilderInferenceSession {
    let typeVarBySymbol: [SymbolID: TypeVarID]
    var constraints: [VariableConstraint] = []
    var isFinalized = false

    init(typeVarBySymbol: [SymbolID: TypeVarID]) {
        self.typeVarBySymbol = typeVarBySymbol
    }

    func mentionsVariable(_ type: TypeID, types: TypeSystem) -> Bool {
        typeVarBySymbol.keys.contains { types.typeContainsTypeParam(type, symbol: $0) }
    }
}

extension CallTypeChecker {
    func inferReceiverBuilderCall(
        _ id: ExprID,
        calleeName: InternedString?,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        receiverType: TypeID? = nil,
        candidateOverride: [SymbolID]? = nil
    ) -> TypeID? {
        guard let calleeName,
              (candidateOverride != nil || receiverType != nil || locals[calleeName] == nil)
        else { return nil }
        // Coroutine launcher and sequence builders (`produce { }`,
        // `runBlocking { }`, `sequence { }`, ...) have dedicated handling
        // below that derives their element/result type from `send`/`yield`
        // calls inside the block and marks the lambda for the receiver-first
        // launcher ABI (launcher slot 0 carries the produced channel/scope).
        // Letting generic builder inference intercept them would lose both
        // specializations -- `produceIn` lowered with captures bound to the
        // wrong launcher slots, so `source.collect` crashed in
        // `__kk_flow_retain` (KUU-962 / flow_scope_launch_produce).
        let launcherNames = KnownCompilerNames(interner: ctx.interner)
        guard calleeName != launcherNames.produce,
              calleeName != launcherNames.runBlocking,
              calleeName != launcherNames.launch,
              calleeName != launcherNames.async,
              calleeName != launcherNames.coroutineScope,
              calleeName != launcherNames.supervisorScope,
              calleeName != launcherNames.suspendCoroutine,
              calleeName != launcherNames.sequenceFn
        else { return nil }
        let candidates = candidateOverride ?? ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard candidates.count == 1,
              let candidate = candidates.first,
              let signature = ctx.sema.symbols.functionSignature(for: candidate),
              (signature.receiverType == nil) == (receiverType == nil),
              signature.classTypeParameterCount == 0,
              !signature.typeParameterSymbols.isEmpty,
              explicitTypeArgs.isEmpty || explicitTypeArgs.count == signature.typeParameterSymbols.count,
              let mapping = ctx.resolver.buildParameterMapping(
                  signature: signature,
                  callArgs: args.map { CallArg.source($0, type: ctx.sema.types.anyType, callRange: range, ast: ctx.ast) },
                  symbols: ctx.sema.symbols,
                  typeSystem: ctx.sema.types,
                  isCallableArgument: { ctx.ast.arena.expr(args[$0].expr)?.isLambdaOrCallableRef == true }
              )
        else { return nil }
        let sema = ctx.sema
        let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let session = BuilderInferenceSession(typeVarBySymbol: variables)
        for (symbol, argument) in zip(signature.typeParameterSymbols, explicitTypeArgs) {
            guard let variable = variables[symbol] else { continue }
            session.constraints.append(VariableConstraint(
                kind: .equal, left: .variable(variable), right: .type(argument), blameRange: range
            ))
        }
        if let receiverType, let declaredReceiver = signature.receiverType {
            session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: receiverType, supertype: declaredReceiver,
                typeVarBySymbol: variables, typeSystem: sema.types, blameRange: range
            ))
        }
        let lambdaIndices = args.indices.filter { index in
            guard case .lambdaLiteral = ctx.ast.arena.expr(args[index].expr),
                  let parameter = mapping[index],
                  case let .functionType(function) = sema.types.kind(of: signature.parameterTypes[parameter]),
                  function.returnType == sema.types.unitType
            else { return false }
            // Ordinary callback parameters carry postponed variables too:
            // `(Continuation<T>) -> Unit` can infer T from uses in the body.
            return ((function.receiver.map { [$0] } ?? []) + function.params).contains { input in
                resolveClassType(input, sema: sema) != nil
                    && session.mentionsVariable(input, types: sema.types)
            }
        }
        guard lambdaIndices.count == 1, let lambdaIndex = lambdaIndices.first,
              let parameterIndex = mapping[lambdaIndex]
        else { return nil }

        if let expectedType, expectedType != sema.types.unitType {
            session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: signature.returnType, supertype: expectedType,
                typeVarBySymbol: variables, typeSystem: sema.types, blameRange: range
            ))
        }
        let initialSolution = ConstraintSolver().solve(
            vars: ctx.resolver.usedTypeVariables(from: session.constraints),
            constraints: session.constraints, typeSystem: sema.types
        )
        var argumentTypes = [TypeID](repeating: sema.types.errorType, count: args.count)
        var knownArguments: [Int: TypeID] = [:]
        for index in args.indices where index != lambdaIndex {
            let contextualType = mapping[index].flatMap {
                contextualCallArgumentType(args[index], parameterIndex: $0, in: signature, ctx: ctx)
            }.map {
                sema.types.substituteTypeParameters(
                    in: $0, substitution: initialSolution.substitution, typeVarBySymbol: variables
                )
            }
            let type = driver.inferExpr(
                args[index].expr, ctx: ctx, locals: &locals,
                expectedType: contextualType.flatMap { session.mentionsVariable($0, types: sema.types) ? nil : $0 }
            )
            argumentTypes[index] = type
            if let parameter = mapping[index] {
                knownArguments[parameter] = type
                session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: type, supertype: contextualCallArgumentType(
                        args[index], parameterIndex: parameter, in: signature, ctx: ctx
                    ) ?? signature.parameterTypes[parameter],
                    typeVarBySymbol: variables, typeSystem: sema.types, blameRange: range
                ))
            }
        }
        if case let .functionType(function) = sema.types.kind(of: signature.parameterTypes[parameterIndex]),
           let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
               args[lambdaIndex].expr, ctx: ctx, paramCount: function.params.count
           )
        {
            for (parameter, annotation) in zip(function.params, annotations) {
                guard let annotation else { continue }
                session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: parameter, supertype: annotation,
                    typeVarBySymbol: variables, typeSystem: sema.types, blameRange: range
                ))
            }
        }
        var seed = ctx.resolver.probeArgumentTypeSubstitution(
            signature: signature, typeVarBySymbol: variables,
            knownArgumentTypes: knownArguments, typeSystem: sema.types
        )
        if receiverType != nil || expectedType != nil || !explicitTypeArgs.isEmpty {
            let receiverSolution = ConstraintSolver().solve(
                vars: ctx.resolver.usedTypeVariables(from: session.constraints),
                constraints: session.constraints, typeSystem: sema.types
            )
            if receiverSolution.isSuccess {
                seed.merge(receiverSolution.substitution) { _, receiverValue in receiverValue }
            }
        }
        let provisionalLambdaType = sema.types.substituteTypeParameters(
            in: signature.parameterTypes[parameterIndex], substitution: seed, typeVarBySymbol: variables
        )
        var provisionalContext = ctx
        provisionalContext.builderInference = session
        var provisionalLocals = locals
        let checkpoint = ctx.semaCtx.diagnostics.checkpoint()
        _ = driver.inferExpr(
            args[lambdaIndex].expr, ctx: provisionalContext,
            locals: &provisionalLocals, expectedType: provisionalLambdaType
        )
        // Reset the diagnostic deduplication state as well as the speculative
        // output, so a final pass can report the same invalid argument again.
        ctx.semaCtx.diagnostics.truncate(to: checkpoint)

        let solution = ConstraintSolver().solve(
            vars: ctx.resolver.usedTypeVariables(from: session.constraints),
            constraints: session.constraints, typeSystem: sema.types
        )
        guard solution.isSuccess else {
            if let failure = solution.failure { ctx.semaCtx.diagnostics.emit(failure) }
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        if let diagnostic = ctx.resolver.checkForUninferredTypeVariables(
            signature: signature, substitution: solution.substitution,
            typeVarBySymbol: variables, range: range, typeSystem: sema.types
        ) {
            // Collection builders can still infer element/key/value types from
            // mutations in the dedicated path when this callback session has
            // no evidence. Preserve successful inference from other arguments
            // or an expected type before falling back.
            if hasGenericCollectionReceiverLambda(signature: signature, sema: sema, interner: ctx.interner) {
                return nil
            }
            ctx.semaCtx.diagnostics.emit(diagnostic)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        let lambdaType = sema.types.substituteTypeParameters(
            in: signature.parameterTypes[parameterIndex],
            substitution: solution.substitution, typeVarBySymbol: variables
        )
        session.isFinalized = true
        var finalContext = ctx
        finalContext.builderInference = session
        argumentTypes[lambdaIndex] = driver.inferExpr(
            args[lambdaIndex].expr, ctx: finalContext, locals: &locals, expectedType: lambdaType
        )
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(range: range, calleeName: calleeName, args: zip(args, argumentTypes).map {
                CallArg.source($0.0, type: $0.1, callRange: range, ast: ctx.ast)
            }, explicitTypeArgs: signature.typeParameterSymbols.compactMap { symbol in
                variables[symbol].flatMap { solution.substitution[$0] }
            }),
            expectedType: expectedType, implicitReceiverType: receiverType ?? ctx.implicitReceiverType, ctx: sema
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else { return nil }
        driver.helpers.checkDeprecation(
            for: chosen, sema: sema, interner: ctx.interner, range: range, diagnostics: ctx.semaCtx.diagnostics
        )
        driver.helpers.checkOptIn(for: chosen, ctx: ctx, range: range, diagnostics: ctx.semaCtx.diagnostics)
        markSourceBackedCoroutineLauncherArguments(chosen, args: args, ctx: ctx)
        let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        applyContractEffects(id: id, chosen: chosen, args: args, ctx: ctx, locals: &locals)
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    func collectPostponedArgumentConstraints(
        args: [CallArgument],
        range: SourceRange,
        argTypes: [TypeID],
        candidates: [SymbolID],
        receiverType: TypeID?,
        ctx: TypeInferenceContext
    ) -> [TypeID] {
        guard let session = ctx.builderInference, !session.isFinalized,
              candidates.count == 1,
              let candidate = candidates.first,
              let signature = ctx.sema.symbols.functionSignature(for: candidate),
              signature.typeParameterSymbols.isEmpty
                || (ctx.sema.symbols.symbol(candidate)?.kind != .constructor
                    && signature.typeParameterSymbols.count == signature.classTypeParameterCount),
              let mapping = ctx.resolver.buildParameterMapping(
                  signature: signature,
                  callArgs: zip(args, argTypes).map {
                      CallArg.source($0.0, type: $0.1, callRange: range, ast: ctx.ast)
                  },
                  symbols: ctx.sema.symbols, typeSystem: ctx.sema.types
              )
        else { return argTypes }
        let sema = ctx.sema
        for index in args.indices {
            guard let parameter = mapping[index] else { continue }
            let sourceParameterType = contextualCallArgumentType(
                args[index], parameterIndex: parameter, in: signature, ctx: ctx
            ) ?? signature.parameterTypes[parameter]
            // A member's leading type parameters belong to its owner. Lift
            // the actual receiver to that owner before collecting constraints
            // (for example ProducerScope<T> -> SendChannel<T>). An unrelated
            // explicit receiver must not borrow the builder's implicit T.
            let parameterType: TypeID
            if let receiverType, sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil {
                parameterType = applyReceiverClassTypeArgs(
                    to: sourceParameterType, signature: signature,
                    candidate: candidate, receiverType: receiverType, sema: sema
                )
            } else {
                parameterType = applyDispatchReceiverClassTypeArgs(
                    to: sourceParameterType, signature: signature,
                    candidate: candidate, ctx: ctx
                )
            }
            guard session.mentionsVariable(parameterType, types: sema.types)
                || session.mentionsVariable(argTypes[index], types: sema.types)
                || signature.classTypeParameterCount > 0
            else { continue }
            session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: argTypes[index], supertype: parameterType,
                typeVarBySymbol: session.typeVarBySymbol, typeSystem: sema.types,
                blameRange: ctx.ast.arena.exprRange(args[index].expr)
            ))
        }
        let solution = ConstraintSolver().solve(
            vars: ctx.resolver.usedTypeVariables(from: session.constraints),
            constraints: session.constraints, typeSystem: sema.types
        )
        guard solution.isSuccess else { return argTypes }
        // Use the provisional solution for this inner call. The enclosing
        // callback is checked again after all of its constraints are solved.
        return argTypes.map {
            sema.types.substituteTypeParameters(
                in: $0, substitution: solution.substitution,
                typeVarBySymbol: session.typeVarBySymbol
            )
        }
    }

    /// Preserve the actual owner's type arguments when a lone implicit member
    /// falls back after constraint solving. They cannot be widened from values
    /// passed to a receiver whose builder type has already been fixed.
    func bindClassOnlyImplicitReceiverMemberFallback(
        _ id: ExprID, chosen: SymbolID, calleeName: InternedString,
        args: [CallArgument], argTypes: [TypeID], range: SourceRange,
        receiverType: TypeID, explicitTypeArgs: [TypeID], ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        guard explicitTypeArgs.isEmpty,
              let signature = sema.symbols.functionSignature(for: chosen),
              signature.classTypeParameterCount > 0,
              signature.typeParameterSymbols.count == signature.classTypeParameterCount,
              sema.symbols.memberExtensionOwnerSymbol(for: chosen) == nil,
              let mapping = ctx.resolver.buildParameterMapping(
                  signature: signature,
                  callArgs: zip(args, argTypes).map { CallArg.source($0.0, type: $0.1, callRange: range, ast: ctx.ast) },
                  symbols: sema.symbols, typeSystem: sema.types
              )
        else { return nil }
        func specialize(_ type: TypeID) -> TypeID {
            applyReceiverClassTypeArgs(to: type, signature: signature, candidate: chosen,
                                       receiverType: receiverType, sema: sema)
        }
        for (argumentIndex, parameterIndex) in mapping {
            let parameterType = contextualCallArgumentType(
                args[argumentIndex], parameterIndex: parameterIndex, in: signature, ctx: ctx
            ) ?? signature.parameterTypes[parameterIndex]
            driver.emitSubtypeConstraint(
                left: argTypes[argumentIndex], right: specialize(parameterType),
                range: ctx.ast.arena.exprRange(args[argumentIndex].expr) ?? range,
                solver: ConstraintSolver(), sema: sema, diagnostics: ctx.semaCtx.diagnostics
            )
        }
        sema.bindings.bindCall(id, binding: CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: signature.typeParameterSymbols.map {
                specialize(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
            }, parameterMapping: mapping
        ))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
        let result = specialize(signature.returnType)
        sema.bindings.bindExprType(id, type: result)
        return result
    }

    /// A class-only member reads the builder's receiver arguments directly.
    /// Its owner parameters are not new inference variables for this call.
    /// This lets a read such as Slot<T>.get() contribute T to an enclosing
    /// monomorphic constructor before the builder's T has been solved.
    func inferPostponedImplicitReceiverMemberCall(
        _ id: ExprID, calleeName: InternedString?, args: [CallArgument],
        range: SourceRange, ctx: TypeInferenceContext, locals: inout LocalBindings,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let session = ctx.builderInference, !session.isFinalized,
              let calleeName, locals[calleeName] == nil, explicitTypeArgs.isEmpty,
              let receiver = ctx.implicitReceiverType else { return nil }
        let candidates = ctx.filterByVisibility(driver.helpers.collectMemberFunctionCandidates(
            named: calleeName, receiverType: receiver, sema: ctx.sema, interner: ctx.interner
        )).visible
        guard candidates.count == 1, let chosen = candidates.first,
              ctx.sema.symbols.memberExtensionOwnerSymbol(for: chosen) == nil,
              let signature = ctx.sema.symbols.functionSignature(for: chosen),
              signature.classTypeParameterCount > 0,
              signature.typeParameterSymbols.count == signature.classTypeParameterCount
        else { return nil }
        let sema = ctx.sema
        func specialize(_ type: TypeID) -> TypeID {
            applyReceiverClassTypeArgs(to: type, signature: signature, candidate: chosen,
                                       receiverType: receiver, sema: sema)
        }
        let resultType = specialize(signature.returnType)
        guard session.mentionsVariable(resultType, types: sema.types)
            || signature.parameterTypes.contains(where: { session.mentionsVariable(specialize($0), types: sema.types) })
        else { return nil }
        let prepared = prepareCallArguments(args: args, callRange: range, candidates: candidates,
                                            receiverType: receiver, ctx: ctx, locals: &locals)
        guard let mapping = ctx.resolver.buildParameterMapping(
            signature: signature,
            callArgs: zip(args, prepared.argTypes).map { CallArg.source($0.0, type: $0.1, callRange: range, ast: ctx.ast) },
            symbols: sema.symbols, typeSystem: sema.types
        ) else { return nil }
        let arguments = signature.typeParameterSymbols.map {
            specialize(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
        }
        sema.bindings.bindCall(id, binding: CallBinding(chosenCallee: chosen,
            substitutedTypeArguments: arguments, parameterMapping: mapping))
        sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
        sema.bindings.bindExprType(id, type: resultType)
        driver.helpers.checkDeprecation(for: chosen, sema: sema, interner: ctx.interner,
                                       range: range, diagnostics: ctx.semaCtx.diagnostics)
        driver.helpers.checkOptIn(for: chosen, ctx: ctx, range: range, diagnostics: ctx.semaCtx.diagnostics)
        return resultType
    }
}
