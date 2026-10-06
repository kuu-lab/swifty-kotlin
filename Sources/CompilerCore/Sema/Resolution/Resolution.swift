extension OverloadResolver {
    public func probeCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID? = nil,
        ignoringLambdaReturnTypeArgumentIndices: Set<Int> = [],
        ctx: SemaModule
    ) -> ProbedCallResult {
        let solver = ConstraintSolver()
        var viable: [ViableCandidate] = []
        for candidate in candidates {
            let evaluation = evaluateCandidate(
                candidate,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                ignoredLambdaReturnTypeArgumentIndices: ignoringLambdaReturnTypeArgumentIndices,
                solver: solver,
                ctx: ctx
            )
            switch evaluation {
            case let .viable(value):
                viable.append(value)
            case .constraintFailure, .rejected:
                continue
            }
        }
        return ProbedCallResult(
            viableCandidates: viable.map { $0.toProbedCallCandidate() }
        )
    }

    /// Derives a partial type-variable substitution for `signature`'s type
    /// parameters using only the argument positions present in
    /// `knownArgumentTypes`. Used to seed a lambda argument's expected type with
    /// type-parameter bindings already inferred from the call's other
    /// (non-lambda) arguments, before the lambda literal itself is type-checked
    /// (see `lambdaLiteralExpectedType` in `CallTypeChecker+LambdaReturnTypeOverload.swift`).
    /// A missing key in the result means that type parameter could not be
    /// constrained from the known arguments — callers must treat it as
    /// "unconstrained", not as an error.
    func probeArgumentTypeSubstitution(
        signature: FunctionSignature,
        typeVarBySymbol: [SymbolID: TypeVarID],
        knownArgumentTypes: [Int: TypeID],
        typeSystem: TypeSystem,
        blameRange: SourceRange? = nil,
        implicitReceiverType: TypeID? = nil
    ) -> [TypeVarID: TypeID] {
        guard !typeVarBySymbol.isEmpty else {
            return [:]
        }
        var constraints: [VariableConstraint] = []
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

        // An upper bound alone is not a usable lambda context. For example,
        // Comparator<Any> passed to Comparator<in R> only establishes R <: Any;
        // the trailing selector still has to infer R from its return type. If
        // this helper substituted Any eagerly, the selector would be checked as
        // (T) -> Any and its concrete return type would be lost before the main
        // call solver ran. Keep substitutions that have a concrete lower bound,
        // while leaving upper-only variables unresolved for the lambda pass.
        let lowerBoundedVariables: Set<TypeVarID> = Set(constraints.compactMap { constraint in
            guard case .type = constraint.left,
                  case let .variable(variable) = constraint.right
            else {
                return nil
            }
            return variable
        })
        return solution.substitution.filter { lowerBoundedVariables.contains($0.key) }
    }

    public func resolveCall(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID? = nil,
        ctx: SemaModule
    ) -> ResolvedCall {
        // --- cache lookup ---
        if let cache = cacheContext {
            let key = SemaCacheContext.makeCallResolutionKey(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                symbols: ctx.symbols
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
                ctx: ctx
            )
            cache.cacheCallResolution(result, for: key)
            return result
        }
        return resolveCallUncached(
            candidates: candidates,
            call: call,
            expectedType: expectedType,
            implicitReceiverType: implicitReceiverType,
            ctx: ctx
        )
    }

    private func resolveCallUncached(
        candidates: [SymbolID],
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        ctx: SemaModule
    ) -> ResolvedCall {
        let solver = ConstraintSolver()
        var viable: [ViableCandidate] = []
        var candidateFailures: [Diagnostic] = []
        for candidate in candidates {
            let evaluation = evaluateCandidate(
                candidate,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: implicitReceiverType,
                ignoredLambdaReturnTypeArgumentIndices: [],
                solver: solver,
                ctx: ctx
            )
            switch evaluation {
            case let .viable(value):
                viable.append(value)
            case let .constraintFailure(diagnostic):
                candidateFailures.append(diagnostic)
            case .rejected:
                continue
            }
        }
        return selectResult(
            from: viable,
            call: call,
            typeSystem: ctx.types,
            candidateFailures: candidateFailures
        )
    }

    private func evaluateCandidate(
        _ candidate: SymbolID,
        call: CallExpr,
        expectedType: TypeID?,
        implicitReceiverType: TypeID?,
        ignoredLambdaReturnTypeArgumentIndices: Set<Int>,
        solver: ConstraintSolver,
        ctx: SemaModule
    ) -> CandidateEvaluation {
        guard let symbol = ctx.symbols.symbol(candidate),
              symbol.kind == .function || symbol.kind == .constructor,
              let signature = ctx.symbols.functionSignature(for: candidate)
        else {
            return .rejected
        }

        let typeVarBySymbol = ctx.types.makeTypeVarBySymbol(signature.typeParameterSymbols)

        // Apply explicit type argument constraints if provided.
        // For constructors, explicit type args map to the class type params
        // (e.g. ArrayDeque<Int>() — <Int> binds the class's E parameter).
        // For regular functions, only compare against the function's own type
        // params (skip leading class type params inferred from the receiver).
        let funcOwnTypeParamCount = signature.typeParameterSymbols.count - signature.classTypeParameterCount
        let isConstructor = symbol.kind == .constructor
        if !call.explicitTypeArgs.isEmpty {
            let expectedTypeArgCount = isConstructor
                ? signature.classTypeParameterCount
                : funcOwnTypeParamCount
            guard call.explicitTypeArgs.count == expectedTypeArgCount else {
                return .rejected
            }
        }

        // Constructors synthesize their own receiver at the call site, so skip
        // the receiver constraint check that would reject them when there is no
        // implicit receiver in scope (e.g. `Dog()` called from a free function).
        var constraints: [VariableConstraint]
        if isConstructor {
            constraints = []
        } else {
            guard let receiverConstraints = buildReceiverConstraints(
                signature: signature,
                implicitReceiverType: implicitReceiverType,
                typeVarBySymbol: typeVarBySymbol,
                range: call.range,
                typeSystem: ctx.types
            ) else {
                return .rejected
            }
            constraints = receiverConstraints
        }

        // Member extensions infer class parameters from their dispatch receiver;
        // the extension receiver still constrains the declared receiver type.
        let memberExtensionOwner = ctx.symbols.memberExtensionOwnerSymbol(for: candidate)
        let classReceiverType: TypeID? = if let owner = memberExtensionOwner {
            call.dispatchReceiverTypes.first { receiver in
                guard case let .classType(receiverClass) = ctx.types.kind(
                    of: ctx.types.makeNonNullable(receiver)
                ) else { return false }
                return ctx.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
            }
        } else {
            implicitReceiverType
        }

        var starProjectedReceiverParameters: Set<SymbolID> = []
        // A nominal member's leading type parameters belong to the declaring
        // class/interface. Constrain them from the dispatch receiver, not an
        // unrelated extension receiver. Otherwise an inherited
        // member such as OpenEndRange<T>.contains(T) can incorrectly infer T
        // from a Byte/Long argument instead of Int from IntRange, making an
        // inapplicable member steal the call from an exact user extension.
        if !isConstructor,
           signature.classTypeParameterCount > 0,
           let classReceiverType,
           isNominalMemberFunction(candidate, typeSystem: ctx.types),
           let owner = ctx.symbols.parentSymbol(for: candidate),
           memberExtensionOwner != nil || signature.receiverType == nil || {
               guard case let .classType(receiverClass) = ctx.types.kind(
                   of: ctx.types.makeNonNullable(classReceiverType)
               ) else {
                   return false
               }
               return ctx.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
           }()
        {
            let ownerArguments: [TypeArg] = signature.typeParameterSymbols
                .prefix(signature.classTypeParameterCount)
                .map { typeParameter in
                    .invariant(ctx.types.make(.typeParam(TypeParamType(
                        symbol: typeParameter,
                        nullability: .nonNull
                    ))))
                }
            let ownerType = ctx.types.make(.classType(ClassType(
                classSymbol: owner,
                args: ownerArguments,
                nullability: .nonNull
            )))
            let receiverOwnerType: TypeID = {
                let nonNullReceiverType = ctx.types.makeNonNullable(classReceiverType)
                guard case let .classType(receiverClassType) = ctx.types.kind(of: nonNullReceiverType),
                      let liftedArguments = ctx.types.liftedNominalSupertypeArgs(
                          from: receiverClassType.classSymbol,
                          childArgs: receiverClassType.args,
                          to: owner
                      )
                else {
                    return classReceiverType
                }
                return ctx.types.make(.classType(ClassType(
                    classSymbol: owner,
                    args: liftedArguments,
                    nullability: .nonNull
                )))
            }()
            if case let .classType(receiverOwner) = ctx.types.kind(of: receiverOwnerType) {
                let methodBounds = Array(signature.typeParameterUpperBoundsList
                    .dropFirst(signature.classTypeParameterCount).joined())
                    + signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount).flatMap {
                        ctx.symbols.typeParameterUpperBounds(for: $0)
                    }
                for (parameter, argument) in zip(
                    signature.typeParameterSymbols.prefix(signature.classTypeParameterCount), receiverOwner.args
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
                for (parameter, argument) in zip(
                    signature.typeParameterSymbols.prefix(signature.classTypeParameterCount),
                    receiverOwner.args
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

        guard let parameterMapping = buildParameterMapping(
            signature: signature,
            callArgs: call.args,
            symbols: ctx.symbols,
            typeSystem: ctx.types
        ) else {
            return .rejected
        }

        // Add equality constraints for explicit type arguments.
        // For constructors, explicit type args bind class type params (offset 0).
        // For regular functions, map to function-own type params (after class type params).
        let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
        var explicitTypeSubstitution: [TypeVarID: TypeID] = [:]
        for (index, explicitArg) in call.explicitTypeArgs.enumerated() {
            let typeParamSymbol = signature.typeParameterSymbols[typeArgOffset + index]
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
        guard appendArgumentConstraints(
            to: &constraints,
            call: call,
            parameterMapping: parameterMapping,
            signature: signature,
            typeVarBySymbol: typeVarBySymbol,
            explicitTypeSubstitution: explicitTypeSubstitution,
            ignoredLambdaReturnTypeArgumentIndices: ignoredLambdaReturnTypeArgumentIndices,
            sema: ctx
        ) else {
            return .rejected
        }
        var inputConstraints = constraints

        // Upper bounds can relate two function type parameters (for example
        // `where C : Collection<*>, C : R`). Add those relationships to the
        // inference graph before solving so a receiver lower bound can widen
        // the result type as required by Kotlin's self-type extensions.
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
                constraints.append(VariableConstraint(
                    kind: .subtype,
                    left: .variable(typeParamVariable),
                    right: .variable(boundTypeParamVariable),
                    blameRange: call.range
                ))
            }
        }

        // Kotlin's Unit-coercion rule: a call whose result is used where Unit is
        // expected (e.g. the trailing expression of a `(T) -> Unit` lambda body,
        // such as `also { it.append(x) }`) does not need its return type to be
        // Unit — the value is simply discarded. Skip the return-type constraint
        // in that case so overload candidates aren't rejected solely because
        // none of them happen to return Unit.
        if let expectedType, expectedType != ctx.types.unitType {
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

        var solveResult = solveConstraints(
            constraints,
            solver: solver,
            typeSystem: ctx.types
        )
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
        let substitution: [TypeVarID: TypeID]
        switch solveResult {
        case let .success(value):
            substitution = value
        case let .constraintFailure(diagnostic):
            return .constraintFailure(diagnostic)
        case .rejected:
            return .rejected
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

        // Emit KSWIFTK-SEMA-INFER when a type variable could not be inferred
        // (solver returned errorType because it had no bounds).
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
            substitutedTypeArguments: substitution,
            parameterMapping: parameterMapping,
            usesVararg: normalizeFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count).contains(true)
        ))
    }

    private func buildReceiverConstraints(
        signature: FunctionSignature,
        implicitReceiverType: TypeID?,
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
            let upperBounds = symbols.typeParameterUpperBounds(for: typeParam.symbol)
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
            classType.args.contains { argument in
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
        sema: SemaModule
    ) -> Bool {
        let typeSystem = sema.types
        let isVararg = normalizeFlags(signature.valueParameterIsVararg, count: signature.parameterTypes.count)
        var processedAll = true
        for argIndex in call.args.indices {
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
            // Explicit type arguments supply a concrete literal expectation,
            // while constraints still target the original type parameter.
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

            let decomposed = decomposeSubtypeConstraint(
                subtype: argType,
                supertype: paramType,
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

    /// Returns the source-level element type represented by a spread argument.
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

    private func selectResult(
        from viable: [ViableCandidate],
        call: CallExpr,
        typeSystem: TypeSystem,
        candidateFailures: [Diagnostic]
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
        if viable.count == 1 {
            return viable[0].toResolvedCall()
        }
        if let chosen = pickMostSpecific(viable, call: call, typeSystem: typeSystem) {
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
        let usesVararg: Bool

        func toResolvedCall() -> ResolvedCall {
            ResolvedCall(
                chosenCallee: symbol,
                substitutedTypeArguments: substitutedTypeArguments,
                parameterMapping: parameterMapping,
                diagnostic: nil
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
        typeSystem: TypeSystem
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
        // and mismatched-signature members stay genuinely ambiguous.
        let tied = winners.isEmpty ? candidates : winners
        if tied.count > 1,
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
                let rhsDefaults = normalizeFlags(rhs.signature.valueParameterHasDefaultValues, count: rhsCount)
                let rhsVarargs = normalizeFlags(rhs.signature.valueParameterIsVararg, count: rhsCount)
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
        if let lhsReceiver = lhs.instantiatedReceiverType,
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

    /// Returns `true` if `signature` declares any receiver or parameter type
    /// that contains a type parameter (e.g. `fun <T> T.compareTo(T)`).
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
            for arg in classType.args {
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
