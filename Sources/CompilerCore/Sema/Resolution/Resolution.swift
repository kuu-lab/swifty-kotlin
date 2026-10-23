private extension CallExpr {
    func replacingArgumentTypes(_ replacements: [Int: TypeID]) -> CallExpr {
        guard !replacements.isEmpty else {
            return self
        }
        let updatedArgs = args.enumerated().map { index, arg in
            CallArg(
                label: arg.label,
                isSpread: arg.isSpread,
                type: replacements[index] ?? arg.type,
                signedIntegerLiteral: arg.signedIntegerLiteral,
                unsignedIntegerLiteral: arg.unsignedIntegerLiteral,
                isTrailingLambda: arg.isTrailingLambda,
                bindsToLastParameter: arg.bindsToLastParameter
            )
        }
        return CallExpr(
            range: range,
            calleeName: calleeName,
            args: updatedArgs,
            explicitTypeArgs: explicitTypeArgs,
            dispatchReceiverTypes: dispatchReceiverTypes,
            boundObjectDispatchReceiverCandidates: boundObjectDispatchReceiverCandidates,
            typeAliasConstructor: typeAliasConstructor,
            elvisLhsExpectedTypeHint: elvisLhsExpectedTypeHint,
            elvisRhsCallResultTypeHint: elvisRhsCallResultTypeHint
        )
    }
}

