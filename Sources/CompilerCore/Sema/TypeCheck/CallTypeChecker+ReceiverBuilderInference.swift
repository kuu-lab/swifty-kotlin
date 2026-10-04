final class BuilderInferenceSession {
    let typeVarBySymbol: [SymbolID: TypeVarID]
    var constraints: [VariableConstraint] = []

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
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let calleeName, locals[calleeName] == nil else { return nil }
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
              calleeName != launcherNames.sequenceFn
        else { return nil }
        let candidates = ctx.filterByVisibility(ctx.cachedScopeLookup(calleeName)).visible
        guard candidates.count == 1,
              let candidate = candidates.first,
              let signature = ctx.sema.symbols.functionSignature(for: candidate),
              signature.receiverType == nil,
              signature.classTypeParameterCount == 0,
              !signature.typeParameterSymbols.isEmpty,
              explicitTypeArgs.isEmpty,
              let mapping = ctx.resolver.buildParameterMapping(
                  signature: signature,
                  callArgs: args.map { CallArg(label: $0.label, isSpread: $0.isSpread, type: ctx.sema.types.anyType) },
                  symbols: ctx.sema.symbols,
                  typeSystem: ctx.sema.types,
                  isCallableArgument: { ctx.ast.arena.expr(args[$0].expr)?.isLambdaOrCallableRef == true }
              )
        else { return nil }
        let sema = ctx.sema
        let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let session = BuilderInferenceSession(typeVarBySymbol: variables)
        let lambdaIndices = args.indices.filter { index in
            guard case .lambdaLiteral = ctx.ast.arena.expr(args[index].expr),
                  let parameter = mapping[index],
                  case let .functionType(function) = sema.types.kind(of: signature.parameterTypes[parameter]),
                  function.returnType == sema.types.unitType,
                  let receiver = function.receiver,
                  resolveClassType(receiver, sema: sema) != nil
            else { return false }
            return session.mentionsVariable(receiver, types: sema.types)
        }
        guard lambdaIndices.count == 1, let lambdaIndex = lambdaIndices.first,
              let parameterIndex = mapping[lambdaIndex]
        else { return nil }

        var argumentTypes = [TypeID](repeating: sema.types.errorType, count: args.count)
        var knownArguments: [Int: TypeID] = [:]
        for index in args.indices where index != lambdaIndex {
            let type = driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals)
            argumentTypes[index] = type
            if let parameter = mapping[index] {
                knownArguments[parameter] = type
                session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: type, supertype: signature.parameterTypes[parameter],
                    typeVarBySymbol: variables, typeSystem: sema.types, blameRange: range
                ))
            }
        }
        if let expectedType, expectedType != sema.types.unitType {
            session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: signature.returnType, supertype: expectedType,
                typeVarBySymbol: variables, typeSystem: sema.types, blameRange: range
            ))
        }
        let seed = ctx.resolver.probeArgumentTypeSubstitution(
            signature: signature, typeVarBySymbol: variables,
            knownArgumentTypes: knownArguments, typeSystem: sema.types
        )
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
        ctx.semaCtx.diagnostics.rollback(to: checkpoint)

        let solution = ConstraintSolver().solve(
            vars: ctx.resolver.usedTypeVariables(from: session.constraints),
            constraints: session.constraints, typeSystem: sema.types
        )
        guard solution.isSuccess,
              ctx.resolver.checkForUninferredTypeVariables(
                  signature: signature, substitution: solution.substitution,
                  typeVarBySymbol: variables, range: range, typeSystem: sema.types
              ) == nil
        else { return nil }

        let lambdaType = sema.types.substituteTypeParameters(
            in: signature.parameterTypes[parameterIndex],
            substitution: solution.substitution, typeVarBySymbol: variables
        )
        argumentTypes[lambdaIndex] = driver.inferExpr(
            args[lambdaIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaType
        )
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(range: range, calleeName: calleeName, args: zip(args, argumentTypes).map {
                CallArg(label: $0.0.label, isSpread: $0.0.isSpread, type: $0.1)
            }, explicitTypeArgs: signature.typeParameterSymbols.compactMap { symbol in
                variables[symbol].flatMap { solution.substitution[$0] }
            }),
            expectedType: expectedType, implicitReceiverType: ctx.implicitReceiverType, ctx: sema
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
        applyContractEffects(chosen: chosen, args: args, ctx: ctx, locals: &locals)
        let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }
}
