
extension CallTypeChecker {
    private struct LambdaParameterCandidate {
        let originalType: TypeID
        let functionType: FunctionType
    }

    /// Applies explicit type arguments to a parameter type from a given signature.
    /// When explicit type args are provided, substitutes them into the parameter type.
    /// - Parameter typeArgOffset: Index into `signature.typeParameterSymbols` at which the
    ///   explicit type args begin. For constructors this is 0 (explicit args map to the class's
    ///   own type parameters). For non-constructor member functions this should be
    ///   `signature.classTypeParameterCount`, so that the explicit args skip the leading class
    ///   type parameters (which are inferred from the receiver) and map only to the function's
    ///   own type parameters.
    private func applyExplicitTypeArgs(
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
        let typeArgOffset = isConstructor ? 0 : signature.classTypeParameterCount
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (idx, explicitTypeArg) in explicitTypeArgs.enumerated() {
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
        guard signature.classTypeParameterCount > 0,
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

    /// Substitutes the class type parameters used in `signature.receiverType`
    /// with the concrete generic arguments of the call-site `receiverType`. This
    /// lets trailing-lambda expected types be computed with the receiver's
    /// generic substitutions already applied, so `it` in `xs.map { it * 10 }`
    /// is seen as `Int` rather than `T`.
    ///
    /// For member functions whose declared receiver type is not available in the
    /// signature, the leading `classTypeParameterCount` type parameters are taken
    /// to be the class type parameters and are substituted from the call-site
    /// receiver's concrete class arguments.
    func applyReceiverClassTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        candidate: SymbolID,
        receiverType: TypeID?,
        sema: SemaModule
    ) -> TypeID {
        guard sema.symbols.symbol(candidate)?.kind != .constructor,
              !signature.typeParameterSymbols.isEmpty,
              let callSiteReceiverType = receiverType,
              let callSiteClass = resolveClassType(callSiteReceiverType, sema: sema)
        else {
            return parameterType
        }

        let declaredClassArgs: [TypeArg]
        let concreteClassArgs: [TypeArg]
        if let signatureReceiverType = signature.receiverType,
           let declaredClass = resolveClassType(signatureReceiverType, sema: sema) {
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
        } else if signature.classTypeParameterCount > 0,
                  callSiteClass.args.count >= signature.classTypeParameterCount {
            declaredClassArgs = signature.typeParameterSymbols.prefix(signature.classTypeParameterCount).map {
                .invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0, nullability: .nonNull))))
            }
            if let owner = sema.symbols.parentSymbol(for: candidate),
               let lifted = sema.types.liftedNominalSupertypeArgs(
                   from: callSiteClass.classSymbol, childArgs: callSiteClass.args, to: owner
               ) {
                concreteClassArgs = lifted
            } else {
                concreteClassArgs = Array(callSiteClass.args.prefix(signature.classTypeParameterCount))
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
            let concreteType: TypeID = switch concreteClassArgs[index] {
            case let .invariant(type), let .out(type), let .in(type):
                type
            case .star:
                sema.types.anyType
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

    /// Substitutes the receiver type parameter of `signature` with the concrete
    /// call-site receiver type. For extension functions like `fun <T> T.apply(block: T.() -> Unit)`,
    /// the lambda's expected type `T.() -> Unit` must become `ConcreteType.() -> Unit`
    /// before the lambda body is type-checked so that unqualified member access on
    /// the implicit receiver resolves correctly.
    private func applyFunctionReceiverTypeArgs(
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
        // Class type parameters at the start of the list are handled by applyReceiverClassTypeArgs.
        if let index = signature.typeParameterSymbols.firstIndex(of: receiverTypeParam.symbol),
           index < signature.classTypeParameterCount {
            return parameterType
        }
        // `T` captures the full receiver type; only `T?` strips nullability
        // before substituting T (e.g. `nullable.also { it }` versus `T?.ext`).
        let substitutionReceiverType = declaredReceiver == nonNullDeclaredReceiver
            ? receiverType
            : sema.types.makeNonNullable(receiverType)
        // Avoid circular substitution when the concrete receiver still references the same type parameter.
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

    /// Substitutes `parameterType`'s type parameters using bindings inferred
    /// from the call's non-lambda arguments, which are already type-checked by
    /// the time a lambda argument's expected type is computed. Without this,
    /// a generic higher-order function's lambda parameter keeps the raw,
    /// unsubstituted type parameter as its static type (e.g. `T` instead of
    /// `Int`), which then fails operator/member resolution inside the lambda
    /// body even though the type is fully determined by the other arguments.
    private func applyInferredArgumentTypeArgs(
        to parameterType: TypeID,
        signature: FunctionSignature,
        inferredNonLambdaArgTypes: [Int: TypeID],
        resolver: OverloadResolver?,
        sema: SemaModule
    ) -> TypeID {
        guard let resolver,
              !inferredNonLambdaArgTypes.isEmpty,
              !signature.typeParameterSymbols.isEmpty
        else {
            return parameterType
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitution = resolver.probeArgumentTypeSubstitution(
            signature: signature,
            typeVarBySymbol: typeVarBySymbol,
            knownArgumentTypes: inferredNonLambdaArgTypes,
            typeSystem: sema.types
        )
        guard !substitution.isEmpty else { return parameterType }
        return sema.types.substituteTypeParameters(
            in: parameterType,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    func callableReferenceExpectedType(
        at index: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        sema: SemaModule
    ) -> TypeID? {
        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let parameterIndex = parameterIndexForCallArgument(
               at: index, label: argumentLabel, in: signature, sema: sema
           ),
           parameterIndex < signature.parameterTypes.count
        {
            let rawType = signature.parameterTypes[parameterIndex]
            return applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
        }

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
            let parameterType = applyExplicitTypeArgs(
                to: signature.parameterTypes[parameterIndex],
                signature: signature,
                candidate: candidate,
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
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

    /// Returns the parameter type for a lambda argument, including Kotlin's
    /// trailing-lambda rule: a final lambda may bind to a later function
    /// parameter when the parameters between the explicit arguments and that
    /// function parameter all have defaults (for example
    /// `joinToString("|") { ... }`).
    func lambdaParameterTypeForArgument(
        at index: Int,
        argumentCount: Int,
        argumentLabel: InternedString?,
        in signature: FunctionSignature,
        sema: SemaModule
    ) -> TypeID? {
        guard index >= 0 else {
            return nil
        }

        if let argumentLabel {
            for (parameterIndex, parameterSymbol) in signature.valueParameterSymbols.enumerated() {
                if sema.symbols.symbol(parameterSymbol)?.name == argumentLabel,
                   parameterIndex < signature.parameterTypes.count
                {
                    return signature.parameterTypes[parameterIndex]
                }
            }
            return nil
        }

        guard index == argumentCount - 1,
              let lastParameterIndex = signature.parameterTypes.indices.last,
              case .functionType = sema.types.kind(
                  of: sema.types.makeNonNullable(signature.parameterTypes[lastParameterIndex])
              )
        else {
            return parameterTypeForArgument(at: index, in: signature)
        }

        guard index <= lastParameterIndex,
              (index ..< lastParameterIndex).allSatisfy({ parameterIndex in
                  signature.valueParameterHasDefaultValues.indices.contains(parameterIndex)
                      && signature.valueParameterHasDefaultValues[parameterIndex]
              })
        else {
            return parameterTypeForArgument(at: index, in: signature)
        }
        return signature.parameterTypes[lastParameterIndex]
    }

    func lambdaLiteralExpectedType(
        at index: Int,
        argumentCount: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        sema: SemaModule
    ) -> (
        type: TypeID?,
        isInputOnly: Bool,
        blocksRefinement: Bool,
        hasAmbiguousImplicitParameterShape: Bool
    ) {
        // When all candidates share the same input-only HOF shape, pick the
        // first candidate and treat the lambda as input-only so that its return type is
        // not used for constraint solving — matches what the single-candidate path does.
        if !candidates.isEmpty,
           candidates.allSatisfy({
               Self.inputOnlyExternalLinkNames.contains(sema.symbols.externalLinkName(for: $0) ?? "")
           }),
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let rawType = lambdaParameterTypeForArgument(
               at: index,
               argumentCount: argumentCount,
               argumentLabel: argumentLabel,
               in: signature,
               sema: sema
           )
        {
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
            let receiverSubstituted = applyReceiverClassTypeArgs(
                to: explicitSubstituted,
                signature: signature,
                candidate: candidates[0],
                receiverType: receiverType,
                sema: sema
            )
            let substituted = applyFunctionReceiverTypeArgs(
                to: receiverSubstituted,
                signature: signature,
                receiverType: receiverType,
                sema: sema
            )
            return (substituted, true, false, false)
        }

        if candidates.count == 1,
           let signature = sema.symbols.functionSignature(for: candidates[0]),
           let rawType = lambdaParameterTypeForArgument(
               at: index,
               argumentCount: argumentCount,
               argumentLabel: argumentLabel,
               in: signature,
               sema: sema
           )
        {
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawType,
                signature: signature,
                candidate: candidates[0],
                explicitTypeArgs: explicitTypeArgs,
                sema: sema
            )
            let receiverSubstituted = applyReceiverClassTypeArgs(
                to: explicitSubstituted,
                signature: signature,
                candidate: candidates[0],
                receiverType: receiverType,
                sema: sema
            )
            let functionReceiverSubstituted = applyFunctionReceiverTypeArgs(
                to: receiverSubstituted,
                signature: signature,
                receiverType: receiverType,
                sema: sema
            )
            let substituted = applyInferredArgumentTypeArgs(
                to: functionReceiverSubstituted,
                signature: signature,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
                resolver: resolver,
                sema: sema
            )
            return (substituted, false, false, false)
        }

        let parameterCandidates = lambdaParameterCandidates(
            at: index,
            argumentCount: argumentCount,
            argumentLabel: argumentLabel,
            candidates: candidates,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: receiverType,
            inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
            resolver: resolver,
            sema: sema
        )
        guard !parameterCandidates.isEmpty else {
            return (nil, false, false, false)
        }

        if let first = parameterCandidates.first,
           parameterCandidates.dropFirst().allSatisfy({ $0.originalType == first.originalType })
        {
            return (first.originalType, false, false, false)
        }

        guard let sharedType = sharedLambdaInputOnlyType(
            from: parameterCandidates,
            types: sema.types
        ) else {
            // Candidates whose parameter type still mentions a type parameter
            // (e.g. `Sequence<T>.onEach` seen through a `String` receiver) can
            // never pin down a usable shape at this call site. When the
            // fully-concrete subset agrees on one shape, use it -- the
            // remaining candidates are infeasible or will unify to the same
            // shape once final resolution binds their type parameters.
            let concreteCandidates = parameterCandidates.filter {
                !typeMentionsTypeParameter($0.originalType, sema: sema)
            }
            if let firstConcrete = concreteCandidates.first,
               !concreteCandidates.isEmpty,
               concreteCandidates.dropFirst().allSatisfy({ $0.originalType == firstConcrete.originalType })
            {
                return (firstConcrete.originalType, false, false, false)
            }
            // The candidates disagree on this lambda's parameter shape, so no single
            // expected type can be pushed down. When every surviving candidate still
            // expects exactly one, genuinely concrete parameter type, a bare lambda
            // here would need an implicit `it` whose type cannot be determined
            // before an overload is chosen (DEBT-SEMA-004) -- e.g. `(Int) -> String`
            // vs. `(String) -> Int`. Candidates whose parameter type still mentions a
            // type parameter are excluded: two independently-registered overloads
            // (e.g. a source declaration and a synthetic vararg sibling) can each
            // mint their own distinct type-parameter symbol for what is conceptually
            // the same generic slot, so raw TypeID inequality there reflects how the
            // signatures happened to be built rather than a real shape conflict --
            // unlike concrete types, where inequality always means a real conflict.
            let isImplicitSingleParameterAmbiguous = parameterCandidates.allSatisfy { candidate in
                guard candidate.functionType.params.count == 1,
                      let onlyParam = candidate.functionType.params.first
                else {
                    return false
                }
                return !typeMentionsTypeParameter(onlyParam, sema: sema)
            }
            return (nil, false, parameterCandidates.count > 1, isImplicitSingleParameterAmbiguous)
        }
        return (sharedType, true, false, false)
    }

    /// Recursively checks whether `type` (or any nested type argument / function
    /// parameter / return type) is or mentions a type parameter. Used to keep
    /// implicit-`it` ambiguity detection scoped to genuinely concrete, conflicting
    /// parameter types rather than misreading distinct type-parameter symbols that
    /// happen to represent the same generic slot as a real conflict.
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
        argumentCount: Int,
        argumentLabel: InternedString?,
        candidates: [SymbolID],
        explicitTypeArgs: [TypeID] = [],
        receiverType: TypeID? = nil,
        inferredNonLambdaArgTypes: [Int: TypeID] = [:],
        resolver: OverloadResolver? = nil,
        sema: SemaModule
    ) -> [LambdaParameterCandidate] {
        candidates.compactMap { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let rawParameterType = lambdaParameterTypeForArgument(
                      at: index,
                      argumentCount: argumentCount,
                      argumentLabel: argumentLabel,
                      in: signature,
                      sema: sema
                  )
            else {
                return nil
            }
            // Substitute the same way the single-candidate path does, so a
            // generic receiver's arguments reach the lambda's expected type
            // (`Iterable<T>.f(transform: (T) -> R)` called on `List<Int>` must
            // expose `it: Int`, not the bare declaration type parameter `T`).
            let explicitSubstituted = applyExplicitTypeArgs(
                to: rawParameterType,
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
            let parameterType = applyInferredArgumentTypeArgs(
                to: functionReceiverSubstituted,
                signature: signature,
                inferredNonLambdaArgTypes: inferredNonLambdaArgTypes,
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