extension OverloadResolver {
    public func probeCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID? = nil,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]] = [:],
        ignoringLambdaReturnTypeArgumentIndices: Set<Int> = [],
        resultIsDiscarded: Bool = false,
        ctx: SemaModule
    ) -> ProbedCallResult {
        let (viable, _) = evaluateCandidates(
            candidates,
            call: call,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: candidateArgumentTypes,
            ignoredLambdaReturnTypeArgumentIndices: ignoringLambdaReturnTypeArgumentIndices,
            resultIsDiscarded: resultIsDiscarded,
            ctx: ctx
        )
        return ProbedCallResult(
            viableCandidates: viable.map { $0.toProbedCallCandidate() }
        )
    }

    /// Derives a partial type-variable substitution for `signature`'s type
    /// parameters from known argument types and explicitly typed lambda inputs.
    /// Used to seed a lambda argument's expected type before the lambda literal
    /// itself is type-checked (see `lambdaLiteralExpectedType` in
    /// `CallTypeChecker+LambdaReturnTypeOverload.swift`).
    /// A missing key in the result means that type parameter could not be
    /// constrained from the known arguments — callers must treat it as
    /// "unconstrained", not as an error.
    func probeArgumentTypeSubstitution(
        signature: FunctionSignature,
        typeVarBySymbol: [SymbolID: TypeVarID],
        knownArgumentTypes: [Int: TypeID],
        knownLambdaInputAnnotations: [Int: [TypeID?]] = [:],
        typeSystem: TypeSystem,
        blameRange: SourceRange? = nil,
        implicitReceiverType: TypeID? = nil
    ) -> [TypeVarID: TypeID] {
        guard !typeVarBySymbol.isEmpty else {
            return [:]
        }
        var constraints: [VariableConstraint] = []
        var lambdaInputTypeVariables: Set<TypeVarID> = []
        for (index, argType) in knownArgumentTypes {
            guard index >= 0, index < signature.parameterTypes.count else { continue }
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: argType,
                supertype: signature.parameterTypes[index],
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange
            ))
        }
        for (parameterIndex, annotations) in knownLambdaInputAnnotations {
            guard signature.parameterTypes.indices.contains(parameterIndex),
                  case let .functionType(functionType) = typeSystem.kind(
                      of: signature.parameterTypes[parameterIndex]
                  ),
                  functionType.params.count == annotations.count
            else { continue }
            for (expectedInput, annotation) in zip(functionType.params, annotations) {
                guard let annotation else { continue }
                for (symbol, variable) in typeVarBySymbol where typeSystem.typeContainsTypeParam(
                    expectedInput, symbol: symbol
                ) {
                    lambdaInputTypeVariables.insert(variable)
                }
                constraints.append(contentsOf: decomposeSubtypeConstraint(
                    subtype: expectedInput,
                    supertype: annotation,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: blameRange
                ))
            }
        }
        if let implicitReceiverType, let receiverType = signature.receiverType {
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: implicitReceiverType,
                supertype: receiverType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange
            ))
        }
        guard !constraints.isEmpty else { return [:] }
        guard !usedTypeVariables(from: constraints).isEmpty else { return [:] }

        // A known argument can determine a type parameter indirectly through
        // another parameter's dependent upper bound. For example, a destination
        // argument can infer `M` in `M : MutableMap<in K, S>`, which in turn
        // determines `S` before the operation lambda is type-checked. Expand
        // those bounds while the probe still has concrete argument types; the
        // full call resolver performs the authoritative bound check later.
        var solution = ConstraintSolver().solve(
            vars: usedTypeVariables(from: constraints),
            constraints: constraints,
            typeSystem: typeSystem
        )
        guard solution.isSuccess else { return [:] }
        let symbolTable = typeSystem.symbolTable
        for _ in 0 ... max(1, signature.typeParameterSymbols.count) {
            var addedDependentConstraint = false
            for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
                guard let typeVar = typeVarBySymbol[typeParamSymbol],
                      let substitutedType = solution.substitution[typeVar]
                else {
                    continue
                }
                let signatureBounds = index < signature.typeParameterUpperBoundsList.count
                    ? signature.typeParameterUpperBoundsList[index]
                    : []
                let symbolBounds = symbolTable?.typeParameterUpperBounds(for: typeParamSymbol) ?? []
                let upperBounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
                for upperBound in upperBounds {
                    let substitutedBound = typeSystem.substituteTypeParameters(
                        in: upperBound,
                        substitution: solution.substitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                    guard containsTypeVariable(
                        substitutedBound,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem
                    ) else {
                        continue
                    }
                    let dependentConstraints = decomposeSubtypeConstraint(
                        subtype: substitutedType,
                        supertype: substitutedBound,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: blameRange
                    )
                    guard !usedTypeVariables(from: dependentConstraints).isEmpty else {
                        continue
                    }
                    constraints.append(contentsOf: dependentConstraints)
                    addedDependentConstraint = true
                }
            }
            guard addedDependentConstraint else { break }
            solution = ConstraintSolver().solve(
                vars: usedTypeVariables(from: constraints),
                constraints: constraints,
                typeSystem: typeSystem
            )
            guard solution.isSuccess else { return [:] }
        }

        // An upper bound derived from an ordinary argument is not a usable
        // lambda context. For example, Comparator<Any> passed to Comparator<in
        // R> only establishes R <: Any; the trailing selector still has to
        // infer R from its return type. Explicit lambda input annotations are
        // different: their input variables are solved candidate-locally, while
        // unrelated upper-only variables remain unresolved for the lambda pass.
        let lowerBoundedVariables: Set<TypeVarID> = Set(constraints.compactMap { constraint in
            guard case .type = constraint.left,
                  case let .variable(variable) = constraint.right
            else {
                return nil
            }
            return variable
        })
        return solution.substitution.filter {
            lowerBoundedVariables.contains($0.key) || lambdaInputTypeVariables.contains($0.key)
        }
    }

    public func resolveCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID? = nil,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]] = [:],
        preserveMemberExtensionAmbiguity: Bool = false,
        resultIsDiscarded: Bool = false,
        ctx: SemaModule
    ) -> ResolvedCall {
        let result = resolveCallWithoutJavaWarnings(
            candidates: candidates, call: call, expectedType: expectedType,
            implicitReceiverType: implicitReceiverType, candidateArgumentTypes: candidateArgumentTypes,
            preserveMemberExtensionAmbiguity: preserveMemberExtensionAmbiguity,
            resultIsDiscarded: resultIsDiscarded, ctx: ctx
        )
        if let chosen = result.chosenCallee {
            warnJavaCollectionsNullableArguments(call, expectedType: expectedType, chosen: chosen, ctx: ctx)
        }
        return result
    }

    private func resolveCallWithoutJavaWarnings(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID? = nil,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]] = [:],
        preserveMemberExtensionAmbiguity: Bool,
        resultIsDiscarded: Bool = false,
        ctx: SemaModule
    ) -> ResolvedCall {
        // --- cache lookup ---
        // Per-candidate overrides, extension ambiguity rules, and discarded-result
        // inference bypass the shared cache because they are call-site specific.
        guard !preserveMemberExtensionAmbiguity,
              !resultIsDiscarded,
              candidateArgumentTypes.isEmpty,
              call.typeAliasConstructor == nil,
              let cache = cacheContext
        else {
            return resolveCallUncached(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                candidateArgumentTypes: candidateArgumentTypes,
                preserveMemberExtensionAmbiguity: preserveMemberExtensionAmbiguity,
                resultIsDiscarded: resultIsDiscarded,
                ctx: ctx
            )
        }
        let defaultArgumentOwners = Dictionary(uniqueKeysWithValues: Set(candidates).compactMap { candidate in
            let inheritedOwner = implicitReceiverType.flatMap {
                ctx.symbols.inheritedDefaultsOwner(for: candidate, receiver: ctx.types.makeNonNullable($0))
            }
            let owner = inheritedOwner ?? ctx.symbols.expectActualDefaultArgumentOwner(for: candidate)
            return owner.map { (candidate, $0) }
        })
        let key = SemaCacheContext.makeCallResolutionKey(
            candidates: candidates,
            call: call,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType,
            symbols: ctx.symbols,
            defaultArgumentOwners: defaultArgumentOwners
        )
        if let cached = cache.cachedCallResolution(for: key) {
            cache.recordCallResolutionHit()
            return cached
        }
        cache.recordCallResolutionMiss()
        let result = resolveCallUncached(
            candidates: candidates,
            call: call,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: [:],
            preserveMemberExtensionAmbiguity: preserveMemberExtensionAmbiguity,
            resultIsDiscarded: false,
            ctx: ctx
        )
        cache.cacheCallResolution(result, for: key)
        return result
    }

    private func resolveCallUncached(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]],
        preserveMemberExtensionAmbiguity: Bool,
        resultIsDiscarded: Bool,
        ctx: SemaModule
    ) -> ResolvedCall {
        let (viable, candidateFailures) = evaluateCandidates(
            candidates,
            call: call,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: candidateArgumentTypes,
            ignoredLambdaReturnTypeArgumentIndices: [],
            resultIsDiscarded: resultIsDiscarded,
            ctx: ctx
        )
        let resolved = selectResult(
            from: viable,
            call: call,
            typeSystem: ctx.types,
            candidateFailures: candidateFailures,
            preserveMemberExtensionAmbiguity: preserveMemberExtensionAmbiguity
        )
        guard resolved.diagnostic?.code == "KSWIFTK-SEMA-0003" else {
            return resolved
        }

        // Error types are subtypes of every type, so unrelated overloads can
        // remain ambiguous even though the argument already has a root error.
        // Retry with Any? to allow a broad recovery overload (such as
        // println(Any?)) to win; keep the original result if the retry fails.
        let errorArgumentTypes = Dictionary(uniqueKeysWithValues: call.args.enumerated().compactMap { index, argument in
            argument.type == ctx.types.errorType ? (index, ctx.types.nullableAnyType) : nil
        })
        guard !errorArgumentTypes.isEmpty else {
            return resolved
        }
        let recoveredCall = call.replacingArgumentTypes(errorArgumentTypes)
        let (recoveredViable, recoveredFailures) = evaluateCandidates(
            candidates,
            call: recoveredCall,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType,
            candidateArgumentTypes: candidateArgumentTypes,
            ignoredLambdaReturnTypeArgumentIndices: [],
            resultIsDiscarded: resultIsDiscarded,
            ctx: ctx
        )
        let recovered = selectResult(
            from: recoveredViable,
            call: recoveredCall,
            typeSystem: ctx.types,
            candidateFailures: recoveredFailures,
            preserveMemberExtensionAmbiguity: preserveMemberExtensionAmbiguity
        )
        return recovered.diagnostic == nil ? recovered : resolved
    }

    private func evaluateCandidates(
        _ candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        candidateArgumentTypes: [SymbolID: [Int: TypeID]],
        ignoredLambdaReturnTypeArgumentIndices: Set<Int>,
        resultIsDiscarded: Bool,
        ctx: SemaModule
    ) -> (viable: [ViableCandidate], failures: [Diagnostic]) {
        let solver = ConstraintSolver()
        var viable: [ViableCandidate] = []
        var failures: [Diagnostic] = []
        for candidate in candidates {
            let candidateCall = call.replacingArgumentTypes(candidateArgumentTypes[candidate] ?? [:])
            let evaluation = evaluateCandidate(
                candidate,
                call: candidateCall,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                ignoredLambdaReturnTypeArgumentIndices: ignoredLambdaReturnTypeArgumentIndices,
                resultIsDiscarded: resultIsDiscarded,
                solver: solver,
                ctx: ctx
            )
            switch evaluation {
            case let .viable(value):
                viable.append(value)
            case let .constraintFailure(diagnostic):
                failures.append(diagnostic)
            case .rejected:
                continue
            }
        }
        return (viable, failures)
    }

    private func evaluateCandidate(
        _ candidate: SymbolID,
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        ignoredLambdaReturnTypeArgumentIndices: Set<Int>,
        resultIsDiscarded: Bool,
        solver: ConstraintSolver,
        ctx: SemaModule
    ) -> CandidateEvaluation {
        guard let symbol = ctx.symbols.symbol(candidate),
              symbol.kind == .function || symbol.kind == .constructor,
              let originalSignature = ctx.symbols.functionSignature(for: candidate)
        else {
            return .rejected
        }

        let aliasConstructor = symbol.kind == .constructor ? call.typeAliasConstructor : nil
        let signature: FunctionSignature
        if let aliasConstructor {
            guard let specialized = typeAliasConstructorSignature(aliasConstructor, original: originalSignature, sema: ctx)
            else { return .rejected }
            signature = specialized
        } else {
            signature = originalSignature
        }

        // An imported object member is already bound to its singleton dispatch
        // receiver, including direct and aliased imports. Derive this per
        // candidate so imports from different objects share an overload set.
        // Member extensions still require their separate extension receiver.
        let candidateImplicitReceiverType: TypeID?
        if call.boundObjectDispatchReceiverCandidates.contains(candidate),
           ctx.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
           let owner = ctx.symbols.parentSymbol(for: candidate),
           let importedReceiver = call.dispatchReceiverTypes.first(where: { receiver in
               guard case let .classType(receiverClass) = ctx.types.kind(of: ctx.types.makeNonNullable(receiver))
               else { return false }
               return ctx.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
           }) {
            // Use the imported singleton type, rather than the declaring
            // supertype's receiver, so generic supertype arguments are applied
            // to inherited members during overload resolution.
            candidateImplicitReceiverType = importedReceiver
        } else if call.boundObjectDispatchReceiverCandidates.contains(candidate),
                  ctx.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                  let owner = ctx.symbols.parentSymbol(for: candidate),
                  ctx.symbols.symbol(owner)?.kind == .object,
                  let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = ctx.types.kind(of: receiverType),
                  receiverClass.classSymbol == owner {
            candidateImplicitReceiverType = receiverType
        } else {
            candidateImplicitReceiverType = implicitReceiverType
        }

        let javaMapArgument = javaCollectionsMapArgument(fqName: symbol.fqName, signature: signature, call: call, ctx: ctx)
        guard javaMapArgument.compatible else { return .rejected }
        let mappedCall = javaMapArgument.replacement.map { call.replacingArgumentTypes([0: $0]) } ?? call
        let call = javaCollectionsCall(mappedCall, fqName: symbol.fqName, signature: signature, ctx: ctx)

        let typeVarBySymbol = ctx.types.makeTypeVarBySymbol(signature.typeParameterSymbols)

        // Apply explicit type argument constraints if provided.
        // For constructors, explicit type args map to the class type params
        // (e.g. ArrayDeque<Int>() — <Int> binds the class's E parameter).
        // For regular functions, only compare against the function's own type
        // params (skip leading class type params inferred from the receiver).
        let funcOwnTypeParamCount = signature.typeParameterSymbols.count - signature.classTypeParameterCount
        let isConstructor = symbol.kind == .constructor
        let constructorCapturedTypeParameterCount: Int = if isConstructor, aliasConstructor == nil,
                                                              let owner = ctx.symbols.parentSymbol(for: candidate) {
            ctx.types.enclosingTypeParameterSymbols(for: owner).count
        } else {
            0
        }
        let constructorOwnTypeParameterCount = max(
            0,
            signature.classTypeParameterCount - constructorCapturedTypeParameterCount
        )
        if !call.explicitTypeArgs.isEmpty {
            let expectedTypeArgCount = isConstructor
                ? (aliasConstructor?.typeParameterSymbols.count ?? constructorOwnTypeParameterCount)
                : funcOwnTypeParamCount
            guard call.explicitTypeArgs.count == expectedTypeArgCount else {
                return .rejected
            }
        }

        // Constructors synthesize their own receiver at the call site, so skip
        // the receiver constraint check that would reject them when there is no
        // implicit receiver in scope (e.g. `Dog()` called from a free function).
        var constraints: [VariableConstraint]
        var capturedOwnerTypeArguments: [TypeVarID: TypeID] = [:]
        if isConstructor {
            constraints = []
            let capturedOwnerArguments: [TypeArg]? = {
                guard constructorCapturedTypeParameterCount > 0,
                      aliasConstructor == nil,
                      let owner = ctx.symbols.parentSymbol(for: candidate)
                else { return nil }
                if let enclosingOwner = ctx.symbols.parentSymbol(for: owner),
                   let outerReceiverType = implicitReceiverType,
                   let receiverClassType = resolveClassType(outerReceiverType, sema: ctx),
                   let arguments = ctx.types.liftedNominalSupertypeArgs(
                       from: receiverClassType,
                       to: enclosingOwner
                   )
                {
                    return arguments
                }
                guard let expectedType,
                      let expectedClassType = resolveClassType(expectedType, sema: ctx),
                      let arguments = ctx.types.liftedNominalSupertypeArgs(
                          from: expectedClassType,
                          to: owner
                      )
                else {
                    return nil
                }
                return arguments
            }()
            if constructorCapturedTypeParameterCount > 0,
               aliasConstructor == nil,
               let owner = ctx.symbols.parentSymbol(for: candidate),
               let ownerArguments = capturedOwnerArguments
            {
                let enclosingTypeParameterSymbols = ctx.types.enclosingTypeParameterSymbols(for: owner)
                let variables = ctx.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                for (index, typeParameter) in enclosingTypeParameterSymbols.enumerated()
                where index < constructorCapturedTypeParameterCount && index < ownerArguments.count {
                    guard let variable = variables[typeParameter] else { continue }
                    let argumentType: TypeID
                    switch ownerArguments[index] {
                    case let .invariant(type):
                        argumentType = type
                    case let .out(type):
                        argumentType = ctx.types.makeCapturedType(
                            parameter: typeParameter,
                            lower: ctx.types.nothingType,
                            upper: type,
                            writeForbidden: true
                        )
                    case let .in(type):
                        let bounds = ctx.types.declaredUpperBounds(for: typeParameter)
                        argumentType = ctx.types.makeCapturedType(
                            parameter: typeParameter,
                            lower: type,
                            upper: bounds.isEmpty ? ctx.types.nullableAnyType : ctx.types.glb(bounds)
                        )
                    case .star:
                        let bounds = ctx.types.declaredUpperBounds(for: typeParameter)
                        argumentType = ctx.types.makeCapturedType(
                            parameter: typeParameter,
                            lower: ctx.types.nothingType,
                            upper: bounds.isEmpty ? ctx.types.nullableAnyType : ctx.types.glb(bounds),
                            writeForbidden: true
                        )
                    }
                    capturedOwnerTypeArguments[variable] = argumentType
                    constraints.append(VariableConstraint(
                        kind: .equal,
                        left: .variable(variable),
                        right: .type(argumentType),
                        blameRange: call.range
                    ))
                }
            }
        } else {
            guard let receiverConstraints = buildReceiverConstraints(
                signature: signature,
                implicitReceiverType: candidateImplicitReceiverType,
                explicitTypeArgs: call.explicitTypeArgs,
                typeVarBySymbol: typeVarBySymbol,
                range: call.range,
                typeSystem: ctx.types
            ) else {
                return .rejected
            }
            constraints = receiverConstraints
        }

        // An alias may use type parameters from the enclosing class even though
        // an inner-class type stores only its own arguments. A member-style call
        // supplies the enclosing instance separately, so use it to infer the
        // alias parameters for those outer slots.
        if isConstructor,
           let aliasConstructor,
           let outerReceiverType = aliasConstructor.innerOuterReceiverType,
           case let .classType(aliasTarget) = ctx.types.kind(of: aliasConstructor.expandedType),
           ctx.symbols.symbol(aliasTarget.classSymbol)?.flags.contains(.innerClass) == true,
           let outerOwner = ctx.symbols.parentSymbol(for: aliasTarget.classSymbol)
        {
            let outerParameterCount = ctx.types.nominalTypeParameterSymbols(for: outerOwner).count
            if outerParameterCount > 0,
               case let .classType(receiverClass) = ctx.types.kind(of: ctx.types.makeNonNullable(outerReceiverType)),
               let receiverOuterArgs = ctx.types.liftedNominalSupertypeArgs(
                   from: receiverClass.classSymbol,
                   childArgs: receiverClass.args,
                   to: outerOwner
               ),
               receiverOuterArgs.count >= outerParameterCount
            {
                for (index, aliasParameter) in aliasConstructor.outerTypeParameterSymbols
                    .prefix(outerParameterCount).enumerated()
                {
                    guard let aliasVariable = typeVarBySymbol[aliasParameter] else { continue }
                    let receiverArgument: TypeID
                    switch receiverOuterArgs[index] {
                    case let .invariant(type), let .out(type), let .in(type): receiverArgument = type
                    case .star: continue
                    }
                    constraints.append(VariableConstraint(
                        kind: .equal,
                        left: .variable(aliasVariable),
                        right: .type(receiverArgument),
                        blameRange: call.range
                    ))
                }
            }
        }

        // Member extensions infer class parameters from their dispatch receiver;
        // the extension receiver still constrains the declared receiver type.
        let memberExtensionOwner = ctx.symbols.memberExtensionOwnerSymbol(for: candidate)
        let unapproximatedClassReceiverType: TypeID? = if let owner = memberExtensionOwner {
            call.dispatchReceiverTypes.first { receiver in
                guard case let .classType(receiverClass) = ctx.types.kind(
                    of: ctx.types.makeNonNullable(receiver)
                ) else { return false }
                return ctx.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
            }
        } else {
            candidateImplicitReceiverType
        }
        let classReceiverType = unapproximatedClassReceiverType.map { ctx.types.capturedReadableUpperBound(of: $0) }

        func nominalReceiverClassType(in type: TypeID, for owner: SymbolID) -> ClassType? {
            func matchingClassType(_ type: TypeID) -> ClassType? {
                guard case let .classType(classType) = ctx.types.kind(
                    of: ctx.types.makeNonNullable(type)
                ),
                    ctx.types.isNominalSubtypeSymbol(classType.classSymbol, of: owner)
                else {
                    return nil
                }
                return classType
            }

            switch ctx.types.kind(of: ctx.types.makeNonNullable(type)) {
            case let .intersection(parts):
                for part in parts {
                    if let classType = matchingClassType(part) {
                        return classType
                    }
                }
                return nil
            default:
                return matchingClassType(type)
            }
        }

        var starProjectedReceiverParameters: Set<SymbolID> = []
        let receiverOwner = memberExtensionOwner ?? ctx.symbols.parentSymbol(for: candidate)
        let matchingReceiverClassType: ClassType? = if let classReceiverType, let receiverOwner {
            nominalReceiverClassType(in: classReceiverType, for: receiverOwner)
        } else {
            nil
        }
        // A nominal member's leading type parameters belong to the declaring
        // class/interface. Constrain them from the dispatch receiver, not an
        // unrelated extension receiver. Otherwise an inherited
        // member such as OpenEndRange<T>.contains(T) can incorrectly infer T
        // from a Byte/Long argument instead of Int from IntRange, making an
        // inapplicable member steal the call from an exact user extension.
        if !isConstructor,
           signature.classTypeParameterCount > 0,
           let classReceiverType,
           (isNominalMemberFunction(candidate, typeSystem: ctx.types) || memberExtensionOwner != nil),
           let owner = receiverOwner,
           memberExtensionOwner != nil || signature.receiverType == nil || matchingReceiverClassType != nil
        {
            let ownerArguments: [TypeArg] = signature.typeParameterSymbols
                .prefix(signature.classTypeParameterCount)
                .map { typeParameter in
                    .invariant(ctx.types.make(.typeParam(TypeParamType(
                        symbol: typeParameter,
                        nullability: .nonNull
                    ))))
                }
            let enclosingOwnerTypeParameterCount = ctx.types.enclosingTypeParameterSymbols(for: owner).count
            let ownerType = ctx.types.make(.classType(ClassType(
                classSymbol: owner,
                args: Array(ownerArguments.dropFirst(enclosingOwnerTypeParameterCount)),
                enclosingTypeArgs: Array(ownerArguments.prefix(enclosingOwnerTypeParameterCount)),
                nullability: .nonNull
            )))
            let receiverOwnerType: TypeID = {
                guard let receiverClassType = matchingReceiverClassType,
                      let liftedArguments = ctx.types.liftedNominalSupertypeArgs(
                          from: receiverClassType,
                          to: owner
                      )
                else {
                    return classReceiverType
                }
                return ctx.types.make(.classType(ClassType(
                    classSymbol: owner,
                    args: Array(liftedArguments.dropFirst(enclosingOwnerTypeParameterCount)),
                    enclosingTypeArgs: Array(liftedArguments.prefix(enclosingOwnerTypeParameterCount)),
                    nullability: .nonNull
                )))
            }()
            if case let .classType(receiverOwner) = ctx.types.kind(of: receiverOwnerType) {
                let receiverOwnerArguments = ctx.types.allTypeArguments(for: receiverOwner)
                let methodBounds = Array(signature.typeParameterUpperBoundsList
                    .dropFirst(signature.classTypeParameterCount).joined())
                    + signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount).flatMap {
                        ctx.symbols.typeParameterUpperBounds(for: $0)
                    }
                for (parameter, argument) in zip(
                    signature.typeParameterSymbols.prefix(signature.classTypeParameterCount), receiverOwnerArguments
                ) {
                    if case .star = argument,
                       !signature.parameterTypes.contains(where: {
                           ctx.types.typeContainsTypeParam($0, symbol: parameter)
                       }),
                       !methodBounds.contains(where: {
                           ctx.types.typeContainsTypeParam($0, symbol: parameter)
                       })
                    {
                        starProjectedReceiverParameters.insert(parameter)
                    }
                }
            }
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: receiverOwnerType,
                supertype: ownerType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: ctx.types,
                blameRange: call.range
            ))
            if signature.receiverType != nil,
               case let .classType(receiverOwner) = ctx.types.kind(of: receiverOwnerType),
               receiverOwner.classSymbol == owner
            {
                let receiverOwnerArguments = ctx.types.allTypeArguments(for: receiverOwner)
                for (parameter, argument) in zip(
                    signature.typeParameterSymbols.prefix(signature.classTypeParameterCount),
                    receiverOwnerArguments
                ) {
                    guard let variable = typeVarBySymbol[parameter] else { continue }
                    let type: TypeID
                    switch argument {
                    case let .invariant(value), let .out(value), let .in(value): type = value
                    case .star: continue
                    }
                    constraints.append(VariableConstraint(
                        kind: .equal, left: .variable(variable), right: .type(type), blameRange: call.range
                    ))
                }
            }
        }

        let inheritedDefaultArgumentOwner = candidateImplicitReceiverType.flatMap {
            ctx.symbols.inheritedDefaultsOwner(for: candidate, receiver: ctx.types.makeNonNullable($0))
        }
        let defaultArgumentOwner = inheritedDefaultArgumentOwner
            ?? ctx.symbols.expectActualDefaultArgumentOwner(for: candidate)
        let inheritedDefaultValues = defaultArgumentOwner.flatMap {
            ctx.symbols.functionSignature(for: $0)?.valueParameterHasDefaultValues
        }
        guard let parameterMapping = buildParameterMapping(
            signature: signature,
            callArgs: call.args,
            symbols: ctx.symbols,
            typeSystem: ctx.types,
            inheritedDefaultValues: inheritedDefaultValues
        ) else {
            return .rejected
        }

        // Add equality constraints for explicit type arguments.
        // For constructors, explicit type args bind class type params (offset 0).
        // For regular functions, map to function-own type params (after class type params).
        let typeArgOffset = isConstructor
            ? (aliasConstructor == nil ? constructorCapturedTypeParameterCount : 0)
            : signature.classTypeParameterCount
        var explicitTypeSubstitution: [TypeVarID: TypeID] = [:]
        for (index, explicitArg) in call.explicitTypeArgs.enumerated() {
            guard explicitArg != TypeID.invalid else { continue }
            let typeParamSymbol = aliasConstructor?.typeParameterSymbols[index]
                ?? signature.typeParameterSymbols[typeArgOffset + index]
            if let typeVar = typeVarBySymbol[typeParamSymbol] {
                explicitTypeSubstitution[typeVar] = explicitArg
                constraints.append(
                    VariableConstraint(
                        kind: .equal,
                        left: .variable(typeVar),
                        right: .type(explicitArg),
                        blameRange: call.range
                    )
                )
            }
        }
        // Unsuffixed integer literals can adopt a primitive type already
        // determined by this candidate's concrete inputs. Keep them out of a
        // preliminary solve so their default Int/UInt does not widen T before
        // the literal has a context. The authoritative solve below still
        // checks every input, explicit binding and declared bound.
        var literalTypeSubstitution = explicitTypeSubstitution
        let literalIndices = Set(call.args.indices.filter { index in
            call.args[index].signedIntegerLiteral != nil || call.args[index].unsignedIntegerLiteral != nil
        })
        if !typeVarBySymbol.isEmpty, !literalIndices.isEmpty {
            var nonLiteralConstraints = constraints
            if appendArgumentConstraints(
                to: &nonLiteralConstraints,
                call: call,
                parameterMapping: parameterMapping,
                signature: signature,
                typeVarBySymbol: typeVarBySymbol,
                explicitTypeSubstitution: explicitTypeSubstitution,
                ignoredLambdaReturnTypeArgumentIndices: ignoredLambdaReturnTypeArgumentIndices,
                ignoredIntegerLiteralArgumentIndices: literalIndices,
                sema: ctx
            ), case let .success(partial) = solveConstraints(
                nonLiteralConstraints, solver: solver, typeSystem: ctx.types
            ) {
                let concreteInputVariables = Set(nonLiteralConstraints.compactMap { constraint -> TypeVarID? in
                    if case .type = constraint.left, case let .variable(variable) = constraint.right {
                        return variable
                    }
                    if constraint.kind == .equal, case let .variable(variable) = constraint.left,
                       case .type = constraint.right {
                        return variable
                    }
                    return nil
                })
                for (variable, type) in partial where explicitTypeSubstitution[variable] == nil
                    && concreteInputVariables.contains(variable) {
                    guard case .primitive = ctx.types.kind(of: ctx.types.makeNonNullable(type)) else { continue }
                    literalTypeSubstitution[variable] = type
                }

                // If no concrete input inferred this parameter, an unambiguous
                // integer primitive upper bound can still contextualize a
                // constant literal. The normal solve and bound validation
                // below remain authoritative, including the literal's range.
                var boundSubstitution = partial
                for (variable, type) in explicitTypeSubstitution {
                    boundSubstitution[variable] = type
                }
                for literalIndex in literalIndices {
                    guard let parameterIndex = parameterMapping[literalIndex],
                          signature.parameterTypes.indices.contains(parameterIndex),
                          case let .typeParam(parameter) = ctx.types.kind(of: ctx.types.makeNonNullable(
                              signature.parameterTypes[parameterIndex]
                          )),
                          let variable = typeVarBySymbol[parameter.symbol],
                          explicitTypeSubstitution[variable] == nil,
                          literalTypeSubstitution[variable] == nil,
                          partial[variable] == nil || partial[variable] == ctx.types.errorType,
                          let typeParameterIndex = signature.typeParameterSymbols.firstIndex(of: parameter.symbol)
                    else { continue }

                    let signatureBounds = typeParameterIndex < signature.typeParameterUpperBoundsList.count
                        ? signature.typeParameterUpperBoundsList[typeParameterIndex] : []
                    let symbolBounds = ctx.symbols.typeParameterUpperBounds(for: parameter.symbol)
                    let upperBounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
                    var integerPrimitiveBounds: [TypeID] = []
                    for upperBound in upperBounds {
                        let substitutedBound = ctx.types.makeNonNullable(ctx.types.substituteTypeParameters(
                            in: upperBound,
                            substitution: boundSubstitution,
                            typeVarBySymbol: typeVarBySymbol
                        ))
                        guard case let .primitive(primitive, _) = ctx.types.kind(of: substitutedBound) else {
                            continue
                        }
                        switch primitive {
                        case .byte, .short, .int, .long, .ubyte, .ushort, .uint, .ulong:
                            if !integerPrimitiveBounds.contains(substitutedBound) {
                                integerPrimitiveBounds.append(substitutedBound)
                            }
                        default:
                            continue
                        }
                    }
                    if integerPrimitiveBounds.count == 1, let bound = integerPrimitiveBounds.first {
                        literalTypeSubstitution[variable] = bound
                    }
                }
            }
        }
        guard appendArgumentConstraints(
            to: &constraints,
            call: call,
            parameterMapping: parameterMapping,
            signature: signature,
            typeVarBySymbol: typeVarBySymbol,
            explicitTypeSubstitution: literalTypeSubstitution,
            ignoredLambdaReturnTypeArgumentIndices: ignoredLambdaReturnTypeArgumentIndices,
            sema: ctx
        ) else {
            return .rejected
        }
        var inputConstraints = constraints

        // An annotated Unit callback constrains call variables from
        // above. Include their concrete declaration bounds before solving:
        // `(String) -> Unit` can satisfy `(T : Number) -> Unit` with an
        // intersection, even though choosing String alone violates the bound.
        var callbackInputUpperBounds: [TypeVarID: [TypeID]] = [:]
        if !typeVarBySymbol.isEmpty {
            for (argumentIndex, parameterIndex) in parameterMapping {
                guard case let .functionType(parameter) = ctx.types.kind(of: signature.parameterTypes[parameterIndex]),
                      case let .functionType(argument) = ctx.types.kind(of: call.args[argumentIndex].type),
                      parameter.returnType == ctx.types.unitType || argument.returnType == ctx.types.unitType,
                      parameter.params.count == argument.params.count
                else { continue }
                for (expectedInput, actualInput) in zip(parameter.params, argument.params) {
                    let inputBounds = decomposeSubtypeConstraint(
                        subtype: expectedInput, supertype: actualInput,
                        typeVarBySymbol: typeVarBySymbol, typeSystem: ctx.types, blameRange: call.range
                    )
                    for constraint in inputBounds {
                        guard constraint.kind == .subtype,
                              case let .variable(variable) = constraint.left,
                              case let .type(bound) = constraint.right,
                              !containsTypeVariable(bound, typeVarBySymbol: typeVarBySymbol, typeSystem: ctx.types)
                        else { continue }
                        callbackInputUpperBounds[variable, default: []].append(bound)
                    }
                }
            }
            for (index, symbol) in signature.typeParameterSymbols.enumerated() {
                guard let variable = typeVarBySymbol[symbol],
                      let inputBounds = callbackInputUpperBounds[variable]
                else { continue }
                let signatureBounds = index < signature.typeParameterUpperBoundsList.count
                    ? signature.typeParameterUpperBoundsList[index] : []
                let symbolBounds = ctx.symbols.typeParameterUpperBounds(for: symbol)
                for bound in signatureBounds + symbolBounds.filter({ !signatureBounds.contains($0) }) {
                    guard !containsTypeVariable(bound, typeVarBySymbol: typeVarBySymbol, typeSystem: ctx.types),
                          !inputBounds.contains(where: { ctx.types.isSubtype($0, bound) })
                    else { continue }
                    constraints.append(VariableConstraint(
                        kind: .subtype, left: .variable(variable), right: .type(bound), blameRange: call.range
                    ))
                }
            }
        }

        // Upper bounds can relate two function type parameters (for example
        // `where C : Collection<*>, C : R`). Add those relationships to the
        // inference graph before solving so a receiver lower bound can widen
        // the result type as required by Kotlin's self-type extensions.
        func shouldDeferNullableDependentBoundCheck(_ bound: TypeID, for parameter: SymbolID) -> Bool {
            guard case let .typeParam(boundParameter) = ctx.types.kind(of: bound),
                  boundParameter.nullability != .nonNull,
                  let parameterVariable = typeVarBySymbol[parameter],
                  let boundVariable = typeVarBySymbol[boundParameter.symbol]
            else {
                return false
            }
            return explicitTypeSubstitution[parameterVariable] != nil
                && explicitTypeSubstitution[boundVariable] != nil
        }

        for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
            guard index < signature.typeParameterUpperBoundsList.count else {
                continue
            }
            let signatureBounds = signature.typeParameterUpperBoundsList[index]
            let symbolBounds = ctx.symbols.typeParameterUpperBounds(for: typeParamSymbol)
            let upperBounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
            for upperBound in upperBounds {
                guard case let .typeParam(boundTypeParam) = ctx.types.kind(of: upperBound),
                      let typeParamVariable = typeVarBySymbol[typeParamSymbol],
                      let boundTypeParamVariable = typeVarBySymbol[boundTypeParam.symbol]
                else {
                    continue
                }
                // A nullable dependent bound such as `E : T?` cannot be
                // represented by this variable-to-variable edge without
                // dropping nullability. Explicit arguments are checked against
                // the fully substituted bound after solving.
                if shouldDeferNullableDependentBoundCheck(upperBound, for: typeParamSymbol) {
                    continue
                }
                constraints.append(VariableConstraint(
                    kind: .subtype,
                    left: .variable(typeParamVariable),
                    right: .variable(boundTypeParamVariable),
                    blameRange: call.range
                ))
            }
        }

        if resultIsDiscarded {
            let inputTypes = signature.parameterTypes
                + signature.contextReceiverTypes
                + signature.contextParameterTypes
                + (signature.receiverType.map { [$0] } ?? [])
            for (index, typeParamSymbol) in signature.typeParameterSymbols.enumerated() {
                guard let typeVariable = typeVarBySymbol[typeParamSymbol],
                      explicitTypeSubstitution[typeVariable] == nil,
                      containsTypeVariable(
                          signature.returnType,
                          typeVarBySymbol: [typeParamSymbol: typeVariable],
                          typeSystem: ctx.types
                      ),
                      !inputTypes.contains(where: {
                          containsTypeVariable(
                              $0,
                              typeVarBySymbol: [typeParamSymbol: typeVariable],
                              typeSystem: ctx.types
                          )
                      })
                else {
                    continue
                }

                var defaultUpperBounds = index < signature.typeParameterUpperBoundsList.count
                    ? signature.typeParameterUpperBoundsList[index]
                    : []
                defaultUpperBounds.append(contentsOf: ctx.symbols.typeParameterUpperBounds(for: typeParamSymbol)
                    .filter { !defaultUpperBounds.contains($0) })
                if defaultUpperBounds.isEmpty {
                    defaultUpperBounds = [ctx.types.nullableAnyType]
                }
                constraints.append(contentsOf: defaultUpperBounds.map { upperBound in
                    VariableConstraint(
                        kind: .subtype,
                        left: .variable(typeVariable),
                        right: .type(upperBound),
                        blameRange: call.range
                    )
                })
            }
        }

        // Kotlin's Unit-coercion rule: a call whose result is used where Unit is
        // expected (e.g. the trailing expression of a `(T) -> Unit` lambda body,
        // such as `also { it.append(x) }`) does not need its return type to be
        // Unit — the value is simply discarded. Skip the return-type constraint
        // in that case so overload candidates aren't rejected solely because
        // none of them happen to return Unit.
        func hasInferredNonNullBoundedReturnParameter() -> Bool {
            guard let expectedType,
                  expectedType != ctx.types.unitType,
                  ctx.types.nullability(of: expectedType) != .nonNull,
                  case let .typeParam(returnParameter) = ctx.types.kind(of: signature.returnType),
                  let index = signature.typeParameterSymbols.firstIndex(of: returnParameter.symbol),
                  let typeVariable = typeVarBySymbol[returnParameter.symbol],
                  explicitTypeSubstitution[typeVariable] == nil
            else {
                return false
            }

            let signatureBounds = index < signature.typeParameterUpperBoundsList.count
                ? signature.typeParameterUpperBoundsList[index]
                : []
            let symbolBounds = ctx.symbols.typeParameterUpperBounds(for: returnParameter.symbol)
            let upperBounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
            return upperBounds.contains(where: ctx.types.isDefinitelyNonNull)
        }

        if let expectedType, expectedType != ctx.types.unitType {
            if call.elvisLhsExpectedTypeHint {
                let methodTypeParameters = signature.typeParameterSymbols.dropFirst(
                    signature.classTypeParameterCount
                )
                let methodTypeVarBySymbol = typeVarBySymbol.filter { symbol, _ in
                    methodTypeParameters.contains(symbol)
                }
                if containsTypeVariable(
                    signature.returnType,
                    typeVarBySymbol: methodTypeVarBySymbol,
                    typeSystem: ctx.types
                ) {
                    let returnTypeHint = ctx.types.makeNonNullable(signature.returnType)
                    let expectedTypeHint = ctx.types.makeNonNullable(expectedType)
                    let returnDecomposed = decomposeSubtypeConstraint(
                        subtype: returnTypeHint,
                        supertype: expectedTypeHint,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: ctx.types,
                        blameRange: call.range
                    )
                    constraints.append(contentsOf: returnDecomposed)
                    inputConstraints.append(contentsOf: returnDecomposed)
                }
            } else if hasInferredNonNullBoundedReturnParameter() {
                // A non-null upper bound lets a call infer from the non-null
                // projection of a nullable expected type while preserving the
                // declared upper-bound check after inference.
                let returnTypeHint = ctx.types.makeNonNullable(signature.returnType)
                let expectedTypeHint = ctx.types.makeNonNullable(expectedType)
                let returnDecomposed = decomposeSubtypeConstraint(
                    subtype: returnTypeHint,
                    supertype: expectedTypeHint,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: ctx.types,
                    blameRange: call.range
                )
                constraints.append(contentsOf: returnDecomposed)
                inputConstraints.append(contentsOf: returnDecomposed)
            } else {
                let returnDecomposed = decomposeSubtypeConstraint(
                    subtype: signature.returnType,
                    supertype: expectedType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: ctx.types,
                    blameRange: call.range
                )
                constraints.append(contentsOf: returnDecomposed)
                inputConstraints.append(contentsOf: returnDecomposed)
            }
        }

        let constraintsBeforeElvisRhsHint = constraints
        var elvisRhsHintConstraints: [VariableConstraint] = []
        if let expectedTypeHint = call.elvisRhsCallResultTypeHint {
            let methodTypeParameters = signature.typeParameterSymbols.dropFirst(
                signature.classTypeParameterCount
            )
            let methodTypeVarBySymbol = typeVarBySymbol.filter { symbol, _ in
                methodTypeParameters.contains(symbol)
            }
            if containsTypeVariable(
                signature.returnType,
                typeVarBySymbol: methodTypeVarBySymbol,
                typeSystem: ctx.types
            ), case let .success(inputSubstitution) = solveConstraints(
                constraints, solver: solver, typeSystem: ctx.types
            ) {
                let inputConstrainedVariables = inputConstrainedTypeVariables(in: inputConstraints)
                let resultTypeHint = ctx.types.makeNonNullable(expectedTypeHint)
                let returnTypeHint = ctx.types.makeNonNullable(signature.returnType)
                let decomposedHints = decomposeSubtypeConstraint(
                    subtype: returnTypeHint,
                    supertype: resultTypeHint,
                    typeVarBySymbol: methodTypeVarBySymbol,
                    typeSystem: ctx.types,
                    blameRange: call.range
                )
                for hint in decomposedHints {
                    guard let left = replacingInputVariables(
                        in: hint.left,
                        constrainedVariables: inputConstrainedVariables,
                        substitution: inputSubstitution
                    ), let right = replacingInputVariables(
                        in: hint.right,
                        constrainedVariables: inputConstrainedVariables,
                        substitution: inputSubstitution
                    ) else {
                        continue
                    }
                    // The LHS type is only a seed for unresolved variables.
                    // Constraints that now mention only input-inferred types
                    // cannot refine the call, so they must not reject a valid
                    // heterogeneous Elvis LUB.
                    guard isVariable(left) || isVariable(right) else {
                        continue
                    }
                    elvisRhsHintConstraints.append(VariableConstraint(
                        kind: hint.kind,
                        left: left,
                        right: right,
                        blameRange: hint.blameRange
                    ))
                }
                constraints.append(contentsOf: elvisRhsHintConstraints)
            }
        }

        var solveResult = solveConstraints(
            constraints,
            solver: solver,
            typeSystem: ctx.types
        )
        if !elvisRhsHintConstraints.isEmpty {
            switch solveResult {
            case .success:
                break
            case .constraintFailure, .rejected:
                // A type hint cannot make an otherwise valid call inapplicable.
                // Retry without it; any still-unresolved type variable will
                // receive the ordinary inference diagnostic below.
                constraints = constraintsBeforeElvisRhsHint
                solveResult = solveConstraints(
                    constraints,
                    solver: solver,
                    typeSystem: ctx.types
                )
            }
        }
        // Infer dependent parameters from concrete upper-bound projections, e.g.
        // R = IntRange and R : ClosedRange<T> imply T = Int, even for a null argument.
        for _ in 0 ..< signature.typeParameterSymbols.count {
            guard case let .success(partial) = solveResult else { break }
            var added = false
            for (index, symbol) in signature.typeParameterSymbols.enumerated() {
                guard let variable = typeVarBySymbol[symbol],
                      let inferred = partial[variable],
                      inferred != ctx.types.errorType
                else { continue }
                let signatureBounds = index < signature.typeParameterUpperBoundsList.count
                    ? signature.typeParameterUpperBoundsList[index] : []
                let symbolBounds = ctx.symbols.typeParameterUpperBounds(for: symbol)
                let bounds = signatureBounds + symbolBounds.filter { !signatureBounds.contains($0) }
                let dependentVariables = typeVarBySymbol.filter { $0.key != symbol }
                for bound in bounds where containsTypeVariable(
                    bound, typeVarBySymbol: dependentVariables, typeSystem: ctx.types
                ) {
                    if shouldDeferNullableDependentBoundCheck(bound, for: symbol) {
                        continue
                    }
                    let projected = decomposeSubtypeConstraint(
                        subtype: inferred,
                        supertype: bound,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: ctx.types,
                        blameRange: call.range
                    )
                    for constraint in projected where !constraints.contains(where: {
                        $0.kind == constraint.kind && $0.left == constraint.left && $0.right == constraint.right
                    }) {
                        constraints.append(constraint)
                        added = true
                    }
                }
            }
            guard added else { break }
            solveResult = solveConstraints(constraints, solver: solver, typeSystem: ctx.types)
        }
        var substitution: [TypeVarID: TypeID]
        switch solveResult {
        case let .success(value):
            substitution = javaCollectionsSubstitution(value, fqName: symbol.fqName, signature: signature, ctx: ctx)
        case let .constraintFailure(diagnostic):
            return .constraintFailure(diagnostic)
        case .rejected:
            return .rejected
        }
        substitution.merge(capturedOwnerTypeArguments, uniquingKeysWith: { _, captured in captured })

        // A variable constrained only by itself — e.g. `FlowCollector<R>` in
        // `transform`'s signature matched against a receiver lambda whose
        // receiver type argument is that same type parameter — yields a
        // `V <: V` tautology and stays unbound. Anchor it to its own type
        // parameter so the caller's parameter flows through to the result,
        // instead of reporting the variable as uninferrable.
        for constraint in constraints {
            guard constraint.kind == .subtype,
                  case let .variable(left) = constraint.left,
                  case let .variable(right) = constraint.right,
                  left == right,
                  substitution[left] == nil || substitution[left] == ctx.types.errorType,
                  let symbol = typeVarBySymbol.first(where: { $0.value == left })?.key
            else {
                continue
            }
            substitution[left] = ctx.types.make(.typeParam(TypeParamType(
                symbol: symbol,
                nullability: .nonNull
            )))
        }

        guard satisfiesOnlyInputTypes(
            signature: signature,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol,
            inputConstraints: inputConstraints,
            ctx: ctx
        ) else {
            return .rejected
        }

        if let inferDiag = checkForUninferredTypeVariables(
            signature: signature,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol,
            range: call.range,
            typeSystem: ctx.types
        ) {
            return .constraintFailure(inferDiag)
        }

        if let boundViolation = checkTypeParameterBounds(
            signature: signature,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol,
            starProjectedReceiverParameters: starProjectedReceiverParameters,
            range: call.range,
            ctx: ctx
        ) {
            return .constraintFailure(boundViolation)
        }

        let bindingSubstitution: [TypeVarID: TypeID]
        if let aliasConstructor {
            bindingSubstitution = typeAliasConstructorBindingArguments(
                aliasConstructor, original: originalSignature, specialized: signature,
                substitution: substitution, types: ctx.types
            )
            if let boundViolation = checkTypeParameterBounds(
                signature: originalSignature,
                substitution: bindingSubstitution,
                typeVarBySymbol: ctx.types.makeTypeVarBySymbol(originalSignature.typeParameterSymbols),
                range: call.range,
                ctx: ctx
            ) {
                return .constraintFailure(boundViolation)
            }
        } else {
            bindingSubstitution = substitution
        }

        let instantiatedParameterTypes: [TypeID] = call.args.indices.compactMap { argIndex in
            guard let paramIndex = parameterMapping[argIndex],
                  paramIndex >= 0,
                  paramIndex < signature.parameterTypes.count
            else {
                return nil
            }
            return ctx.types.substituteTypeParameters(
                in: signature.parameterTypes[paramIndex],
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
        }
        guard instantiatedParameterTypes.count == call.args.count else {
            return .rejected
        }

        let instantiatedReceiverType = signature.receiverType.map {
            ctx.types.substituteTypeParameters(
                in: $0,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
        }

        return .viable(ViableCandidate(
            symbol: candidate,
            signature: signature,
            instantiatedReceiverType: instantiatedReceiverType,
            instantiatedParameterTypes: instantiatedParameterTypes,
            substitutedTypeArguments: bindingSubstitution,
            parameterMapping: parameterMapping,
            defaultArgumentOwner: defaultArgumentOwner,
            effectiveDefaultValues: inheritedDefaultValues ?? signature.valueParameterHasDefaultValues,
            usesVararg: Self.normalizeFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count).contains(true),
            isLowPriorityInOverloadResolution: ctx.symbols.annotations(for: candidate).contains {
                $0.annotationFQName == "kotlin.internal.LowPriorityInOverloadResolution"
            }
        ))
    }

    private func buildReceiverConstraints(
        signature: FunctionSignature,
        implicitReceiverType: TypeID?,
        explicitTypeArgs: [TypeID],
        typeVarBySymbol: [SymbolID: TypeVarID],
        range: SourceRange,
        typeSystem: TypeSystem
    ) -> [VariableConstraint]? {
        guard let receiverType = signature.receiverType else {
            return []
        }
        guard let implicitReceiverType else {
            return nil
        }
        // Fixed KClass receivers must retain the complete projection relation.
        // Decomposing their arguments would turn an in/out combination into
        // equality and discard the declaration's upper bound.
        let isKClassReceiver: Bool = switch typeSystem.kind(of: receiverType) {
        case .kClassType: true
        case let .classType(classType): classType.classSymbol == typeSystem.kClassInterfaceSymbol
        default: false
        }
        if isKClassReceiver,
           !containsTypeVariable(receiverType, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem)
        {
            return [VariableConstraint(
                kind: .subtype, left: .type(implicitReceiverType), right: .type(receiverType),
                blameRange: range
            )]
        }
        // Read-only extensions can use the projection's upper bound, but keep
        // the capture identity so subsequent operations still check its bounds.
        if explicitTypeArgs.isEmpty,
           signature.reifiedTypeParameterIndices.isEmpty,
           case let .classType(actualClass) = typeSystem.kind(of: implicitReceiverType),
           actualClass.classSymbol == typeSystem.kClassInterfaceSymbol,
           actualClass.args.count == 1,
           case .out = actualClass.args[0],
           case let .kClassType(declaredKClass) = typeSystem.kind(of: receiverType),
           case let .typeParam(parameter) = typeSystem.kind(of: declaredKClass.argument),
           typeVarBySymbol[parameter.symbol] != nil,
           !(signature.parameterTypes + signature.contextReceiverTypes).contains(where: {
               typeSystem.typeContainsTypeParam($0, symbol: parameter.symbol)
           }),
           !signature.typeParameterSymbols.enumerated().contains(where: { index, symbol in
               guard symbol != parameter.symbol else { return false }
               let bounds = (index < signature.typeParameterUpperBoundsList.count
                   ? signature.typeParameterUpperBoundsList[index] : [])
                   + (typeSystem.symbolTable?.typeParameterUpperBounds(for: symbol) ?? [])
               return bounds.contains { typeSystem.typeContainsTypeParam($0, symbol: parameter.symbol) }
           }),
           typeSystem.canApproximateCapturedUpperBound(
               in: signature.returnType, parameter: parameter.symbol
           )
        {
            return decomposeSubtypeConstraint(
                subtype: implicitReceiverType,
                supertype: receiverType, typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem, blameRange: range
            )
        }
        // Infer a receiver parameter from the receiver itself, not a LUB of its
        // separate bounds. Dependent bound arguments are projected after solving.
        if case let .typeParam(parameter) = typeSystem.kind(of: receiverType),
           typeVarBySymbol[parameter.symbol] != nil
        {
            return decomposeSubtypeConstraint(
                subtype: implicitReceiverType, supertype: receiverType,
                typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem,
                blameRange: range
            )
        }
        // Use decomposeSubtypeConstraint to properly extract type variables
        // from generic receiver types (e.g. Class<T>) so the solver can
        // infer type arguments from projected receivers (e.g. Class<out Any>).
        // A receiver can itself be a type parameter with a non-recursive upper
        // bound (for example `M : MutableMap<in K, in V>`). Resolve the member
        // against that bound so calls such as `destination.put(key, value)`
        // infer the member's class type parameters from the projected bound.
        // Star-projected bounds erase those member type arguments, so preserve
        // the direct receiver constraint instead of inferring them as Any?.
        if case let .typeParam(typeParam) = typeSystem.kind(of: implicitReceiverType),
           typeVarBySymbol[typeParam.symbol] == nil,
           containsTypeVariable(receiverType, typeVarBySymbol: typeVarBySymbol, typeSystem: typeSystem),
           let symbols = typeSystem.symbolTable
        {
            let upperBounds = typeParam.capture.map { [$0.upper] }
                ?? symbols.typeParameterUpperBounds(for: typeParam.symbol)
            let matchingBounds = upperBounds.filter { upperBound in
                guard !typeSystem.typeContainsTypeParam(upperBound, symbol: typeParam.symbol),
                      !containsStarProjection(upperBound, typeSystem: typeSystem)
                else {
                    return false
                }
                return receiverBoundMatches(
                    bound: upperBound,
                    receiverType: receiverType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem
                )
            }
            if !matchingBounds.isEmpty {
                return matchingBounds.flatMap { upperBound in
                    decomposeSubtypeConstraint(
                        subtype: upperBound,
                        supertype: receiverType,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: range
                    )
                }
            }
        }
        return decomposeSubtypeConstraint(
            subtype: implicitReceiverType,
            supertype: receiverType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: typeSystem,
            blameRange: range
        )
    }

    private func receiverBoundMatches(
        bound: TypeID,
        receiverType: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem
    ) -> Bool {
        let nonNullBound = typeSystem.makeNonNullable(bound)
        let nonNullReceiver = typeSystem.makeNonNullable(receiverType)
        if case let .classType(superClass) = typeSystem.kind(of: nonNullReceiver) {
            if case let .classType(subClass) = typeSystem.kind(of: nonNullBound) {
                return subClass.classSymbol == superClass.classSymbol
                    || typeSystem.isNominalSubtypeSymbol(subClass.classSymbol, of: superClass.classSymbol)
            }
            return false
        }
        if case let .functionType(superFunc) = typeSystem.kind(of: nonNullReceiver) {
            if case let .functionType(subFunc) = typeSystem.kind(of: nonNullBound) {
                return subFunc.params.count == superFunc.params.count
            }
            return false
        }
        if case let .typeParam(superParam) = typeSystem.kind(of: nonNullReceiver),
           typeVarBySymbol[superParam.symbol] != nil
        {
            return true
        }
        return typeSystem.isSubtype(nonNullBound, nonNullReceiver)
    }

    private func containsStarProjection(_ type: TypeID, typeSystem: TypeSystem) -> Bool {
        switch typeSystem.kind(of: type) {
        case let .classType(classType):
            typeSystem.allTypeArguments(for: classType).contains { argument in
                switch argument {
                case .star:
                    true
                case let .invariant(inner), let .out(inner), let .in(inner):
                    containsStarProjection(inner, typeSystem: typeSystem)
                }
            }
        case let .functionType(functionType):
            functionType.contextReceivers.contains { containsStarProjection($0, typeSystem: typeSystem) }
                || functionType.receiver.map { containsStarProjection($0, typeSystem: typeSystem) } == true
                || functionType.params.contains { containsStarProjection($0, typeSystem: typeSystem) }
                || containsStarProjection(functionType.returnType, typeSystem: typeSystem)
                || functionType.throws.contains { containsStarProjection($0, typeSystem: typeSystem) }
        case let .intersection(parts):
            parts.contains { containsStarProjection($0, typeSystem: typeSystem) }
        case let .kClassType(kClassType):
            containsStarProjection(kClassType.argument, typeSystem: typeSystem)
        default:
            false
        }
    }

    private func appendArgumentConstraints(
        to constraints: inout [VariableConstraint],
        call: CallExpr,
        parameterMapping: [Int: Int],
        signature: FunctionSignature,
        typeVarBySymbol: [SymbolID: TypeVarID],
        explicitTypeSubstitution: [TypeVarID: TypeID],
        ignoredLambdaReturnTypeArgumentIndices: Set<Int>,
        ignoredIntegerLiteralArgumentIndices: Set<Int> = [],
        sema: SemaModule
    ) -> Bool {
        let typeSystem = sema.types
        let isVararg = Self.normalizeFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count)
        var processedAll = true
        for argIndex in call.args.indices {
            if ignoredIntegerLiteralArgumentIndices.contains(argIndex) { continue }
            guard let paramIndex = parameterMapping[argIndex],
                  paramIndex >= 0,
                  paramIndex < signature.parameterTypes.count
            else {
                constraints.removeAll(keepingCapacity: false)
                processedAll = false
                break
            }
            let paramType = signature.parameterTypes[paramIndex]
            let arg = call.args[argIndex]
            // Explicit bindings and concrete non-literal inputs supply the
            // literal expectation; constraints still target the original T.
            let literalParameterType = typeSystem.substituteTypeParameters(
                in: paramType,
                substitution: explicitTypeSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            let inferredArgType = !arg.isSpread
                ? (integerLiteralType(arg, parameterType: literalParameterType, types: typeSystem) ?? arg.type)
                : arg.type
            let argType = !arg.isSpread
                ? (typeSystem.suspendConversionType(from: inferredArgType, to: paramType) ?? inferredArgType)
                : inferredArgType

            if arg.label != nil, isVararg[paramIndex] {
                // A named vararg argument supplies the whole array, even without `*`.
                guard let elementType = namedVarargArgumentElementType(
                    argType, parameterType: paramType, sema: sema
                ) else {
                    return false
                }
                constraints.append(contentsOf: decomposeSubtypeConstraint(
                    subtype: elementType,
                    supertype: paramType,
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: typeSystem,
                    blameRange: call.range
                ))
                continue
            }
            // Recover spread element types to distinguish array overloads.
            // Keep the historical unconstrained fallback for synthetic or
            // incomplete test types whose array shape cannot be recovered.
            if arg.isSpread, isVararg[paramIndex] {
                if let elementType = spreadArgumentElementType(argType, sema: sema) {
                    let decomposed = decomposeSubtypeConstraint(
                        subtype: elementType,
                        supertype: paramType,
                        typeVarBySymbol: typeVarBySymbol,
                        typeSystem: typeSystem,
                        blameRange: call.range
                    )
                    constraints.append(contentsOf: decomposed)
                }
                continue
            }

            if ignoredLambdaReturnTypeArgumentIndices.contains(argIndex),
               appendLambdaInputConstraintsIgnoringReturn(
                   to: &constraints,
                   argType: argType,
                   paramType: paramType,
                   typeVarBySymbol: typeVarBySymbol,
                   typeSystem: typeSystem,
                   blameRange: call.range
               )
            {
                continue
            }

            // SAM adaptation is a call-site conversion, not nominal subtyping.
            // Constrain the function value against the SAM method so generic
            // interface arguments participate in ordinary candidate inference.
            let constraintParameterType: TypeID
            let constraintArgumentType: TypeID
            if !arg.isSpread,
               case .functionType = typeSystem.kind(of: argType),
               let samFunction = TypeCheckHelpers().samFunctionType(for: paramType, sema: sema)
            {
                constraintParameterType = typeSystem.withNullability(
                    typeSystem.nullability(of: paramType),
                    for: typeSystem.make(.functionType(samFunction))
                )
                // Suspend conversion applies to function arguments even when
                // the target is represented by a SAM interface at this call site.
                constraintArgumentType = typeSystem.suspendConversionType(
                    from: argType,
                    to: constraintParameterType
                ) ?? argType
            } else {
                constraintParameterType = paramType
                constraintArgumentType = argType
            }
            let decomposed = decomposeSubtypeConstraint(
                subtype: constraintArgumentType,
                supertype: constraintParameterType,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: call.range
            )
            constraints.append(contentsOf: decomposed)
        }
        if !processedAll {
            return !(constraints.isEmpty && !call.args.isEmpty)
        }
        return true
    }

    /// Infer a literal against this candidate, rather than treating an
    /// unsuffixed literal's previously inferred Int as its only possible type.
    private func integerLiteralType(
        _ argument: CallArg,
        parameterType: TypeID,
        types: TypeSystem
    ) -> TypeID? {
        guard case let .primitive(primitive, _) = types.kind(of: types.makeNonNullable(parameterType)) else {
            return nil
        }
        if let value = argument.signedIntegerLiteral {
            switch primitive {
            case .byte where (-128...127).contains(value): return types.byteType
            case .short where (-32768...32767).contains(value): return types.shortType
            case .long: return types.longType
            default: return nil
            }
        }
        if let value = argument.unsignedIntegerLiteral {
            switch primitive {
            case .ubyte where value <= UInt64(UInt8.max): return types.ubyteType
            case .ushort where value <= UInt64(UInt16.max): return types.ushortType
            case .ulong: return types.ulongType
            default: return nil
            }
        }
        return nil
    }

    private func namedVarargArgumentElementType(
        _ type: TypeID,
        parameterType: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        guard sema.types.nullability(of: type) != .nullable,
              let (_, symbol) = resolveClassTypeSymbol(type, sema: sema),
              let interner = sema.interner
        else {
            return nil
        }
        // Primitive varargs require their primitive array; reference, nullable
        // primitive, and generic varargs require Array<out T>.
        let arrayName: String
        if case let .primitive(primitive, .nonNull) = sema.types.kind(of: parameterType) {
            arrayName = primitive.kotlinName + "Array"
        } else {
            arrayName = "Array"
        }
        guard symbol.fqName == [interner.intern("kotlin"), interner.intern(arrayName)] else {
            return nil
        }
        return spreadArgumentElementType(type, sema: sema)
    }

    /// Generic `Array<T>`/collection types carry the element in their first type
    /// argument; primitive arrays require the interner to identify the class.
    private func spreadArgumentElementType(_ type: TypeID, sema: SemaModule) -> TypeID? {
        guard let (classType, symbol) = resolveClassTypeSymbol(type, sema: sema) else {
            return nil
        }
        if let firstArgument = classType.args.first {
            switch firstArgument {
            case let .invariant(element), let .out(element), let .in(element):
                return element
            case .star:
                return sema.types.nullableAnyType
            }
        }
        guard let interner = sema.interner else {
            return nil
        }
        let knownNames = KnownCompilerNames(interner: interner)
        switch symbol.name {
        case knownNames.intArray:
            return sema.types.intType
        case knownNames.shortArray:
            return sema.types.shortType
        case knownNames.byteArray:
            return sema.types.byteType
        case knownNames.longArray:
            return sema.types.longType
        case knownNames.ubyteArray:
            return sema.types.ubyteType
        case knownNames.ushortArray:
            return sema.types.ushortType
        case knownNames.uintArray:
            return sema.types.uintType
        case knownNames.ulongArray:
            return sema.types.ulongType
        case knownNames.doubleArray:
            return sema.types.doubleType
        case knownNames.floatArray:
            return sema.types.floatType
        case knownNames.booleanArray:
            return sema.types.booleanType
        case knownNames.charArray:
            return sema.types.charType
        default:
            return nil
        }
    }

    private func appendLambdaInputConstraintsIgnoringReturn(
        to constraints: inout [VariableConstraint],
        argType: TypeID,
        paramType: TypeID,
        typeVarBySymbol: [SymbolID: TypeVarID],
        typeSystem: TypeSystem,
        blameRange: SourceRange
    ) -> Bool {
        guard case let .functionType(argFunction) = typeSystem.kind(of: argType),
              case let .functionType(paramFunction) = typeSystem.kind(of: paramType),
              // Non-suspend arguments satisfy suspend parameters
              // (`() -> T <: suspend () -> T`), not the reverse.
              paramFunction.isSuspend || !argFunction.isSuspend,
              argFunction.params.count == paramFunction.params.count
        else {
            return false
        }

        if let argReceiver = argFunction.receiver,
           let paramReceiver = paramFunction.receiver
        {
            // Function receivers are contravariant — flip direction.
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: paramReceiver,
                supertype: argReceiver,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange
            ))
        } else if argFunction.receiver != nil || paramFunction.receiver != nil {
            return false
        }

        // Function type parameters are contravariant — flip direction
        // (matching decomposeSubtypeConstraintImpl in Resolution+TypeConstraints.swift).
        for (argParameter, paramParameter) in zip(argFunction.params, paramFunction.params) {
            constraints.append(contentsOf: decomposeSubtypeConstraint(
                subtype: paramParameter,
                supertype: argParameter,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: typeSystem,
                blameRange: blameRange
            ))
        }
        return true
    }

    private func solveConstraints(
        _ constraints: [VariableConstraint],
        solver: ConstraintSolver,
        typeSystem: TypeSystem
    ) -> ConstraintSolveResult {
        let varsToSolve = usedTypeVariables(from: constraints)
        if varsToSolve.isEmpty {
            let allSatisfied = constraints.allSatisfy {
                isConstraintSatisfiedWithoutVariables($0, typeSystem: typeSystem)
            }
            return allSatisfied ? .success([:]) : .rejected
        }
        let solution = solver.solve(
            vars: varsToSolve,
            constraints: constraints,
            typeSystem: typeSystem
        )
        if solution.isSuccess {
            return .success(solution.substitution)
        }
        if let failure = solution.failure {
            return .constraintFailure(failure)
        }
        return .rejected
    }

    private func inputConstrainedTypeVariables(in constraints: [VariableConstraint]) -> Set<TypeVarID> {
        var variables: Set<TypeVarID> = []
        for constraint in constraints {
            if case let .variable(variable) = constraint.left {
                variables.insert(variable)
            }
            if case let .variable(variable) = constraint.right {
                variables.insert(variable)
            }
        }
        return variables
    }

    private func replacingInputVariables(
        in operand: ConstraintOperand,
        constrainedVariables: Set<TypeVarID>,
        substitution: [TypeVarID: TypeID]
    ) -> ConstraintOperand? {
        guard case let .variable(variable) = operand,
              constrainedVariables.contains(variable)
        else {
            return operand
        }
        guard let type = substitution[variable], type != .invalid else {
            return nil
        }
        return .type(type)
    }

    private func isVariable(_ operand: ConstraintOperand) -> Bool {
        if case .variable = operand { return true }
        return false
    }

    private func selectResult(
        from viable: [ViableCandidate],
        call: CallExpr,
        typeSystem: TypeSystem,
        candidateFailures: [Diagnostic],
        preserveMemberExtensionAmbiguity: Bool
    ) -> ResolvedCall {
        if viable.isEmpty {
            if let diagnostic = candidateFailures.first {
                return ResolvedCall(
                    chosenCallee: nil,
                    substitutedTypeArguments: [:],
                    parameterMapping: [:],
                    diagnostic: diagnostic
                )
            }
            return errorResult(
                code: "KSWIFTK-SEMA-0002",
                message: "No viable overload found for call.",
                range: call.range
            )
        }
        // Low-priority overloads participate only when no applicable
        // regular-priority candidate exists. Apply this after viability so an
        // inapplicable regular overload cannot suppress the low-priority set.
        let regularPriorityCandidates = viable.filter { candidate in
            !candidate.isLowPriorityInOverloadResolution
        }
        let priorityFiltered = regularPriorityCandidates.isEmpty ? viable : regularPriorityCandidates
        if priorityFiltered.count == 1 {
            return priorityFiltered[0].toResolvedCall()
        }
        if let chosen = pickMostSpecific(
            priorityFiltered,
            call: call,
            typeSystem: typeSystem,
            preserveMemberExtensionAmbiguity: preserveMemberExtensionAmbiguity
        ) {
            return chosen.toResolvedCall()
        }
        return errorResult(
            code: "KSWIFTK-SEMA-0003",
            message: "Ambiguous overload resolution.",
            range: call.range,
            secondaryRanges: candidateDeclSites(viable, typeSystem: typeSystem)
        )
    }

    /// ARCH-031: declaration sites of the ambiguous overload candidates,
    /// deduplicated and sorted by source position so diagnostics stay
    /// deterministic.
    private func candidateDeclSites(
        _ candidates: [ViableCandidate],
        typeSystem: TypeSystem
    ) -> [SourceRange] {
        typeSystem.symbolTable?.sortedDeclSites(of: candidates.map(\.symbol)) ?? []
    }

    private func errorResult(
        code: String,
        message: String,
        range: SourceRange,
        secondaryRanges: [SourceRange] = []
    ) -> ResolvedCall {
        ResolvedCall(
            chosenCallee: nil,
            substitutedTypeArguments: [:],
            parameterMapping: [:],
            diagnostic: Diagnostic(
                severity: .error,
                code: code,
                message: message,
                primaryRange: range,
                secondaryRanges: secondaryRanges
            )
        )
    }

    private struct ViableCandidate {
        let symbol: SymbolID
        let signature: FunctionSignature
        let instantiatedReceiverType: TypeID?
        let instantiatedParameterTypes: [TypeID]
        let substitutedTypeArguments: [TypeVarID: TypeID]
        let parameterMapping: [Int: Int]
        let defaultArgumentOwner: SymbolID?
        let effectiveDefaultValues: [Bool]
        let usesVararg: Bool
        let isLowPriorityInOverloadResolution: Bool

        func toResolvedCall() -> ResolvedCall {
            ResolvedCall(
                chosenCallee: symbol,
                substitutedTypeArguments: substitutedTypeArguments,
                parameterMapping: parameterMapping,
                diagnostic: nil,
                defaultArgumentOwner: defaultArgumentOwner
            )
        }

        func toProbedCallCandidate() -> ProbedCallCandidate {
            ProbedCallCandidate(symbol: symbol)
        }
    }

    private enum CandidateEvaluation {
        case viable(ViableCandidate)
        case constraintFailure(Diagnostic)
        case rejected
    }

    private enum ConstraintSolveResult {
        case success([TypeVarID: TypeID])
        case constraintFailure(Diagnostic)
        case rejected
    }

    private func pickMostSpecific(
        _ candidates: [ViableCandidate],
        call: CallExpr,
        typeSystem: TypeSystem,
        preserveMemberExtensionAmbiguity: Bool
    ) -> ViableCandidate? {
        let winners = candidates.filter { candidate in
            for other in candidates where other.symbol != candidate.symbol {
                if !isMoreSpecificCandidate(candidate, than: other, call: call, typeSystem: typeSystem) {
                    return false
                }
            }
            return true
        }
        if winners.count == 1 {
            return winners[0]
        }
        // Candidates that tied on every specificity criterion (empty `winners`
        // means no candidate was more specific than all the others). When they
        // are all member functions with pairwise-equivalent instantiated
        // signatures, the same Kotlin member was reached through multiple
        // supertype paths — e.g. `IntRange` inherits `ClosedRange.contains` and
        // `OpenEndRange.contains` — so collapse them to one deterministic
        // winner instead of reporting the call as ambiguous. Scope extensions
        // and mismatched-signature members stay genuinely ambiguous. Imported
        // singleton members are independently bound callables, not duplicate
        // supertype paths, even when their value parameter types are equal.
        let tied = winners.isEmpty ? candidates : winners
        if tied.count > 1,
           tied.allSatisfy({ !call.boundObjectDispatchReceiverCandidates.contains($0.symbol) }),
           (!preserveMemberExtensionAmbiguity || tied.allSatisfy({
               typeSystem.symbolTable?.memberExtensionOwnerSymbol(for: $0.symbol) == nil
           })),
           tied.allSatisfy({ isNominalMemberFunction($0.symbol, typeSystem: typeSystem) }),
           tied.allSatisfy({ lhs in
               tied.allSatisfy { rhs in
                   lhs.symbol == rhs.symbol
                       || (lhs.instantiatedParameterTypes.count == rhs.instantiatedParameterTypes.count
                           && zip(lhs.instantiatedParameterTypes, rhs.instantiatedParameterTypes).allSatisfy {
                               typeSystem.isSubtype($0, $1) && typeSystem.isSubtype($1, $0)
                           })
               }
           })
        {
            return tied.min { lhs, rhs in
                let lhsSynthetic = typeSystem.symbolTable?.symbol(lhs.symbol)?.flags.contains(.synthetic) ?? false
                let rhsSynthetic = typeSystem.symbolTable?.symbol(rhs.symbol)?.flags.contains(.synthetic) ?? false
                if lhsSynthetic != rhsSynthetic {
                    return !lhsSynthetic
                }
                return lhs.symbol.rawValue < rhs.symbol.rawValue
            }
        }
        return nil
    }

    /// True when `symbol` is a function declared directly inside a nominal
    /// (class/interface/object) — as opposed to a package-scope extension or a
    /// local function — so multiple copies reached via supertypes denote the
    /// same unified Kotlin member.
    private func isNominalMemberFunction(
        _ symbol: SymbolID,
        typeSystem: TypeSystem
    ) -> Bool {
        guard let symbols = typeSystem.symbolTable,
              let declaration = symbols.symbol(symbol),
              let parentID = symbols.parentSymbol(for: symbol),
              let parent = symbols.symbol(parentID),
              declaration.fqName == parent.fqName + [declaration.name]
        else {
            return false
        }
        return parent.kind == .class
            || parent.kind == .interface
            || parent.kind == .object
            || parent.kind == .enumClass
            || parent.kind == .annotationClass
    }

    /// Returns true if `lhs` is at least as specific as `rhs`.
    /// First compares parameter types; if they are equivalent, falls back to
    /// receiver type: the more-derived receiver (override) wins over the base.
    /// When counts differ because one candidate has additional unbound default
    /// parameters, the candidate binding the same arguments to fewer parameters
    /// is preferred (e.g. trailing-lambda overloads without optional prefix args).
    private func isMoreSpecificCandidate(
        _ lhs: ViableCandidate,
        than rhs: ViableCandidate,
        call: CallExpr,
        typeSystem: TypeSystem
    ) -> Bool {
        // Between function and SAM parameters, Kotlin prefers the callable
        // overload that accepts the function value without adaptation. Keep
        // nominal overloads (for example SAM versus Any) on the usual rules.
        var prefersFunctionParameter = false
        for (index, pair) in zip(lhs.instantiatedParameterTypes, rhs.instantiatedParameterTypes).enumerated() {
            guard case .functionType = typeSystem.kind(of: call.args[index].type) else { continue }
            let lhsIsFunction: Bool = if case .functionType = typeSystem.kind(of: pair.0) { true } else { false }
            let rhsIsFunction: Bool = if case .functionType = typeSystem.kind(of: pair.1) { true } else { false }
            func isSam(_ type: TypeID) -> Bool {
                guard case let .classType(nominal) = typeSystem.kind(of: type) else { return false }
                return typeSystem.symbolTable?.symbol(nominal.classSymbol)?.flags.contains(.funInterface) == true
            }
            if lhsIsFunction, isSam(pair.1) { prefersFunctionParameter = true }
            if rhsIsFunction, isSam(pair.0) { return false }
        }
        if prefersFunctionParameter { return true }
        if isMoreSpecific(lhs.instantiatedParameterTypes, than: rhs.instantiatedParameterTypes, call: call, typeSystem: typeSystem) {
            return true
        }

        // If parameter counts differ because one candidate supplied additional
        // default arguments, the candidate with fewer parameters is more specific
        // when every bound argument type is at least as specific.
        let rhsBound = Set(rhs.parameterMapping.values)
        var lhsBoundIsNoLessSpecific = true
        for argIndex in lhs.instantiatedParameterTypes.indices {
            guard argIndex < rhs.instantiatedParameterTypes.count else {
                lhsBoundIsNoLessSpecific = false
                break
            }
            if !typeSystem.isSubtype(lhs.instantiatedParameterTypes[argIndex], rhs.instantiatedParameterTypes[argIndex]) {
                lhsBoundIsNoLessSpecific = false
                break
            }
        }
        if lhsBoundIsNoLessSpecific {
            let lhsCount = lhs.signature.parameterTypes.count
            let rhsCount = rhs.signature.parameterTypes.count
            if lhsCount < rhsCount {
                // The larger candidate is more specific only if its extra formal
                // parameters are not supplied by the call and are optional (default
                // or vararg). If every extra parameter is bound, the smaller
                // candidate (e.g. a vararg overload) is not preferred.
                let rhsDefaults = Self.normalizeFlags(rhs.effectiveDefaultValues, count: rhsCount)
                let rhsVarargs = Self.normalizeFlags(rhs.signature.valueParameterIsVararg, count: rhsCount)
                var unboundFound = false
                var extraAreOptional = true
                for p in 0..<rhsCount {
                    if rhsBound.contains(p) { continue }
                    unboundFound = true
                    if rhsVarargs[p] { continue }
                    if rhsDefaults[p] { continue }
                    extraAreOptional = false
                    break
                }
                if unboundFound && extraAreOptional {
                    return true
                }
            }
        }

        if prefersExplicitFunctionTypeParameter(lhs, than: rhs, call: call, typeSystem: typeSystem) {
            return true
        }
        if prefersDeclaredShapeOverBareTypeParameter(lhs, than: rhs, typeSystem: typeSystem) {
            return true
        }

        // If parameter types are not strictly more specific, check whether they
        // are pairwise equivalent and the receiver type is a subtype (override
        // wins over the base class/interface default method).
        guard lhs.instantiatedParameterTypes.count == rhs.instantiatedParameterTypes.count else {
            return false
        }
        let paramsEqual = zip(lhs.instantiatedParameterTypes, rhs.instantiatedParameterTypes).allSatisfy {
            typeSystem.isSubtype($0, $1) && typeSystem.isSubtype($1, $0)
        }
        guard paramsEqual else {
            return false
        }
        if lhs.instantiatedParameterTypes == rhs.instantiatedParameterTypes,
           let lhsReceiver = lhs.instantiatedReceiverType,
           let rhsReceiver = rhs.instantiatedReceiverType
        {
            let lhsReceiverSubRhs = typeSystem.isSubtype(lhsReceiver, rhsReceiver)
            let rhsReceiverSubLhs = typeSystem.isSubtype(rhsReceiver, lhsReceiver)
            if lhsReceiverSubRhs && !rhsReceiverSubLhs {
                return true
            }
            if rhsReceiverSubLhs && !lhsReceiverSubRhs {
                return false
            }
        }
        let lhsHasTypeParameter = signatureContainsTypeParameter(lhs.signature, typeSystem: typeSystem)
        let rhsHasTypeParameter = signatureContainsTypeParameter(rhs.signature, typeSystem: typeSystem)
        if lhsHasTypeParameter != rhsHasTypeParameter {
            return !lhsHasTypeParameter
        }
        let lhsOwnTypeParamCount = lhs.signature.typeParameterSymbols.count - lhs.signature.classTypeParameterCount
        let rhsOwnTypeParamCount = rhs.signature.typeParameterSymbols.count - rhs.signature.classTypeParameterCount
        if lhsOwnTypeParamCount != rhsOwnTypeParamCount {
            return lhsOwnTypeParamCount < rhsOwnTypeParamCount
        }
        if hasMoreSpecificTypeParameterBounds(lhs.signature, than: rhs.signature, typeSystem: typeSystem) {
            return true
        }
        if lhs.usesVararg != rhs.usesVararg {
            return !lhs.usesVararg && rhs.usesVararg
        }
        return false
    }

    /// Kotlin compares overloads by their declared (uninstantiated) signatures:
    /// `minus(elements: Iterable<T>)` beats `minus(element: T)` because
    /// `Iterable<T>` can be passed to a bare `T` but not vice versa. Instantiated
    /// parameter types can be incomparable (e.g. `T` inferred as `List<*>` for
    /// nested lists), so fall back to the declared shapes: every parameter is
    /// identical or the other side is a bare type parameter, with at least one
    /// strict case.
    private func prefersDeclaredShapeOverBareTypeParameter(
        _ lhs: ViableCandidate,
        than rhs: ViableCandidate,
        typeSystem: TypeSystem
    ) -> Bool {
        let lhsDeclared = lhs.signature.parameterTypes
        let rhsDeclared = rhs.signature.parameterTypes
        guard lhsDeclared.count == rhsDeclared.count, !lhsDeclared.isEmpty else { return false }
        func isBareTypeParameter(_ type: TypeID) -> Bool {
            if case .typeParam = typeSystem.kind(of: typeSystem.makeNonNullable(type)) { return true }
            return false
        }
        var sawStrict = false
        for (l, r) in zip(lhsDeclared, rhsDeclared) {
            if isBareTypeParameter(r), !isBareTypeParameter(l) {
                sawStrict = true
            } else if isBareTypeParameter(l) != isBareTypeParameter(r) {
                return false
            } else if !isBareTypeParameter(l), l != r {
                return false
            }
        }
        return sawStrict
    }

    /// Prefer a declared function-type parameter over a direct type parameter
    /// when both candidates infer the same function type for a lambda argument.
    /// Otherwise a generic value overload such as `fun <T> f(value: T)` ties
    /// with `fun <T> f(block: () -> T)` after both have been instantiated.
    private func prefersExplicitFunctionTypeParameter(
        _ lhs: ViableCandidate,
        than rhs: ViableCandidate,
        call: CallExpr,
        typeSystem: TypeSystem
    ) -> Bool {
        guard lhs.instantiatedParameterTypes.count == call.args.count,
              rhs.instantiatedParameterTypes.count == call.args.count,
              zip(lhs.instantiatedParameterTypes, rhs.instantiatedParameterTypes).allSatisfy({
                  typeSystem.isSubtype($0, $1) && typeSystem.isSubtype($1, $0)
              })
        else {
            return false
        }

        func isFunctionType(_ type: TypeID) -> Bool {
            if case .functionType = typeSystem.kind(of: typeSystem.makeNonNullable(type)) {
                return true
            }
            return false
        }
        func isDirectTypeParameter(_ type: TypeID) -> Bool {
            if case .typeParam = typeSystem.kind(of: typeSystem.makeNonNullable(type)) {
                return true
            }
            return false
        }

        var prefersFunctionType = false
        for argumentIndex in call.args.indices {
            guard case .functionType = typeSystem.kind(of: call.args[argumentIndex].type),
                  let lhsParameterIndex = lhs.parameterMapping[argumentIndex],
                  let rhsParameterIndex = rhs.parameterMapping[argumentIndex],
                  lhs.signature.parameterTypes.indices.contains(lhsParameterIndex),
                  rhs.signature.parameterTypes.indices.contains(rhsParameterIndex)
            else {
                continue
            }
            let lhsDeclaredType = lhs.signature.parameterTypes[lhsParameterIndex]
            let rhsDeclaredType = rhs.signature.parameterTypes[rhsParameterIndex]
            if isDirectTypeParameter(lhsDeclaredType), isFunctionType(rhsDeclaredType) {
                return false
            }
            if isFunctionType(lhsDeclaredType), isDirectTypeParameter(rhsDeclaredType) {
                prefersFunctionType = true
            }
        }
        return prefersFunctionType
    }

    private func hasMoreSpecificTypeParameterBounds(
        _ lhs: FunctionSignature,
        than rhs: FunctionSignature,
        typeSystem: TypeSystem
    ) -> Bool {
        guard !lhs.typeParameterSymbols.isEmpty,
              lhs.typeParameterSymbols.count == rhs.typeParameterSymbols.count,
              let symbols = typeSystem.symbolTable
        else { return false }
        let rhsVariables = typeSystem.makeTypeVarBySymbol(rhs.typeParameterSymbols)
        var renaming: [TypeVarID: TypeID] = [:]
        for (left, right) in zip(lhs.typeParameterSymbols, rhs.typeParameterSymbols) {
            guard let variable = rhsVariables[right] else { return false }
            renaming[variable] = typeSystem.make(.typeParam(TypeParamType(symbol: left, nullability: .nonNull)))
        }
        func renamed(_ type: TypeID) -> TypeID {
            typeSystem.substituteTypeParameters(in: type, substitution: renaming, typeVarBySymbol: rhsVariables)
        }
        // Compare bounds only for alpha-equivalent declaration shapes; concrete
        // instantiations alone lose the distinction between T : Any and Comparable<T>.
        guard lhs.parameterTypes == rhs.parameterTypes.map(renamed),
              lhs.receiverType == rhs.receiverType.map(renamed)
        else { return false }
        func bounds(_ signature: FunctionSignature, _ index: Int) -> [TypeID] {
            let declared = index < signature.typeParameterUpperBoundsList.count
                ? signature.typeParameterUpperBoundsList[index] : []
            let stored = symbols.typeParameterUpperBounds(for: signature.typeParameterSymbols[index])
            let result = declared + stored.filter { !declared.contains($0) }
            return result.isEmpty ? [typeSystem.nullableAnyType] : result
        }
        var strictlyMoreSpecific = false
        for index in lhs.typeParameterSymbols.indices {
            let left = typeSystem.glb(bounds(lhs, index))
            let right = typeSystem.glb(bounds(rhs, index).map(renamed))
            guard typeSystem.isSubtype(left, right) else { return false }
            if !typeSystem.isSubtype(right, left) { strictlyMoreSpecific = true }
        }
        return strictlyMoreSpecific
    }

    private func signatureContainsTypeParameter(
        _ signature: FunctionSignature,
        typeSystem: TypeSystem
    ) -> Bool {
        var typesToCheck: [TypeID] = signature.parameterTypes
        if let receiver = signature.receiverType {
            typesToCheck.append(receiver)
        }
        return typesToCheck.contains { typeContainsTypeParameter($0, typeSystem: typeSystem) }
    }

    private func typeContainsTypeParameter(
        _ type: TypeID,
        typeSystem: TypeSystem
    ) -> Bool {
        switch typeSystem.kind(of: type) {
        case .typeParam:
            return true
        case let .classType(classType):
            for arg in typeSystem.allTypeArguments(for: classType) {
                let argType: TypeID? = switch arg {
                case let .invariant(t), let .out(t), let .in(t): t
                case .star: nil
                }
                if let argType, typeContainsTypeParameter(argType, typeSystem: typeSystem) {
                    return true
                }
            }
            return false
        case let .functionType(functionType):
            let allTypes = functionType.contextReceivers
                + (functionType.receiver.map { [$0] } ?? [])
                + functionType.params
                + [functionType.returnType]
            return allTypes.contains { typeContainsTypeParameter($0, typeSystem: typeSystem) }
        case let .kClassType(kClassType):
            return typeContainsTypeParameter(kClassType.argument, typeSystem: typeSystem)
        case let .intersection(parts):
            return parts.contains { typeContainsTypeParameter($0, typeSystem: typeSystem) }
        default:
            return false
        }
    }

    private func isMoreSpecific(
        _ lhs: [TypeID],
        than rhs: [TypeID],
        call: CallExpr,
        typeSystem: TypeSystem
    ) -> Bool {
        if lhs.count != rhs.count {
            return false
        }
        var sawStrict = false
        for (index, pair) in zip(lhs, rhs).enumerated() {
            let (lhsParam, rhsParam) = pair
            let lhsSubRhs = typeSystem.isSubtype(lhsParam, rhsParam)
            if !lhsSubRhs {
                // Kotlin's literal-specific widening order is not subtyping:
                // Int is preferred to Byte/Short/Long, and Short to Byte.
                // Unsigned literals follow the same shape: UInt beats
                // UByte/UShort/ULong, and UShort beats UByte.
                guard !call.args[index].isSpread,
                      case let .primitive(lhsPrimitive, _) = typeSystem.kind(of: typeSystem.makeNonNullable(lhsParam)),
                      case let .primitive(rhsPrimitive, _) = typeSystem.kind(of: typeSystem.makeNonNullable(rhsParam)),
                      (call.args[index].signedIntegerLiteral != nil
                          && ((lhsPrimitive == .int && [.byte, .short, .long].contains(rhsPrimitive))
                              || (lhsPrimitive == .short && rhsPrimitive == .byte)))
                          || (call.args[index].unsignedIntegerLiteral != nil
                              && ((lhsPrimitive == .uint && [.ubyte, .ushort, .ulong].contains(rhsPrimitive))
                                  || (lhsPrimitive == .ushort && rhsPrimitive == .ubyte)))
                else { return false }
                sawStrict = true
                continue
            }
            let rhsSubLhs = typeSystem.isSubtype(rhsParam, lhsParam)
            if lhsSubRhs, !rhsSubLhs {
                sawStrict = true
            }
        }
        return sawStrict
    }
}
