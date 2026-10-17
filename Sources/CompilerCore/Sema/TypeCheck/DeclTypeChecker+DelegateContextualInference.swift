extension DeclTypeChecker {
    func inferDelegateFactoryTypeFromConventionContext(
        _ delegateExpr: ExprID,
        propertySymbol: SymbolID,
        valueType: TypeID,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        guard case let .call(callee, typeArgs, arguments, _) = ctx.ast.arena.expr(delegateExpr),
              typeArgs.isEmpty,
              arguments.isEmpty,
              case let .nameRef(factoryName, _) = ctx.ast.arena.expr(callee)
        else {
            return nil
        }

        let factoryTiers = delegateContextFactoryCandidateTiers(
            named: factoryName,
            receiverType: ctx.implicitReceiverType,
            locals: locals,
            ctx: ctx
        )
        guard !factoryTiers.isEmpty else { return nil }

        var inferredTypes: Set<TypeID> = []
        for factoryTier in factoryTiers {
            var tierInferredTypes: Set<TypeID> = []
            for factory in factoryTier {
                guard delegateContextClassSymbol(of: factory.returnType, sema: ctx.sema) != nil else {
                    continue
                }

                let provideDelegateTiers = delegateConventionCandidateTiers(
                    named: ctx.interner.intern("provideDelegate"),
                    receiverType: factory.returnType,
                    locals: locals,
                    ctx: ctx
                )
                var factoryInferredTypes: Set<TypeID> = []
                for provideDelegateTier in provideDelegateTiers {
                    var tierInferredTypes: Set<TypeID> = []
                    for provideDelegate in provideDelegateTier {
                        let getValueTiers = delegateConventionCandidateTiers(
                            named: ctx.interner.intern("getValue"),
                            receiverType: provideDelegate.signature.returnType,
                            locals: locals,
                            ctx: ctx
                        )
                        for getValueTier in getValueTiers {
                            var providerInferredTypes: Set<TypeID> = []
                            for getValue in getValueTier {
                                if let inferred = inferredDelegateFactoryType(
                                    factory: factory,
                                    provideDelegate: provideDelegate,
                                    getValue: getValue,
                                    propertySymbol: propertySymbol,
                                    valueType: valueType,
                                    ctx: ctx
                                ) {
                                    providerInferredTypes.insert(inferred)
                                }
                            }
                            if !providerInferredTypes.isEmpty {
                                tierInferredTypes.formUnion(providerInferredTypes)
                                break
                            }
                        }
                    }
                    if !tierInferredTypes.isEmpty {
                        factoryInferredTypes.formUnion(tierInferredTypes)
                        break
                    }
                }

                // A delegate without provideDelegate uses getValue directly on the
                // factory result. Fall back when no complete provider/getter tier
                // supplies a usable context.
                if factoryInferredTypes.isEmpty {
                    let getValueTiers = delegateConventionCandidateTiers(
                        named: ctx.interner.intern("getValue"),
                        receiverType: factory.returnType,
                        locals: locals,
                        ctx: ctx
                    )
                    for getValueTier in getValueTiers {
                        var tierInferredTypes: Set<TypeID> = []
                        for getValue in getValueTier {
                            if let inferred = inferredDelegateFactoryType(
                                factory: factory,
                                provideDelegate: nil,
                                getValue: getValue,
                                propertySymbol: propertySymbol,
                                valueType: valueType,
                                ctx: ctx
                            ) {
                                tierInferredTypes.insert(inferred)
                            }
                        }
                        if !tierInferredTypes.isEmpty {
                            factoryInferredTypes.formUnion(tierInferredTypes)
                            break
                        }
                    }
                }
                tierInferredTypes.formUnion(factoryInferredTypes)
            }
            if !tierInferredTypes.isEmpty {
                inferredTypes.formUnion(tierInferredTypes)
                break
            }
        }

        guard inferredTypes.count == 1 else { return nil }
        return inferredTypes.first
    }

    private func inferredDelegateFactoryType(
        factory: DelegateFactoryContextCandidate,
        provideDelegate: DelegateConventionContextCandidate?,
        getValue: DelegateConventionContextCandidate,
        propertySymbol: SymbolID,
        valueType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let signatures = [factory.signature]
            + [provideDelegate?.signature]
            .compactMap { $0 }
            + [getValue.signature]
        let typeParameterSymbols = Array(Set(signatures.flatMap(\.typeParameterSymbols)))
            .sorted { $0.rawValue < $1.rawValue }
        let typeVarBySymbol = Dictionary(uniqueKeysWithValues: typeParameterSymbols.enumerated().map {
            ($0.element, TypeVarID(rawValue: Int32($0.offset)))
        })
        var constraints: [VariableConstraint] = []

        func addSubtype(_ subtype: TypeID, _ supertype: TypeID) {
            constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                subtype: subtype,
                supertype: supertype,
                typeVarBySymbol: typeVarBySymbol,
                typeSystem: sema.types,
                blameRange: nil
            ))
        }

        func addArgumentConstraints(
            signature: FunctionSignature,
            argumentTypes: [TypeID]
        ) -> Bool {
            guard argumentTypes.count <= signature.parameterTypes.count else { return false }
            for index in argumentTypes.indices {
                constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: argumentTypes[index],
                    supertype: signature.parameterTypes[index],
                    typeVarBySymbol: typeVarBySymbol,
                    typeSystem: sema.types,
                    blameRange: nil
                ))
            }
            for index in argumentTypes.count ..< signature.parameterTypes.count {
                let hasDefault = signature.valueParameterHasDefaultValues.indices.contains(index)
                    && signature.valueParameterHasDefaultValues[index]
                let isVararg = signature.valueParameterIsVararg.indices.contains(index)
                    && signature.valueParameterIsVararg[index]
                guard hasDefault || isVararg else { return false }
            }
            return true
        }

        guard addArgumentConstraints(signature: factory.signature, argumentTypes: []) else {
            return nil
        }

        if let provideDelegate {
            guard addArgumentConstraints(
                      signature: provideDelegate.signature,
                      argumentTypes: Array(propertyDelegateProvideDelegateArgumentTypes(
                          for: propertySymbol,
                          ctx: ctx
                      ).prefix(2))
                  )
            else {
                return nil
            }
            addSubtype(factory.returnType, provideDelegate.receiverType)
            addSubtype(provideDelegate.signature.returnType, getValue.receiverType)
        } else {
            addSubtype(factory.returnType, getValue.receiverType)
        }

        guard addArgumentConstraints(
            signature: getValue.signature,
            argumentTypes: Array(propertyDelegateAccessorArgumentTypes(
                for: propertySymbol,
                valueType: nil,
                ctx: ctx
            ).prefix(2))
        ) else {
            return nil
        }
        constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
            subtype: getValue.signature.returnType,
            supertype: valueType,
            typeVarBySymbol: typeVarBySymbol,
            typeSystem: sema.types,
            blameRange: nil
        ))

        let variables = typeVarBySymbol.values.sorted { $0.rawValue < $1.rawValue }
        let solution = ConstraintSolver().solve(
            vars: variables,
            constraints: constraints,
            typeSystem: sema.types
        )
        guard solution.isSuccess else { return nil }
        for symbol in factory.signature.typeParameterSymbols {
            guard let variable = typeVarBySymbol[symbol],
                  let inferred = solution.substitution[variable],
                  !sema.types.typeContainsTypeParam(inferred, symbol: symbol)
            else {
                return nil
            }
        }
        let result = sema.types.substituteTypeParameters(
            in: factory.returnType,
            substitution: solution.substitution,
            typeVarBySymbol: typeVarBySymbol
        )
        guard case .classType = sema.types.kind(of: result) else { return nil }
        return result
    }

    private func delegateContextFactoryCandidateTiers(
        named name: InternedString,
        receiverType: TypeID?,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> [[DelegateFactoryContextCandidate]] {
        let sema = ctx.sema
        var symbolTiers: [[SymbolID]] = []
        var seen: Set<SymbolID> = []

        func appendVisibleTier(_ candidates: [SymbolID]) {
            let visible = ctx.filterByVisibility(candidates).visible.filter {
                seen.insert($0).inserted
            }
            if !visible.isEmpty {
                symbolTiers.append(visible)
            }
        }

        if let local = locals[name],
           sema.symbols.symbol(local.symbol)?.kind == .function,
           sema.symbols.functionSignature(for: local.symbol)?.receiverType == nil
        {
            appendVisibleTier([local.symbol])
        }
        if let receiverType {
            let found = driver.helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            )
            appendVisibleTier(found.filter {
                sema.symbols.symbol($0)?.kind == .function
                    && sema.symbols.memberExtensionOwnerSymbol(for: $0) == nil
            })
        }
        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            let found = driver.helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: receiver.type,
                sema: sema,
                interner: ctx.interner
            )
            appendVisibleTier(found.filter {
                sema.symbols.symbol($0)?.kind == .function
                    && sema.symbols.memberExtensionOwnerSymbol(for: $0) == nil
            })
        }

        let scopeFound = ctx.scope.lookup(name, matching: { symbol in
            guard sema.symbols.symbol(symbol)?.kind == .function,
                  let signature = sema.symbols.functionSignature(for: symbol)
            else {
                return false
            }
            return signature.receiverType == nil
        })
        appendVisibleTier(scopeFound)

        return symbolTiers.compactMap { symbols in
            let factories = symbols.compactMap { symbol -> DelegateFactoryContextCandidate? in
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      case let .classType(returnType) = sema.types.kind(of: signature.returnType)
                else {
                    return nil
                }
                return DelegateFactoryContextCandidate(
                    signature: signature,
                    returnType: sema.types.make(.classType(returnType))
                )
            }
            return factories.isEmpty ? nil : factories
        }
    }

    private func delegateConventionCandidateTiers(
        named name: InternedString,
        receiverType: TypeID,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> [[DelegateConventionContextCandidate]] {
        let sema = ctx.sema
        var symbolTiers: [[SymbolID]] = []
        var seen: Set<SymbolID> = []

        func appendVisibleTier(_ candidates: [SymbolID]) {
            let visible = ctx.filterByVisibility(candidates).visible.filter {
                seen.insert($0).inserted
            }
            if !visible.isEmpty {
                symbolTiers.append(visible)
            }
        }

        func isOperator(_ symbol: SymbolID) -> Bool {
            sema.symbols.symbol(symbol)?.flags.contains(.operatorFunction) == true
        }

        appendVisibleTier(driver.helpers.collectMemberFunctionCandidates(
            named: name,
            receiverType: receiverType,
            sema: sema,
            interner: ctx.interner
        ).filter(isOperator))

        if let local = locals[name],
           isOperator(local.symbol),
           sema.symbols.functionSignature(for: local.symbol)?.receiverType != nil
        {
            appendVisibleTier([local.symbol])
        }

        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            let memberExtensions = driver.helpers.collectMemberFunctionCandidates(
                named: name,
                receiverType: receiver.type,
                sema: sema,
                interner: ctx.interner
            ).filter {
                isOperator($0) && sema.symbols.memberExtensionOwnerSymbol(for: $0) != nil
            }
            appendVisibleTier(memberExtensions)
        }

        appendVisibleTier(ctx.scope.lookup(name, matching: { symbol in
            guard let declaration = sema.symbols.symbol(symbol),
                  let signature = sema.symbols.functionSignature(for: symbol)
            else {
                return false
            }
            return declaration.kind == .function
                && declaration.flags.contains(.operatorFunction)
                && sema.symbols.memberExtensionOwnerSymbol(for: symbol) == nil
                && signature.receiverType != nil
        }))

        var bundledCandidates = driver.callChecker.collectBundledStdlibExtensionCandidates(
            named: name,
            receiverType: receiverType,
            requireOperator: true,
            sourceFile: ctx.currentASTFile,
            sema: sema,
            interner: ctx.interner
        ) + bundledMapDelegateCandidates(named: name, sema: sema, interner: ctx.interner)
        if name == ctx.interner.intern("getValue"),
           isMutableMapDelegateType(receiverType, sema: sema, interner: ctx.interner)
        {
            let mutableMapName = [
                ctx.interner.intern("kotlin"),
                ctx.interner.intern("collections"),
                ctx.interner.intern("MutableMap"),
            ]
            let mutableMapCandidates = bundledCandidates.filter { symbol in
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      let declaredReceiver = signature.receiverType,
                      let receiverClass = delegateContextClassSymbol(of: declaredReceiver, sema: sema),
                      let receiverSymbol = sema.symbols.symbol(receiverClass)
                else {
                    return false
                }
                return receiverSymbol.fqName == mutableMapName
            }
            if !mutableMapCandidates.isEmpty {
                bundledCandidates = mutableMapCandidates
            }
        }
        bundledCandidates = bundledCandidates.filter(isOperator).filter { seen.insert($0).inserted }
        if !bundledCandidates.isEmpty {
            symbolTiers.append(bundledCandidates)
        }

        return symbolTiers.compactMap { symbols in
            let candidates = symbols.compactMap { symbol -> DelegateConventionContextCandidate? in
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      let declaredReceiver = delegateConventionReceiverType(
                          for: symbol,
                          signature: signature,
                          sema: sema
                      ),
                      delegateContextReceiverProjection(
                          actual: receiverType,
                          declared: declaredReceiver,
                          sema: sema
                      ) != nil
                else {
                    return nil
                }
                return DelegateConventionContextCandidate(
                    signature: signature,
                    receiverType: declaredReceiver
                )
            }
            return candidates.isEmpty ? nil : candidates
        }
    }

    private func delegateConventionReceiverType(
        for symbol: SymbolID,
        signature: FunctionSignature,
        sema: SemaModule
    ) -> TypeID? {
        if let receiverType = signature.receiverType {
            return receiverType
        }
        guard let owner = sema.symbols.parentSymbol(for: symbol),
              let ownerKind = sema.symbols.symbol(owner)?.kind,
              [.class, .interface, .object, .enumClass].contains(ownerKind)
        else {
            return nil
        }
        let classTypeParameterSymbols = signature.typeParameterSymbols.prefix(
            signature.classTypeParameterCount
        )
        let args = classTypeParameterSymbols.map { parameter in
            TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: parameter))))
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: owner,
            args: args,
            nullability: .nonNull
        )))
    }

    private func delegateContextClassSymbol(
        of type: TypeID,
        sema: SemaModule
    ) -> SymbolID? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)) else {
            return nil
        }
        return classType.classSymbol
    }

    private func delegateContextReceiverProjection(
        actual: TypeID,
        declared: TypeID,
        sema: SemaModule
    ) -> TypeID? {
        let actualKind = sema.types.kind(of: actual)
        let declaredKind = sema.types.kind(of: declared)
        if case let .classType(actualClass) = actualKind,
           case let .classType(declaredClass) = declaredKind
        {
            guard sema.types.nullabilitySubtype(actualClass.nullability, declaredClass.nullability),
                  sema.types.isNominalSubtypeSymbol(actualClass.classSymbol, of: declaredClass.classSymbol),
                  let args = sema.types.liftedNominalSupertypeArgs(
                      from: actualClass.classSymbol,
                      childArgs: actualClass.args,
                      to: declaredClass.classSymbol
                  ),
                  args.count == declaredClass.args.count
            else {
                return nil
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: declaredClass.classSymbol,
                args: args,
                nullability: actualClass.nullability
            )))
        }

        if case let .typeParam(parameter) = declaredKind, parameter.capture == nil {
            guard sema.types.nullabilitySubtype(
                sema.types.nullability(of: actual),
                parameter.nullability
            ) else {
                return nil
            }
            let upperBounds = sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
            guard upperBounds.allSatisfy({ sema.types.isSubtype(actual, $0) }) else {
                return nil
            }
            return actual
        }

        return sema.types.isSubtype(actual, declared) ? actual : nil
    }
}

private struct DelegateFactoryContextCandidate {
    let signature: FunctionSignature
    let returnType: TypeID
}

private struct DelegateConventionContextCandidate {
    let signature: FunctionSignature
    let receiverType: TypeID
}
