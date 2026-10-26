
extension CallTypeChecker {
    /// Nominal context for a nested SAM constructor before eager inference.
    /// Abstain when a same-named callable could take precedence over the interface.
    func inferableSamConstructorSymbol(_ exprID: ExprID, ctx: TypeInferenceContext) -> SymbolID? {
        guard let expr = ctx.ast.arena.expr(exprID),
              case let .call(callee, typeArgs, args, _) = expr,
              typeArgs.isEmpty,
              args.count == 1,
              isSamConvertibleArgument(args[0].expr, ast: ctx.ast),
              let qualifiedName = qualifiedCalleePath(for: callee, ast: ctx.ast),
              let calleeName = qualifiedName.last
        else {
            return nil
        }
        var visibleCallables = ctx.filterByVisibility(
            ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        ).visible
        if visibleCallables.isEmpty {
            visibleCallables = ctx.sema.symbols.lookupAll(fqName: [calleeName]).filter { candidate in
                guard let symbol = ctx.sema.symbols.symbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        }
        guard visibleCallables.isEmpty else { return nil }
        return samConstructorTarget(named: calleeName, qualifiedName: qualifiedName, ctx: ctx)?.interfaceSymbol
    }

    func inferSamConvertedCallExpr(
        _ id: ExprID,
        calleeName: InternedString,
        qualifiedName: [InternedString]? = nil,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        samFactoryCandidates: inout [SymbolID]?
    ) -> TypeID? {
        let samArgIndices = args.enumerated().compactMap { index, argument in
            isSamConvertibleArgument(argument.expr, ast: ctx.ast) ? index : nil
        }
        if samArgIndices.isEmpty {
            return inferSamConstructorFromFunctionValue(
                id, calleeName: calleeName, qualifiedName: qualifiedName, args: args, ctx: ctx, locals: &locals,
                expectedType: expectedType, explicitTypeArgs: explicitTypeArgs
            )
        }
        guard samArgIndices.count == 1 else {
            return nil
        }
        let samArgIndex = samArgIndices[0]
        let samArgExpr = args[samArgIndex].expr

        var visibleCandidates = ctx.filterByVisibility(
            ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        ).visible
        if visibleCandidates.isEmpty {
            visibleCandidates = ctx.filterByVisibility(ctx.sema.symbols.lookupAll(fqName: [calleeName]).filter { candidate in
                guard let symbol = ctx.sema.symbols.symbol(candidate) else {
                    return false
                }
                return symbol.kind == .function || symbol.kind == .constructor
            }).visible
        }
        // A same-named factory participates in ordinary overload resolution before
        // the synthetic SAM constructor. Check applicability without inferring a
        // losing lambda body or suppressing errors in the winning factory context.
        let hasSamConstructor = samConstructorTarget(
            named: calleeName, qualifiedName: qualifiedName, ctx: ctx
        ) != nil
        if hasSamConstructor {
            let shapes = samFactoryShapes(
                visibleCandidates, calleeName: calleeName, args: args, range: range,
                ctx: ctx, locals: locals, explicitTypeArgs: explicitTypeArgs
            )
            let applicable = visibleCandidates.filter { shapes[$0] != nil }
            if let first = applicable.first, let firstShape = shapes[first] {
                let resolution = ctx.resolver.resolveCall(
                    candidates: applicable,
                    call: CallExpr(
                        range: range, calleeName: calleeName,
                        args: [CallArg.source(args[0], type: firstShape.argumentType, callRange: range, ast: ctx.ast)],
                        explicitTypeArgs: explicitTypeArgs
                    ),
                    expectedType: nil, implicitReceiverType: ctx.implicitReceiverType,
                    candidateArgumentTypes: shapes.mapValues { [0: $0.argumentType] }, ctx: ctx.sema
                )
                if let diagnostic = resolution.diagnostic {
                    let canRefineReturnType: Bool
                    if diagnostic.code == "KSWIFTK-SEMA-0003",
                       case .lambdaLiteral = ctx.ast.arena.expr(args[0].expr)
                    {
                        canRefineReturnType = samFactoryAllowsReturnTypeRefinement(applicable, shapes: shapes, sema: ctx.sema)
                    } else {
                        canRefineReturnType = false
                    }
                    if !canRefineReturnType {
                        ctx.sema.diagnostics.emit(diagnostic)
                        return ctx.sema.types.errorType
                    }
                }
                samFactoryCandidates = resolution.chosenCallee.map { [$0] } ?? applicable
                return nil
            }
        }
        let samCompatibleCandidates = visibleCandidates.filter { candidate in
            guard !hasSamConstructor,
                  let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count),
                  samArgIndex < signature.parameterTypes.count
            else {
                return false
            }
            return driver.helpers.samFunctionType(for: signature.parameterTypes[samArgIndex], sema: ctx.sema) != nil
        }
        let narrowedSamCandidates = narrowSamCandidates(
            samCompatibleCandidates,
            args: args,
            samArgIndex: samArgIndex,
            ctx: ctx,
            locals: &locals
        )

        if narrowedSamCandidates.count == 1,
           let signature = ctx.sema.symbols.functionSignature(for: narrowedSamCandidates[0])
        {
            var argTypes: [CallArg] = []
            argTypes.reserveCapacity(args.count)
            for (index, argument) in args.enumerated() {
                let parameterExpectedType = index < signature.parameterTypes.count ? signature.parameterTypes[index] : nil
                let inferredType = driver.inferExpr(
                    argument.expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: parameterExpectedType
                )
                let resolutionType = ctx.sema.bindings.isSamConversion(argument.expr)
                    ? ctx.sema.bindings.samUnderlyingFunctionType(for: argument.expr) ?? inferredType
                    : inferredType
                argTypes.append(CallArg.source(argument, type: resolutionType, callRange: range, ast: ctx.ast))
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: narrowedSamCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName,
                    args: argTypes,
                    explicitTypeArgs: explicitTypeArgs
                ),
                expectedType: expectedType,
                implicitReceiverType: ctx.implicitReceiverType,
                ctx: ctx.sema
            )
            if let diagnostic = resolved.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
                ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.errorType)
                return ctx.sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                return nil
            }
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: ctx.sema,
                interner: ctx.interner,
                range: range,
                diagnostics: ctx.sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.sema.diagnostics
            )
            bindResolvedSamLambdaArguments(
                args, chosen: chosen, resolved: resolved, ast: ctx.ast, sema: ctx.sema
            )
            return bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: ctx.sema)
        }

        if args.count == 1, let samType = inferSamConstructorCallExpr(
            id,
            calleeName: calleeName,
            qualifiedName: qualifiedName,
            argExpr: samArgExpr,
               ctx: ctx,
               locals: &locals,
               expectedType: expectedType,
               explicitTypeArgs: explicitTypeArgs
           ) {
            return samType
        }

        return nil
    }

    private func bindResolvedSamLambdaArguments(
        _ args: [CallArgument],
        chosen: SymbolID,
        resolved: ResolvedCall,
        ast: ASTModule,
        sema: SemaModule
    ) {
        guard let signature = sema.symbols.functionSignature(for: chosen) else { return }
        let typeVars = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        for (argumentIndex, argument) in args.enumerated() {
            guard case .lambdaLiteral = ast.arena.expr(argument.expr),
                  sema.bindings.isSamConversion(argument.expr),
                  let parameterIndex = resolved.parameterMapping[argumentIndex],
                  signature.parameterTypes.indices.contains(parameterIndex)
            else {
                continue
            }
            let interfaceType = sema.types.substituteTypeParameters(
                in: signature.parameterTypes[parameterIndex],
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVars
            )
            guard let samFunction = driver.helpers.samFunctionType(for: interfaceType, sema: sema) else {
                continue
            }
            let functionType = sema.types.make(.functionType(samFunction))
            sema.bindings.bindExprType(argument.expr, type: interfaceType)
            sema.bindings.bindSamInterfaceType(argument.expr, type: interfaceType)
            sema.bindings.bindSamUnderlyingFunctionType(argument.expr, type: functionType)
        }
    }

    /// The synthetic SAM constructor accepts a function value, not only a
    /// lambda or reference. Abstain when a same-named function could take
    /// precedence.
    private func inferSamConstructorFromFunctionValue(
        _ id: ExprID,
        calleeName: InternedString,
        qualifiedName: [InternedString]?,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard args.count == 1,
              args[0].label == nil, !args[0].isSpread,
              case let .nameRef(argName, _)? = ctx.ast.arena.expr(args[0].expr),
              let local = locals[argName],
              case .functionType = ctx.sema.types.kind(of: local.type),
              samConstructorTarget(named: calleeName, qualifiedName: qualifiedName, ctx: ctx) != nil
        else { return nil }
        let hasCallable = !ctx.filterByVisibility(
            ctx.cachedScopeLookup(calleeName).filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                return symbol.kind == .function || symbol.kind == .constructor
            }
        ).visible.isEmpty
        guard !hasCallable else { return nil }
        return inferSamConstructorCallExpr(
            id, calleeName: calleeName, qualifiedName: qualifiedName,
            argExpr: args[0].expr, ctx: ctx, locals: &locals,
            expectedType: expectedType, explicitTypeArgs: explicitTypeArgs
        )
    }

    func narrowSamCandidates(
        _ candidates: [SymbolID],
        args: [CallArgument],
        samArgIndex: Int,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> [SymbolID] {
        guard candidates.count > 1 else {
            return candidates
        }

        var inferredNonSamArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() where index != samArgIndex {
            inferredNonSamArgTypes[index] = driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }

        let narrowed = candidates.filter { candidate in
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate),
                  isCallableArityCompatible(signature: signature, argCount: args.count)
            else {
                return false
            }
            for (index, inferredType) in inferredNonSamArgTypes {
                guard let parameterType = parameterTypeForArgument(
                    at: index,
                    in: signature
                ) else {
                    return false
                }
                if !ctx.sema.types.isSubtype(inferredType, parameterType) {
                    return false
                }
            }
            return true
        }

        return narrowed.isEmpty ? candidates : narrowed
    }

    func isCallableArityCompatible(signature: FunctionSignature, argCount: Int) -> Bool {
        let hasVararg = signature.valueParameterIsVararg.contains(true)
        let requiredCount = zip(signature.parameterTypes.indices, signature.valueParameterHasDefaultValues).reduce(0) { partial, entry in
            let (index, hasDefault) = entry
            if hasVararg, signature.valueParameterIsVararg[index] {
                return partial
            }
            return partial + (hasDefault ? 0 : 1)
        }
        if argCount < requiredCount {
            return false
        }
        if hasVararg {
            return true
        }
        return argCount <= signature.parameterTypes.count
    }

    func parameterTypeForArgument(
        at index: Int,
        in signature: FunctionSignature
    ) -> TypeID? {
        guard index >= 0 else {
            return nil
        }
        if index < signature.parameterTypes.count {
            return signature.parameterTypes[index]
        }
        guard let varargIndex = signature.valueParameterIsVararg.firstIndex(of: true),
              varargIndex < signature.parameterTypes.count,
              index >= varargIndex
        else {
            return nil
        }
        return signature.parameterTypes[varargIndex]
    }

    func samConstructorTarget(
        named name: InternedString,
        qualifiedName: [InternedString]? = nil,
        ctx: TypeInferenceContext
    ) -> (interfaceSymbol: SymbolID, typeAliasSymbol: SymbolID?)? {
        let sema = ctx.sema
        let isFunInterface: (SymbolID) -> Bool = { candidate in
            guard let symbol = ctx.cachedSymbol(candidate) else { return false }
            return symbol.kind == .interface && symbol.flags.contains(.funInterface)
        }
        func target(in candidates: [SymbolID]) -> (interfaceSymbol: SymbolID, typeAliasSymbol: SymbolID?)? {
            if let interface = candidates.first(where: isFunInterface) {
                return (interface, nil)
            }
            for alias in candidates where ctx.cachedSymbol(alias)?.kind == .typeAlias {
                let typeParameters = sema.symbols.typeAliasTypeParameters(for: alias)
                let typeArgs = typeParameters.map { parameter in
                    TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: parameter))))
                }
                guard let expanded = driver.helpers.expandTypeAlias(
                    alias,
                    typeArgs: typeArgs,
                    sema: sema,
                    visited: [],
                    depth: 0
                ),
                   case let .classType(classType) = sema.types.kind(of: expanded),
                   classType.nullability == .nonNull,
                   isFunInterface(classType.classSymbol)
                else {
                    continue
                }
                return (classType.classSymbol, alias)
            }
            return nil
        }

        if let qualifiedName, qualifiedName.count > 1 {
            let qualifiedCandidates = ctx.filterByVisibility(sema.symbols.lookupAll(fqName: qualifiedName)).visible
            if let target = target(in: qualifiedCandidates) {
                return target
            }
        }

        let scoped = ctx.filterByVisibility(ctx.cachedScopeLookup(name)).visible
        if let target = target(in: scoped) {
            return target
        }

        let kotlinFQName = [ctx.interner.intern("kotlin"), name]
        let kotlinCandidates = ctx.filterByVisibility(sema.symbols.lookupAll(fqName: kotlinFQName)).visible
        if let target = target(in: kotlinCandidates) {
            return target
        }
        return nil
    }

    private func inferSamConstructorCallExpr(
        _ id: ExprID,
        calleeName: InternedString,
        qualifiedName: [InternedString]?,
        argExpr: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        guard let target = samConstructorTarget(
            named: calleeName, qualifiedName: qualifiedName, ctx: ctx
        ) else {
            return nil
        }
        let interfaceSymID = target.interfaceSymbol
        let sema = ctx.sema
        let interfaceTypeParameters = sema.types.nominalTypeParameterSymbols(for: interfaceSymID)
        let interfaceType: TypeID
        if let aliasSymbol = target.typeAliasSymbol {
            guard let aliasType = samAliasConstructorType(
                aliasSymbol,
                interfaceSymbol: interfaceSymID,
                interfaceTypeParameters: interfaceTypeParameters,
                argExpr: argExpr,
                expectedType: expectedType,
                explicitTypeArgs: explicitTypeArgs,
                ctx: ctx,
                locals: locals
            ) else {
                return nil
            }
            interfaceType = aliasType
        } else {
            let inferredInterfaceArgs: [TypeArg]
            if let expectedType,
               let expectedClassType = resolveClassType(expectedType, sema: sema),
               expectedClassType.classSymbol == interfaceSymID
            {
                inferredInterfaceArgs = expectedClassType.args
            } else {
                let annotationArgs = inferInterfaceArgsFromLambdaAnnotations(
                    interfaceSymID,
                    typeParameters: interfaceTypeParameters,
                    argExpr: argExpr,
                    ctx: ctx
                )
                if annotationArgs.count == interfaceTypeParameters.count {
                    inferredInterfaceArgs = annotationArgs
                } else {
                    inferredInterfaceArgs = inferInterfaceArgsFromLambdaReturnType(
                        interfaceSymID,
                        typeParameters: interfaceTypeParameters,
                        argExpr: argExpr,
                        ctx: ctx,
                        locals: locals
                    ) ?? annotationArgs
                }
            }

            let interfaceArgs: [TypeArg]
            if explicitTypeArgs.isEmpty {
                interfaceArgs = inferredInterfaceArgs
            } else {
                guard explicitTypeArgs.count == interfaceTypeParameters.count else {
                    return nil
                }
                var mergedArgs: [TypeArg] = []
                for index in interfaceTypeParameters.indices {
                    if let explicit = resolvedExplicitTypeArgument(at: index, in: explicitTypeArgs) {
                        mergedArgs.append(.invariant(explicit))
                    } else if inferredInterfaceArgs.indices.contains(index) {
                        mergedArgs.append(inferredInterfaceArgs[index])
                    } else {
                        return nil
                    }
                }
                interfaceArgs = mergedArgs
            }
            interfaceType = sema.types.make(.classType(ClassType(
                classSymbol: interfaceSymID,
                args: interfaceArgs,
                nullability: .nonNull
            )))
        }
        let samFT: FunctionType?
        if case .callableRef = ctx.ast.arena.expr(argExpr) {
            samFT = driver.helpers.samCallableReferenceFunctionType(for: interfaceType, sema: sema)
        } else {
            samFT = driver.helpers.samFunctionType(for: interfaceType, sema: sema)
        }
        guard let samFT else {
            return nil
        }
        let samFTTypeID = sema.types.make(.functionType(samFT))

        _ = driver.inferExpr(
            argExpr,
            ctx: ctx,
            locals: &locals,
            expectedType: interfaceType
        )

        sema.bindings.markSamConversion(argExpr)
        sema.bindings.bindSamUnderlyingFunctionType(argExpr, type: samFTTypeID)
        sema.bindings.bindSamInterfaceType(argExpr, type: interfaceType)

        sema.bindings.bindExprType(id, type: interfaceType)
        return interfaceType
    }

    private func samAliasConstructorType(
        _ aliasSymbol: SymbolID,
        interfaceSymbol: SymbolID,
        interfaceTypeParameters: [SymbolID],
        argExpr: ExprID,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let aliasTypeParameters = sema.symbols.typeAliasTypeParameters(for: aliasSymbol)
        guard explicitTypeArgs.isEmpty || explicitTypeArgs.count == aliasTypeParameters.count else {
            return nil
        }
        let aliasTypeArgs: [TypeArg] = if explicitTypeArgs.isEmpty {
            aliasTypeParameters.map { parameter in
                .invariant(sema.types.make(.typeParam(TypeParamType(symbol: parameter))))
            }
        } else {
            explicitTypeArgs.map(TypeArg.invariant)
        }
        guard let expanded = driver.helpers.expandTypeAlias(
            aliasSymbol,
            typeArgs: aliasTypeArgs,
            sema: sema,
            visited: [],
            depth: 0,
            diagnostics: sema.diagnostics
        ),
           case let .classType(templateType) = sema.types.kind(of: expanded),
           templateType.classSymbol == interfaceSymbol,
           templateType.nullability == .nonNull
        else {
            return nil
        }
        if !explicitTypeArgs.isEmpty || aliasTypeParameters.isEmpty {
            return expanded
        }

        var inferredAliasArguments: [TypeID]?
        if let expectedType,
           let expectedClassType = resolveClassType(expectedType, sema: sema),
           expectedClassType.classSymbol == interfaceSymbol
        {
            inferredAliasArguments = inferSamAliasTypeArguments(
                aliasTypeParameters,
                templateArguments: templateType.args,
                actualArguments: expectedClassType.args,
                ctx: ctx
            )
        }
        if inferredAliasArguments == nil {
            let annotationArguments = inferInterfaceArgsFromLambdaAnnotations(
                interfaceSymbol,
                typeParameters: interfaceTypeParameters,
                argExpr: argExpr,
                ctx: ctx
            )
            if annotationArguments.count == interfaceTypeParameters.count {
                inferredAliasArguments = inferSamAliasTypeArguments(
                    aliasTypeParameters,
                    templateArguments: templateType.args,
                    actualArguments: annotationArguments,
                    ctx: ctx
                )
            }
        }
        if inferredAliasArguments == nil,
           let returnArguments = inferInterfaceArgsFromLambdaReturnType(
               interfaceSymbol,
               typeParameters: interfaceTypeParameters,
               argExpr: argExpr,
               ctx: ctx,
               locals: locals
           )
        {
            inferredAliasArguments = inferSamAliasTypeArguments(
                aliasTypeParameters,
                templateArguments: templateType.args,
                actualArguments: returnArguments,
                ctx: ctx
            )
        }
        guard let inferredAliasArguments,
              inferredAliasArguments.count == aliasTypeParameters.count
        else {
            return nil
        }
        return driver.helpers.expandTypeAlias(
            aliasSymbol,
            typeArgs: inferredAliasArguments.map(TypeArg.invariant),
            sema: sema,
            visited: [],
            depth: 0,
            diagnostics: sema.diagnostics
        )
    }

    private func inferSamAliasTypeArguments(
        _ aliasTypeParameters: [SymbolID],
        templateArguments: [TypeArg],
        actualArguments: [TypeArg],
        ctx: TypeInferenceContext
    ) -> [TypeID]? {
        let sema = ctx.sema
        guard !aliasTypeParameters.isEmpty,
              templateArguments.count == actualArguments.count
        else {
            return nil
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(aliasTypeParameters)
        let variables = aliasTypeParameters.compactMap { typeVarBySymbol[$0] }
        guard variables.count == aliasTypeParameters.count else {
            return nil
        }
        var constraints: [VariableConstraint] = []
        for (templateArgument, actualArgument) in zip(templateArguments, actualArguments) {
            let templateType: TypeID
            let actualType: TypeID
            switch (templateArgument, actualArgument) {
            case let (.invariant(template), .invariant(actual)),
                 let (.invariant(template), .out(actual)),
                 let (.invariant(template), .in(actual)),
                 let (.out(template), .invariant(actual)),
                 let (.in(template), .invariant(actual)),
                 let (.out(template), .out(actual)),
                 let (.in(template), .in(actual)):
                templateType = template
                actualType = actual
            case (.star, _), (_, .star):
                return nil
            default:
                return nil
            }
            constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: templateType,
                supertype: actualType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: sema.types,
                blameRange: nil
            ))
            constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: actualType,
                supertype: templateType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: sema.types,
                blameRange: nil
            ))
        }
        let solution = ConstraintSolver().solve(
            vars: variables,
            constraints: constraints,
            typeSystem: sema.types
        )
        guard solution.isSuccess else {
            return nil
        }
        let inferredArguments = aliasTypeParameters.compactMap { parameter in
            typeVarBySymbol[parameter].flatMap { solution.substitution[$0] }
        }
        guard inferredArguments.count == aliasTypeParameters.count else {
            return nil
        }
        return inferredArguments
    }

    /// Infers a raw SAM constructor's type arguments from the lambda's explicit
    /// parameter type annotations, which are the only source of that information
    /// when neither explicit type arguments nor an expected type are available
    /// (BUG-046).
    private func inferInterfaceArgsFromLambdaAnnotations(
        _ interfaceSymID: SymbolID,
        typeParameters: [SymbolID],
        argExpr: ExprID,
        ctx: TypeInferenceContext
    ) -> [TypeArg] {
        let sema = ctx.sema
        guard !typeParameters.isEmpty,
              let signature = driver.helpers.samMethodSignature(for: interfaceSymID, sema: sema),
              let annotations = driver.exprChecker.resolveLambdaParamAnnotations(
                  argExpr,
                  ctx: ctx,
                  paramCount: signature.parameterTypes.count
              )
        else {
            return []
        }
        var bindings: [SymbolID: TypeID] = [:]
        for (index, parameterType) in signature.parameterTypes.enumerated() {
            guard let annotated = annotations[index],
                  case let .typeParam(typeParam) = sema.types.kind(of: parameterType),
                  bindings[typeParam.symbol] == nil
            else {
                continue
            }
            bindings[typeParam.symbol] = annotated
        }
        let inferredArgs: [TypeArg] = typeParameters.compactMap { bindings[$0].map { .invariant($0) } }
        return inferredArgs.count == typeParameters.count ? inferredArgs : []
    }

    private func inferInterfaceArgsFromLambdaReturnType(
        _ interfaceSymID: SymbolID,
        typeParameters: [SymbolID],
        argExpr: ExprID,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> [TypeArg]? {
        let sema = ctx.sema
        guard !typeParameters.isEmpty,
              case let .lambdaLiteral(_, bodyExpr, _, _) = ctx.ast.arena.expr(argExpr),
              let signature = driver.helpers.samMethodSignature(for: interfaceSymID, sema: sema),
              typeParameters.allSatisfy({ sema.types.typeContainsTypeParam(signature.returnType, symbol: $0) })
        else {
            return nil
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        guard typeParameters.allSatisfy({ typeVarBySymbol[$0] != nil }) else {
            return nil
        }
        let provisionalType = sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymID,
            args: typeParameters.map {
                .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
            },
            nullability: .nonNull
        )))
        guard let samFunctionType = driver.helpers.samFunctionType(for: provisionalType, sema: sema) else {
            return nil
        }

        // Give the lambda its SAM input types but a top return type so its body
        // is inferred without prematurely checking against unresolved T.
        let returnProbeType = sema.types.make(.functionType(FunctionType(
            contextReceivers: samFunctionType.contextReceivers,
            receiver: samFunctionType.receiver,
            params: samFunctionType.params,
            returnType: sema.types.nullableAnyType,
            isSuspend: samFunctionType.isSuspend,
            isCallableReference: samFunctionType.isCallableReference,
            nullability: samFunctionType.nullability,
            throws: samFunctionType.throws
        )))
        let checkpoint = sema.diagnostics.checkpoint()
        var probeLocals = locals
        _ = driver.inferExpr(argExpr, ctx: ctx, locals: &probeLocals, expectedType: returnProbeType)
        let bodyType = sema.bindings.exprType(for: bodyExpr)
        sema.diagnostics.rollback(to: checkpoint)
        guard let bodyType, bodyType != sema.types.errorType else {
            return nil
        }

        let constraints = ctx.resolver.decomposeSubtypeConstraint(
            subtype: bodyType,
            supertype: signature.returnType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: sema.types,
            blameRange: ctx.ast.arena.exprRange(bodyExpr)
        )
        let variables = ctx.resolver.usedTypeVariables(from: constraints)
        guard !variables.isEmpty else {
            return nil
        }
        let solution = ConstraintSolver().solve(
            vars: variables,
            constraints: constraints,
            typeSystem: sema.types
        )
        guard solution.isSuccess else {
            return nil
        }

        var inferredArgs: [TypeArg] = []
        inferredArgs.reserveCapacity(typeParameters.count)
        for typeParameter in typeParameters {
            guard let variable = typeVarBySymbol[typeParameter],
                  let type = solution.substitution[variable],
                  type != sema.types.errorType
            else {
                return nil
            }
            inferredArgs.append(.invariant(type))
        }
        return inferredArgs
    }

    private func isSamConvertibleArgument(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else {
            return false
        }
        switch expr {
        case .lambdaLiteral, .callableRef:
            return true
        default:
            return false
        }
    }
}
