
extension CallTypeChecker {
    private struct LambdaParameterCandidate {
        let originalType: TypeID
        let functionType: FunctionType
    }

    func applyExplicitTypeArgs(
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
        let typeArgOffset: Int = if isConstructor,
                                    let owner = sema.symbols.parentSymbol(for: candidate) {
            sema.types.enclosingTypeParameterSymbols(for: owner).count
        } else if isConstructor {
            0
        } else {
            signature.classTypeParameterCount
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (idx, explicitTypeArg) in explicitTypeArgs.enumerated() {
            guard explicitTypeArg != TypeID.invalid else { continue }
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

    func applyDispatchReceiverClassTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard sema.symbols.symbol(candidate)?.kind != .constructor,
              signature.classTypeParameterCount > 0,
              let owner = sema.symbols.parentSymbol(for: candidate)
        else { return parameterType }
        let receivers = ctx.implicitReceiverStack.reversed().map(\.type)
            + [ctx.implicitReceiverType].compactMap { $0 }
            + ctx.outerReceiverTypes.reversed().map(\.type)
        for receiver in receivers {
            guard let receiverClass = resolveClassType(receiver, sema: sema),
                  let ownerArgs = sema.types.liftedNominalSupertypeArgs(
                      from: receiverClass.classSymbol,
                      childArgs: receiverClass.args,
                      to: owner
                  ),
                  ownerArgs.count >= signature.classTypeParameterCount
            else { continue }
            let variables = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            var substitution: [TypeVarID: TypeID] = [:]
            for (index, symbol) in signature.typeParameterSymbols
                .prefix(signature.classTypeParameterCount)
                .enumerated()
            {
                guard let variable = variables[symbol] else { continue }
                switch ownerArgs[index] {
                case let .invariant(type), let .in(type), let .out(type):
                    substitution[variable] = type
                case .star:
                    break
                }
            }
            return sema.types.substituteTypeParameters(
                in: parameterType, substitution: substitution, typeVarBySymbol: variables
            )
        }
        return parameterType
    }

    func applyReceiverClassTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        receiverType: TypeID?,
        classTypeParametersOnly: Bool = false,
        sema: SemaModule
    ) -> TypeID {
        guard sema.symbols.symbol(candidate)?.kind != .constructor,
              !signature.typeParameterSymbols.isEmpty,
              let callSiteReceiverType = receiverType
        else {
            return parameterType
        }

        let declaredReceiverClass = signature.receiverType.flatMap { resolveClassType($0, sema: sema) }
        let receiverOwner = declaredReceiverClass?.classSymbol ?? sema.symbols.parentSymbol(for: candidate)
        let callSiteClass = resolveClassType(callSiteReceiverType, sema: sema)
            ?? receiverOwner.flatMap {
                receiverClassTypeFromUpperBounds(callSiteReceiverType, matching: $0, sema: sema)
            }
        guard let callSiteClass else { return parameterType }

        let declaredClassArgs: [TypeArg]
        let concreteClassArgs: [TypeArg]
        if let declaredClass = declaredReceiverClass {
            if declaredClass.classSymbol == callSiteClass.classSymbol,
               declaredClass.args.count == callSiteClass.args.count {
                declaredClassArgs = declaredClass.args
                concreteClassArgs = callSiteClass.args
            } else if sema.types.isNominalSubtypeSymbol(callSiteClass.classSymbol, of: declaredClass.classSymbol) {
                declaredClassArgs = declaredClass.args
                guard let lifted = sema.types.liftedNominalSupertypeArgs(
                    from: callSiteClass.classSymbol,
                    childArgs: callSiteClass.args,
                    to: declaredClass.classSymbol
                ), lifted.count == declaredClassArgs.count else {
                    return parameterType
                }
                concreteClassArgs = lifted
            } else {
                return parameterType
            }
        } else if signature.classTypeParameterCount > 0 {
            declaredClassArgs = signature.typeParameterSymbols.prefix(signature.classTypeParameterCount).map {
                .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
            }
            if let owner = sema.symbols.parentSymbol(for: candidate),
               let lifted = sema.types.liftedNominalSupertypeArgs(
                   from: callSiteClass.classSymbol, childArgs: callSiteClass.args, to: owner
               ), lifted.count >= signature.classTypeParameterCount {
                concreteClassArgs = Array(lifted.prefix(signature.classTypeParameterCount))
            } else if callSiteClass.args.count >= signature.classTypeParameterCount {
                concreteClassArgs = Array(callSiteClass.args.prefix(signature.classTypeParameterCount))
            } else {
                return parameterType
            }
        } else {
            return parameterType
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for index in 0 ..< declaredClassArgs.count {
            let declaredArg: TypeID
            switch declaredClassArgs[index] {
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
            // An extension's own type parameter is only constrained by the
            // receiver (`Array<out T>` accepts `Array<IntArray>` with any
            // `T :> IntArray`), so it must stay open for the other arguments.
            if classTypeParametersOnly,
               !signature.typeParameterSymbols.prefix(signature.classTypeParameterCount)
                   .contains(declaredTypeParam.symbol)
            {
                continue
            }
            var concreteType: TypeID
            switch concreteClassArgs[index] {
            case let .invariant(type), let .out(type), let .in(type):
                concreteType = type
            case .star:
                let bounds = sema.symbols.typeParameterUpperBounds(for: declaredTypeParam.symbol)
                concreteType = bounds.isEmpty ? sema.types.nullableAnyType : sema.types.glb(bounds)
            }
            // A nullable declared argument owns its `?`: matching `C<T?>`
            // against `C<X?>` determines `T` only up to `{X, X?}`, mirroring
            // the `X <: T` bound `decomposeSubtypeConstraintImpl` derives
            // from `X? <: T?` (KUU-3976). When every upper bound of `T` is
            // non-nullable (`T : Any`), `X` is the unique solution, so the
            // substituted types must use it: binding `X?` here would violate
            // the bound once it reaches the argument check. When a bound
            // still admits null (`T : Any?`), the whole `X?` argument stays —
            // it matches the variable Kotlin's `Nothing? <: T` picks.
            if declaredTypeParam.nullability == .nullable {
                let bounds = sema.symbols.typeParameterUpperBounds(for: declaredTypeParam.symbol)
                if !bounds.isEmpty,
                   bounds.allSatisfy({ sema.types.nullability(of: $0) == .nonNull })
                {
                    concreteType = sema.types.makeNonNullable(concreteType)
                }
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

    func applyReceiverBoundFunctionTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard sema.symbols.symbol(candidate)?.kind != .constructor,
              signature.classTypeParameterCount < signature.typeParameterSymbols.count,
              let callSiteReceiverType = receiverType,
              let declaredReceiver = signature.receiverType,
              let declaredClass = resolveClassType(declaredReceiver, sema: sema)
        else {
            return parameterType
        }
        let callSiteClass = resolveClassType(callSiteReceiverType, sema: sema)
            ?? receiverClassTypeFromUpperBounds(
                callSiteReceiverType, matching: declaredClass.classSymbol, sema: sema
            )
        guard let callSiteClass else { return parameterType }

        let declaredClassArgs: [TypeArg]
        let concreteClassArgs: [TypeArg]
        if callSiteClass.classSymbol == declaredClass.classSymbol,
           callSiteClass.args.count == declaredClass.args.count {
            declaredClassArgs = declaredClass.args
            concreteClassArgs = callSiteClass.args
        } else if sema.types.isNominalSubtypeSymbol(callSiteClass.classSymbol, of: declaredClass.classSymbol),
                  let lifted = sema.types.liftedNominalSupertypeArgs(
                      from: callSiteClass.classSymbol,
                      childArgs: callSiteClass.args,
                      to: declaredClass.classSymbol
                  ),
                  lifted.count == declaredClass.args.count {
            declaredClassArgs = declaredClass.args
            concreteClassArgs = lifted
        } else {
            return parameterType
        }

        let functionTypeParameterSymbols = Set(
            signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
        )
        guard !functionTypeParameterSymbols.isEmpty else { return parameterType }
        let variances = sema.types.normalizedNominalVariances(
            for: declaredClass.classSymbol, arity: declaredClassArgs.count
        )
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for index in 0 ..< declaredClassArgs.count {
            let declaredVariance = index < variances.count ? variances[index] : .invariant
            let projection = sema.types.composedProjection(
                declarationVariance: declaredVariance, useSite: declaredClassArgs[index]
            )
            let declaredArg: TypeID
            switch projection {
            case let .invariant(type), let .in(type):
                declaredArg = type
            case .out, .star, .invalid:
                continue
            }
            guard case let .typeParam(declaredTypeParam) = sema.types.kind(of: declaredArg),
                  functionTypeParameterSymbols.contains(declaredTypeParam.symbol),
                  let typeVar = typeVarBySymbol[declaredTypeParam.symbol]
            else {
                continue
            }
            var concreteType: TypeID
            switch concreteClassArgs[index] {
            case let .invariant(type), let .out(type), let .in(type):
                concreteType = type
            case .star:
                let bounds = sema.symbols.typeParameterUpperBounds(for: declaredTypeParam.symbol)
                concreteType = bounds.isEmpty ? sema.types.nullableAnyType : sema.types.glb(bounds)
            }
            if declaredTypeParam.nullability == .nullable {
                let bounds = sema.symbols.typeParameterUpperBounds(for: declaredTypeParam.symbol)
                if !bounds.isEmpty,
                   bounds.allSatisfy({ sema.types.nullability(of: $0) == .nonNull })
                {
                    concreteType = sema.types.makeNonNullable(concreteType)
                }
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

    private func receiverClassTypeFromUpperBounds(
        _ receiverType: TypeID,
        matching receiverOwner: SymbolID,
        sema: SemaModule
    ) -> ClassType? {
        var pending = [receiverType]
        var visitedTypes: Set<TypeID> = []
        while let current = pending.popLast() {
            let readable = sema.types.makeNonNullable(sema.types.capturedReadableUpperBound(of: current))
            guard visitedTypes.insert(readable).inserted else { continue }
            switch sema.types.kind(of: readable) {
            case .classType:
                guard let nominal = resolveClassType(readable, sema: sema),
                      nominal.classSymbol == receiverOwner
                          || sema.types.isNominalSubtypeSymbol(nominal.classSymbol, of: receiverOwner)
                else {
                    continue
                }
                return nominal
            case let .typeParam(parameter):
                let bounds = parameter.capture.map { [$0.upper] }
                    ?? sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
                pending.append(contentsOf: bounds.reversed())
            case let .intersection(parts):
                pending.append(contentsOf: parts.reversed())
            default:
                continue
            }
        }
        return nil
    }

    func applyFunctionReceiverTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard let receiverType,
              let declaredReceiver = signature.receiverType,
              !signature.typeParameterSymbols.isEmpty
        else {
            return parameterType
        }
        let nonNullDeclaredReceiver = sema.types.makeNonNullable(declaredReceiver)
        guard case let .typeParam(receiverTypeParam) = sema.types.kind(of: nonNullDeclaredReceiver) else {
            return parameterType
        }
        if let index = signature.typeParameterSymbols.firstIndex(of: receiverTypeParam.symbol),
           index < signature.classTypeParameterCount {
            return parameterType
        }
        let substitutionReceiverType = declaredReceiver == nonNullDeclaredReceiver
            ? receiverType
            : sema.types.makeNonNullable(receiverType)
        guard !sema.types.typeContainsTypeParam(substitutionReceiverType, symbol: receiverTypeParam.symbol) else {
            return parameterType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        guard let typeVar = typeVarBySymbol[receiverTypeParam.symbol] else {
            return parameterType
        }
        let substitution: [TypeVarID: TypeID] = [typeVar: substitutionReceiverType]
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func applyInferredArgumentTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        receiverType: TypeID? = nil,
        fixesReceiverBoundInputs: Bool = false,
        inferredNonLambdaArgTypes: [Int: TypeID],
        inferredLambdaInputAnnotations: [Int: [TypeID?]] = [:],
        nonLambdaArgumentTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver?,
        sema: SemaModule
    ) -> TypeID {
        guard let resolver,
              !signature.typeParameterSymbols.isEmpty
        else {
            return parameterType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let receiverInfersTypeParameters = signature.receiverType.map { declaredReceiver in
            signature.typeParameterSymbols.contains { symbol in
                sema.types.typeContainsTypeParam(declaredReceiver, symbol: symbol)
            }
        } ?? false
        var result = parameterType
        if !inferredNonLambdaArgTypes.isEmpty || !inferredLambdaInputAnnotations.isEmpty {
            var substitution = resolver.probeArgumentTypeSubstitution(
                signature: signature,
                typeVarBySymbol: typeVarBySymbol,
                knownArgumentTypes: inferredNonLambdaArgTypes,
                knownLambdaInputAnnotations: inferredLambdaInputAnnotations,
                typeSystem: sema.types
            )
            // Kotlin fixes only the variables a lambda's input types mention
            // before analysing it; variables occurring solely in the lambda's
            // return type (e.g. `R` in `fold(f: (T) -> R, g: (Throwable) -> R)`)
            // stay open so this lambda's own return type contributes a lower
            // bound to the final solve. Seeding them from a sibling argument's
            // already-inferred type would wrongly pin `R`:
            // `fold({ it + 1 }, { it.message })` would check the second lambda
            // against `(Throwable) -> Int`.
            if case let .functionType(lambdaFunctionType) = sema.types.kind(of: result) {
                let lambdaInputs = lambdaFunctionType.params
                    + lambdaFunctionType.contextReceivers
                    + (lambdaFunctionType.receiver.map { [$0] } ?? [])
                var inputVariables: Set<TypeVarID> = []
                for (symbol, variable) in typeVarBySymbol
                where lambdaInputs.contains(where: {
                    sema.types.typeContainsTypeParam($0, symbol: symbol)
                }) {
                    inputVariables.insert(variable)
                }
                // A return-only variable is still fixed when a plain (non
                // lambda/callable-reference) argument already determines it:
                // `combineInternal`'s `{ arrayOfNulls(flows.size) }` must see
                // `Array<T>` with T bound from `flows`, or the body's own
                // generic call has no expected type to infer its type
                // argument from.
                var returnOnlySafeVariables = Set<TypeVarID>()
                if !nonLambdaArgumentTypes.isEmpty {
                    let nonLambdaSubstitution = resolver.probeArgumentTypeSubstitution(
                        signature: signature,
                        typeVarBySymbol: typeVarBySymbol,
                        knownArgumentTypes: nonLambdaArgumentTypes,
                        typeSystem: sema.types
                    )
                    returnOnlySafeVariables = Set(nonLambdaSubstitution.keys)
                        .subtracting(inputVariables)
                }
                substitution = substitution.filter {
                    inputVariables.contains($0.key) || returnOnlySafeVariables.contains($0.key)
                }
            }
            if !substitution.isEmpty {
                result = sema.types.substituteTypeParameters(
                    in: result,
                    substitution: substitution,
                    typeVarBySymbol: typeVarBySymbol
                )
            }
        }
        if fixesReceiverBoundInputs,
           let receiverType,
           receiverInfersTypeParameters,
           case let .functionType(functionType) = sema.types.kind(of: result)
        {
            let receiverSubstitution = resolver.probeArgumentTypeSubstitution(
                signature: signature,
                typeVarBySymbol: typeVarBySymbol,
                knownArgumentTypes: inferredNonLambdaArgTypes,
                knownLambdaInputAnnotations: inferredLambdaInputAnnotations,
                typeSystem: sema.types,
                implicitReceiverType: receiverType
            )
            if !receiverSubstitution.isEmpty {
                func substituted(_ type: TypeID) -> TypeID {
                    sema.types.substituteTypeParameters(
                        in: type,
                        substitution: receiverSubstitution,
                        typeVarBySymbol: typeVarBySymbol
                    )
                }
                result = sema.types.make(.functionType(FunctionType(
                    contextReceivers: functionType.contextReceivers,
                    receiver: functionType.receiver.map(substituted),
                    params: functionType.params.map(substituted),
                    returnType: functionType.returnType,
                    isSuspend: functionType.isSuspend,
                    isCallableReference: functionType.isCallableReference,
                    nullability: functionType.nullability,
                    throws: functionType.throws
                )))
            }
        }
        return result
    }

    private func contextualCallableParameterType(
        _ parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        explicitTypeArgs: [TypeID],
        receiverType: TypeID?,
        fixesReceiverBoundInputs: Bool = false,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        inferredLambdaInputAnnotations: [Int: [TypeID?]] = [:],
        nonLambdaArgumentTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        sema: SemaModule
    ) -> TypeID {
        let explicitSubstituted = applyExplicitTypeArgs(
            to: parameterType,
            signature: signature,
            candidate: candidate,
            explicitTypeArgs: explicitTypeArgs,
            sema: sema
        )
        let receiverSubstituted = applyReceiverClassTypeArgs(
            to: explicitSubstituted,
            signature: signature,
            candidate: candidate,
            receiverType: receiverType,
            sema: sema
        )
        let functionReceiverSubstituted = applyFunctionReceiverTypeArgs(
            to: receiverSubstituted,
            signature: signature,
            receiverType: receiverType,
            sema: sema
        )
        return applyInferredArgumentTypeArgs(
            to: functionReceiverSubstituted,
            signature: signature,
            receiverType: receiverType,
            fixesReceiverBoundInputs: fixesReceiverBoundInputs,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            inferredLambdaInputAnnotations: inferredLambdaInputAnnotations,
            nonLambdaArgumentTypes: nonLambdaArgumentTypes,
            resolver: resolver,
            sema: sema
        )
    }

    private func contextualInferenceInputsForLambda(
        at lambdaArgumentIndex: Int,
        args: [CallArgument],
        callRange: SourceRange,
        signature: FunctionSignature,
        inferredNonLambdaArgTypes: [Int: TypeID],
        lambdaInputAnnotations: [TypeID?]?,
        ctx: TypeInferenceContext
    ) -> (argumentTypes: [Int: TypeID], lambdaInputAnnotations: [Int: [TypeID?]], nonLambdaArgumentTypes: [Int: TypeID]) {
        guard let mapping = parameterMappingForCallArguments(
            args, in: signature, callRange: callRange, ctx: ctx
        ) else {
            return ([:], [:], [:])
        }

        let lambdaParameterIndex = mapping[lambdaArgumentIndex]
        let lambdaFunctionType: FunctionType?
        if let lambdaParameterIndex,
           signature.parameterTypes.indices.contains(lambdaParameterIndex),
           case let .functionType(functionType) = ctx.sema.types.kind(
               of: signature.parameterTypes[lambdaParameterIndex]
           ) {
            lambdaFunctionType = functionType
        } else {
            lambdaFunctionType = nil
        }
        let usableAnnotations: [TypeID?]? = if let lambdaInputAnnotations,
                                               let lambdaFunctionType,
                                               lambdaInputAnnotations.count == lambdaFunctionType.params.count,
                                               lambdaInputAnnotations.contains(where: { $0 != nil }) {
            lambdaInputAnnotations
        } else {
            nil
        }

        let constrainedTypeParameters = Set(signature.typeParameterSymbols.filter { symbol in
            guard let usableAnnotations, let lambdaFunctionType else { return false }
            return zip(lambdaFunctionType.params, usableAnnotations).contains { expectedInput, annotation in
                annotation != nil && ctx.sema.types.typeContainsTypeParam(expectedInput, symbol: symbol)
            }
        })

        var argumentTypes: [Int: TypeID] = [:]
        var nonLambdaArgumentTypes: [Int: TypeID] = [:]
        for (argumentIndex, type) in inferredNonLambdaArgTypes {
            guard args.indices.contains(argumentIndex),
                  let parameterIndex = mapping[argumentIndex],
                  signature.parameterTypes.indices.contains(parameterIndex)
            else { continue }
            if usableAnnotations != nil,
               isFlexibleLambdaInferenceArgument(args[argumentIndex].expr, ctx: ctx),
               constrainedTypeParameters.contains(where: { symbol in
                   ctx.sema.types.typeContainsTypeParam(
                       signature.parameterTypes[parameterIndex], symbol: symbol
                   )
               }) {
                continue
            }
            argumentTypes[parameterIndex] = type
            if !isLambdaShapedArgument(args[argumentIndex].expr, ctx: ctx) {
                nonLambdaArgumentTypes[parameterIndex] = type
            }
        }

        let lambdaAnnotationsByParameter: [Int: [TypeID?]]
        if let usableAnnotations, let lambdaParameterIndex {
            lambdaAnnotationsByParameter = [lambdaParameterIndex: usableAnnotations]
        } else {
            lambdaAnnotationsByParameter = [:]
        }
        return (argumentTypes, lambdaAnnotationsByParameter, nonLambdaArgumentTypes)
    }

    private func isLambdaShapedArgument(_ expr: ExprID, ctx: TypeInferenceContext) -> Bool {
        switch ctx.ast.arena.expr(expr) {
        case .lambdaLiteral, .callableRef:
            return true
        case .blockExpr:
            return ctx.ast.arena.isAnonymousFunction(expr)
        default:
            return false
        }
    }

    private func isFlexibleLambdaInferenceArgument(_ expr: ExprID, ctx: TypeInferenceContext) -> Bool {
        switch ctx.ast.arena.expr(expr) {
        case .intLiteral, .uintLiteral, .nullLiteral:
            return true
        case let .unaryExpr(op, operand, _) where op == .unaryPlus || op == .unaryMinus:
            switch ctx.ast.arena.expr(operand) {
            case .intLiteral, .uintLiteral: return true
            default: return false
            }
        default:
            return false
        }
    }

    private func explicitLambdaInputAnnotations(
        at index: Int,
        args: [CallArgument],
        ctx: TypeInferenceContext
    ) -> [TypeID?]? {
        guard args.indices.contains(index),
              case let .lambdaLiteral(parameters, _, _, _) = ctx.ast.arena.expr(args[index].expr),
              ctx.ast.arena.lambdaParamTypeRefs(for: args[index].expr)?.contains(where: { $0 != nil }) == true
        else { return nil }
        return driver.exprChecker.resolveLambdaParamAnnotations(
            args[index].expr, ctx: ctx, paramCount: parameters.count
        )
    }

    private func fixesReceiverBoundLambdaInputs(
        at index: Int,
        args: [CallArgument],
        explicitTypeArgs: [TypeID],
        ctx: TypeInferenceContext
    ) -> Bool {
        explicitTypeArgs.isEmpty
            && index < args.count
            && ctx.ast.arena.lambdaParamTypeRefs(for: args[index].expr)?.contains(where: { $0 != nil }) != true
    }

    func callableReferenceExpectedType(
        at index: Int,
        argumentLabel: InternedString?,
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        var matchingParameterTypes: [TypeID] = []
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let parameterIndex = parameterIndexForCallArgument(
                      at: index, label: argumentLabel, in: signature, sema: sema
                  ),
                  parameterIndex < signature.parameterTypes.count
            else {
                continue
            }
            let parameterMapping = parameterMappingForCallArguments(args, in: signature, callRange: callRange, ctx: ctx)
            var knownParameterTypes: [Int: TypeID] = [:]
            for (argumentIndex, type) in inferredNonLambdaArgTypes {
                if let parameterIndex = parameterMapping?[argumentIndex] {
                    knownParameterTypes[parameterIndex] = type
                }
            }
            let parameterType = contextualCallableParameterType(
                signature.parameterTypes[parameterIndex],
                signature: signature,
                candidate: candidate,
                explicitTypeArgs: explicitTypeArgs,
                receiverType: receiverType,
                inferredNonLambdaArgTypes: knownParameterTypes,
                resolver: resolver,
                sema: sema
            )
            if candidates.count == 1 {
                return parameterType
            }
            if case .functionType = sema.types.kind(of: parameterType) {
                matchingParameterTypes.append(parameterType)
            } else if driver.helpers.samFunctionType(for: parameterType, sema: sema) != nil {
                matchingParameterTypes.append(parameterType)
            }
        }
        guard let firstType = matchingParameterTypes.first else {
            return nil
        }
        let allSame = matchingParameterTypes.dropFirst().allSatisfy { $0 == firstType }
        return allSame ? firstType : nil
    }

    static let inputOnlyExternalLinkNames: Set<String> = [
    ]

    func lambdaParameterTypeForArgument(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        in signature: FunctionSignature,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        guard let mapping = parameterMappingForCallArguments(
            args, in: signature, callRange: callRange, ctx: ctx
        ), let parameterIndex = mapping[index],
              signature.parameterTypes.indices.contains(parameterIndex)
        else {
            return nil
        }
        return signature.parameterTypes[parameterIndex]
    }

    func lambdaLiteralExpectedType(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> (
        type: TypeID?,
        isInputOnly: Bool,
        blocksRefinement: Bool,
        hasAmbiguousImplicitParameterShape: Bool
    ) {
        let effectiveReceiverType = receiverType ?? ctx.implicitReceiverType
        let lambdaInputAnnotations = explicitLambdaInputAnnotations(at: index, args: args, ctx: ctx)

        if !candidates.isEmpty,
           candidates.allSatisfy({
               Self.inputOnlyExternalLinkNames.contains(sema.symbols.externalLinkName(for: $0) ?? "")
           }),
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let rawType = lambdaParameterTypeForArgument(
               at: index,
               args: args,
               callRange: callRange,
               in: signature,
               ctx: ctx
           )
        {
            let substituted = contextualCallableParameterType(
                rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                receiverType: effectiveReceiverType,
                sema: sema
            )
            return (substituted, true, false, false)
        }

        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let rawType = lambdaParameterTypeForArgument(
               at: index,
               args: args,
               callRange: callRange,
               in: signature,
               ctx: ctx
           )
        {
            let inferenceInputs = contextualInferenceInputsForLambda(
                at: index,
                args: args,
                callRange: callRange,
                signature: signature,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                lambdaInputAnnotations: lambdaInputAnnotations,
                ctx: ctx
            )
            let substituted = contextualCallableParameterType(
                rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                receiverType: effectiveReceiverType,
                fixesReceiverBoundInputs: fixesReceiverBoundLambdaInputs(
                    at: index, args: args, explicitTypeArgs: explicitTypeArgs, ctx: ctx
                ),
                inferredNonLambdaArgTypes: inferenceInputs.argumentTypes,
                inferredLambdaInputAnnotations: inferenceInputs.lambdaInputAnnotations,
                nonLambdaArgumentTypes: inferenceInputs.nonLambdaArgumentTypes,
                resolver: resolver,
                sema: sema
            )
            return (substituted, false, false, false)
        }

        let parameterCandidates = lambdaParameterCandidates(
            at: index,
            args: args,
            callRange: callRange,
            candidates: candidates,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: effectiveReceiverType,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            lambdaInputAnnotations: lambdaInputAnnotations,
            resolver: resolver,
            sema: sema,
            ctx: ctx
        )
        guard !parameterCandidates.isEmpty else {
            return (nil, false, false, false)
        }

        let annotationCompatibleCandidates = parameterCandidates.filter { candidate in
            guard let lambdaInputAnnotations,
                  lambdaInputAnnotations.count == candidate.functionType.params.count
            else {
                return true
            }
            return zip(candidate.functionType.params, lambdaInputAnnotations).allSatisfy { expected, annotation in
                guard let annotation else { return true }
                return sema.types.isSubtype(expected, annotation)
            }
        }
        let contextualCandidates = annotationCompatibleCandidates.isEmpty
            ? parameterCandidates
            : annotationCompatibleCandidates

        if let first = contextualCandidates.first,
           contextualCandidates.dropFirst().allSatisfy({ $0.originalType == first.originalType })
        {
            return (first.originalType, false, false, false)
        }

        guard let sharedType = sharedLambdaInputOnlyType(
            from: contextualCandidates,
            types: sema.types
        ) else {
            let concreteCandidates = contextualCandidates.filter {
                !typeMentionsTypeParameter($0.originalType, sema: sema)
            }
            if let firstConcrete = concreteCandidates.first,
               !concreteCandidates.isEmpty,
               concreteCandidates.dropFirst().allSatisfy({ $0.originalType == firstConcrete.originalType })
            {
                return (firstConcrete.originalType, false, false, false)
            }
            let isImplicitSingleParameterAmbiguous = contextualCandidates.allSatisfy { candidate in
                guard candidate.functionType.params.count == 1,
                      let onlyParam = candidate.functionType.params.first
                else {
                    return false
                }
                return !typeMentionsTypeParameter(onlyParam, sema: sema)
            }
            return (nil, false, contextualCandidates.count > 1, isImplicitSingleParameterAmbiguous)
        }
        return (sharedType, true, false, false)
    }

    func typeMentionsTypeParameter(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .typeParam:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    typeMentionsTypeParameter(inner, sema: sema)
                case .star:
                    false
                }
            }
        case let .functionType(functionType):
            return functionType.params.contains { typeMentionsTypeParameter($0, sema: sema) }
                || typeMentionsTypeParameter(functionType.returnType, sema: sema)
                || (functionType.receiver.map { typeMentionsTypeParameter($0, sema: sema) } ?? false)
        case let .intersection(members):
            return members.contains { typeMentionsTypeParameter($0, sema: sema) }
        default:
            return false
        }
    }

    private func lambdaParameterCandidates(
        at index: Int,
        args: [CallArgument],
        callRange: SourceRange,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        lambdaInputAnnotations: [TypeID?]?,
        resolver: OverloadResolver? = nil,
        sema: SemaModule,
        ctx: TypeInferenceContext
    ) -> [LambdaParameterCandidate] {
        candidates.compactMap { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let rawParameterType = lambdaParameterTypeForArgument(
                      at: index,
                      args: args,
                      callRange: callRange,
                      in: signature,
                      ctx: ctx
                  )
            else {
                return nil
            }
            let fixesReceiverBoundInputs = fixesReceiverBoundLambdaInputs(
                at: index, args: args, explicitTypeArgs: explicitTypeArgs, ctx: ctx
            )
            let inferenceInputs = contextualInferenceInputsForLambda(
                at: index,
                args: args,
                callRange: callRange,
                signature: signature,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                lambdaInputAnnotations: lambdaInputAnnotations,
                ctx: ctx
            )
            let parameterType = contextualCallableParameterType(
                rawParameterType,
                signature: signature,
                candidate: candidate,
                explicitTypeArgs: explicitTypeArgs,
                receiverType: receiverType,
                fixesReceiverBoundInputs: fixesReceiverBoundInputs,
                inferredNonLambdaArgTypes: inferenceInputs.argumentTypes,
                inferredLambdaInputAnnotations: inferenceInputs.lambdaInputAnnotations,
                nonLambdaArgumentTypes: inferenceInputs.nonLambdaArgumentTypes,
                resolver: resolver,
                sema: sema
            )
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
            returnType: types.nullableAnyType,
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
}
