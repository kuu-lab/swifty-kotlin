extension CallLowerer {
    func appendReifiedTypeTokens(
        chosenCallee: SymbolID?,
        callBinding: CallBinding?,
        sema: SemaModule,
        interner: StringInterner,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        guard let chosenCallee,
              let callBinding,
              let signature = sema.symbols.functionSignature(for: chosenCallee),
              !signature.reifiedTypeParameterIndices.isEmpty
        else {
            return
        }

        let carriesComponent = !kirIsRuntimeBridgedCallee(chosenCallee, sema: sema)
            && sema.symbols.symbol(chosenCallee)?.flags.contains(.legacyReifiedClassTokenABI) != true
        let intType = sema.types.make(.primitive(.int, .nonNull))
        for index in signature.reifiedTypeParameterIndices.sorted() {
            let concreteType = index < callBinding.substitutedTypeArguments.count
                ? callBinding.substitutedTypeArguments[index]
                : sema.types.anyType
            // Nested inline calls must forward the enclosing reified token;
            // a type parameter has no concrete nominal token to encode yet.
            var forwardedParameter: TypeParamType?
            var tokenType = concreteType
            switch sema.types.kind(of: concreteType) {
            case let .typeParam(parameter):
                forwardedParameter = parameter
            case let .intersection(parts):
                if parts.contains(sema.types.anyType),
                   let parameter = parts.compactMap({ part -> TypeParamType? in
                       if case let .typeParam(parameter) = sema.types.kind(of: part) { return parameter }
                       return nil
                   }).first {
                    if sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true {
                        forwardedParameter = parameter
                    } else {
                        // Kotlin 2.3.10 erases an unreified U & Any to Any for
                        // this reified invocation, rather than rejecting it.
                        tokenType = sema.types.anyType
                    }
                }
            default:
                break
            }
            let componentType = forwardedParameter.map { sema.types.make(.typeParam($0)) } ?? tokenType
            if let parameter = forwardedParameter,
               sema.symbols.symbol(parameter.symbol)?.flags.contains(.reifiedTypeParameter) == true {
                let tokenSymbol = SyntheticSymbolScheme.reifiedTypeTokenSymbol(for: parameter.symbol)
                let tokenExpr: KIRExprID
                if let capturedToken = driver.ctx.localValue(for: tokenSymbol) {
                    tokenExpr = capturedToken
                } else {
                    tokenExpr = arena.appendExpr(.symbolRef(tokenSymbol), type: intType)
                    instructions.append(.constValue(result: tokenExpr, value: .symbolRef(tokenSymbol)))
                }
                if parameter.nullability == .nullable {
                    let flagValue = RuntimeTypeCheckToken.nullableFlag
                    let flag = arena.appendExpr(.intLiteral(flagValue), type: intType)
                    instructions.append(.constValue(result: flag, value: .intLiteral(flagValue)))
                    let adjustedToken = arena.appendTemporary(type: intType)
                    instructions.append(.call(symbol: nil, callee: interner.intern("kk_bitwise_or"),
                                              arguments: [tokenExpr, flag], result: adjustedToken,
                                              canThrow: false, thrownResult: nil))
                    arguments.append(adjustedToken)
                } else {
                    arguments.append(tokenExpr)
                }
                if carriesComponent {
                    let component = runtimeArrayComponentTypeExpr(
                        for: componentType, context: driver.ctx, sema: sema, arena: arena,
                        interner: interner, instructions: &instructions
                    )
                    arguments.append(component)
                }
                continue
            }
            let encodedToken = RuntimeTypeCheckToken.encode(type: tokenType, sema: sema, interner: interner)
            let tokenExpr = arena.appendExpr(
                .intLiteral(encodedToken),
                type: intType
            )
            instructions.append(.constValue(result: tokenExpr, value: .intLiteral(encodedToken)))
            arguments.append(tokenExpr)
            if carriesComponent {
                let component = runtimeArrayComponentTypeExpr(
                    for: componentType, context: driver.ctx, sema: sema, arena: arena,
                    interner: interner, instructions: &instructions
                )
                arguments.append(component)
            }
        }
    }

    func appendDefaultMaskArgument(
        _ defaultMask: Int64,
        sema: SemaModule,
        arena: KIRArena,
        instructions: inout [KIRInstruction],
        arguments: inout [KIRExprID]
    ) {
        let intType = sema.types.make(.primitive(.int, .nonNull))
        let maskExpr = arena.appendExpr(.intLiteral(Int64(defaultMask)), type: intType)
        instructions.append(.constValue(result: maskExpr, value: .intLiteral(Int64(defaultMask))))
        arguments.append(maskExpr)
    }

    func normalizedCallableValueArguments(
        providedArguments: [KIRExprID],
        callableValueCallBinding: CallableValueCallBinding?,
        sema: SemaModule
    ) -> [KIRExprID] {
        guard let callableValueCallBinding,
              case let .functionType(functionType) = sema.types.kind(of: callableValueCallBinding.functionType)
        else {
            return providedArguments
        }

        let parameterCount = functionType.params.count
        guard parameterCount == providedArguments.count,
              !callableValueCallBinding.parameterMapping.isEmpty
        else {
            return providedArguments
        }

        var reordered = Array(repeating: KIRExprID.invalid, count: parameterCount)
        for (argIndex, paramIndex) in callableValueCallBinding.parameterMapping {
            guard argIndex >= 0,
                  argIndex < providedArguments.count,
                  paramIndex >= 0,
                  paramIndex < parameterCount,
                  reordered[paramIndex] == .invalid
            else {
                return providedArguments
            }
            reordered[paramIndex] = providedArguments[argIndex]
        }

        guard !reordered.contains(.invalid) else {
            return providedArguments
        }
        return reordered
    }

    func recoverMemberCallBinding(
        exprID: ExprID,
        receiverExpr: ExprID,
        calleeName: InternedString,
        argumentExprs: [ExprID],
        sema: SemaModule
    ) -> CallBinding? {
        let existingBinding = sema.bindings.callBindings[exprID]
        if let existing = existingBinding,
           existing.chosenCallee != .invalid,
           sema.symbols.symbol(existing.chosenCallee) != nil
        {
            return existing
        }
        if case let .symbol(symbol)? = sema.bindings.callableTarget(for: exprID),
           symbol != .invalid,
           let signature = sema.symbols.functionSignature(for: symbol),
           signature.receiverType != nil
        {
            let parameterMapping = normalizedParameterMapping(
                existingBinding?.parameterMapping,
                argumentCount: argumentExprs.count
            )
            return CallBinding(
                chosenCallee: symbol,
                substitutedTypeArguments: [],
                parameterMapping: parameterMapping
            )
        }

        guard let receiverType = sema.bindings.exprTypes[receiverExpr] else {
            return nil
        }
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        guard let classType = resolveClassType(nonNullReceiverType, sema: sema) else {
            return nil
        }
        var ownerQueue: [SymbolID] = [classType.classSymbol]
        var visitedOwners: Set<SymbolID> = []
        var candidates: [SymbolID] = []
        while let owner = ownerQueue.first {
            ownerQueue.removeFirst()
            guard visitedOwners.insert(owner).inserted,
                  let ownerSymbol = sema.symbols.symbol(owner)
            else {
                continue
            }
            let memberFQName = ownerSymbol.fqName + [calleeName]
            for candidate in sema.symbols.lookupAll(fqName: memberFQName) {
                // The fqName lookup already scopes candidates to this owner;
                // comparing parentSymbol IDs is wrong when the same nominal
                // owner exists twice (e.g. a stdlib artifact import beside a
                // bundled declaration gives members a different SymbolID
                // under the identical fqName).
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function
                else {
                    continue
                }
                candidates.append(candidate)
            }
            ownerQueue.append(contentsOf: sema.symbols.directSupertypes(for: owner))
        }
        if receiverType != nonNullReceiverType {
            candidates.append(contentsOf: extensionCandidates(
                named: calleeName,
                nonNullReceiverType: nonNullReceiverType,
                argumentCount: argumentExprs.count,
                sema: sema
            ))
        }
        // Duplicate registrations (bundled source decl beside an artifact
        // import) share the fqName; prefer the imported symbol — its link
        // name is the one the artifact actually exports, while a bundled
        // decl's `kk_fn_*` symbol exists only in source-injection mode.
        candidates.sort { lhs, rhs in
            let lhsImported = sema.symbols.symbol(lhs)?.declSite == nil
            let rhsImported = sema.symbols.symbol(rhs)?.declSite == nil
            if lhsImported != rhsImported {
                return lhsImported
            }
            return lhs.rawValue < rhs.rawValue
        }
        guard !candidates.isEmpty else {
            return nil
        }

        let argumentTypes = argumentExprs.map { exprID in
            sema.bindings.exprTypes[exprID] ?? sema.types.anyType
        }

        let matched = candidates.first { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == argumentTypes.count
            else {
                return false
            }
            // Member signatures are declared against the owner's nominal type
            // parameters (`MutableList<E>.add(element: E)`); check argument
            // compatibility after substituting the receiver's type arguments
            // so `MutableList<Any>.add` accepts a concrete enum/class element
            // instead of leaving the call unbound.
            let candidateOwner = sema.symbols.parentSymbol(for: candidate)
            return zip(argumentTypes, signature.parameterTypes).allSatisfy { argumentType, parameterType in
                let effectiveParameterType = candidateOwner.map {
                    sema.types.substituteNominalTypeParameters(
                        in: parameterType, owner: $0, ownerArgs: classType.args
                    )
                } ?? parameterType
                return sema.types.isSubtype(argumentType, effectiveParameterType)
            }
        }

        guard let chosen = matched else {
            return nil
        }

        let parameterMapping = normalizedParameterMapping(
            existingBinding?.parameterMapping,
            argumentCount: argumentExprs.count
        )
        return CallBinding(
            chosenCallee: chosen,
            substitutedTypeArguments: [],
            parameterMapping: parameterMapping
        )
    }

    /// Source-level extension functions and extension-property getters declared
    /// for `nonNullReceiverType`. Sema resolves those against the narrowed
    /// receiver, but a receiver whose static type stays nullable (a mutable
    /// local keeps its declared type across a null check) leaves no call
    /// binding behind, and only the bare source name would reach codegen.
    private func extensionCandidates(
        named calleeName: InternedString,
        nonNullReceiverType: TypeID,
        argumentCount: Int,
        sema: SemaModule
    ) -> [SymbolID] {
        func receiverMatches(_ candidate: SymbolID) -> Bool {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType,
                  signature.parameterTypes.count == argumentCount
            else {
                return false
            }
            return sema.types.isSubtype(
                nonNullReceiverType,
                sema.types.makeNonNullable(declaredReceiver)
            )
        }

        return sema.symbols.lookupByShortName(calleeName).compactMap { candidate in
            guard let symbol = sema.symbols.symbol(candidate) else {
                return nil
            }
            switch symbol.kind {
            case .function:
                return receiverMatches(candidate) ? candidate : nil
            case .property:
                guard argumentCount == 0,
                      let getter = sema.symbols.extensionPropertyGetterAccessor(for: candidate),
                      receiverMatches(getter)
                else {
                    return nil
                }
                return getter
            default:
                return nil
            }
        }
    }

    private func normalizedParameterMapping(
        _ parameterMapping: [Int: Int]?,
        argumentCount: Int
    ) -> [Int: Int] {
        if let parameterMapping, !parameterMapping.isEmpty {
            return parameterMapping
        }
        var positionalMapping: [Int: Int] = [:]
        for index in 0 ..< argumentCount {
            positionalMapping[index] = index
        }
        return positionalMapping
    }
}
