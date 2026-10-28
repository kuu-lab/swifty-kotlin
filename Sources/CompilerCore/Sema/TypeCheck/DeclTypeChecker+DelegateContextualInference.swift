extension DeclTypeChecker {
    func inferProvidedMutableDelegateType(
        _ delegateType: TypeID,
        propertySymbol: SymbolID,
        valueType: TypeID,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let factory = DelegateFactoryContextCandidate(
            signature: FunctionSignature(parameterTypes: [], returnType: delegateType),
            returnType: delegateType,
            callReceiverType: nil
        )
        let providers = delegateConventionCandidateTiers(
            named: ctx.interner.intern("provideDelegate"), receiverType: delegateType,
            locals: locals, ctx: ctx
        )
        for providerTier in providers {
            var results: Set<TypeID> = []
            for provider in providerTier {
                let effectiveType = provider.signature.returnType
                let getters = delegateConventionCandidateTiers(
                    named: ctx.interner.intern("getValue"), receiverType: effectiveType,
                    locals: locals, ctx: ctx
                )
                let setters = delegateConventionCandidateTiers(
                    named: ctx.interner.intern("setValue"), receiverType: effectiveType,
                    locals: locals, ctx: ctx
                )
                for getterTier in getters {
                    for setterTier in setters {
                        for getter in getterTier {
                            for setter in setterTier {
                                guard ctx.sema.types.isSubtype(
                                    setter.signature.returnType, ctx.sema.types.unitType
                                ) else { continue }
                                if let result = inferredDelegateFactoryType(
                                    factory: factory, provideDelegate: provider, getValue: getter,
                                    setValue: setter, returnProvidedType: true, factoryArguments: [],
                                    propertySymbol: propertySymbol, valueType: valueType, ctx: ctx
                                ) {
                                    results.insert(result)
                                }
                            }
                        }
                        if !results.isEmpty { break }
                    }
                    if !results.isEmpty { break }
                }
            }
            if !results.isEmpty { return results.count == 1 ? results.first : nil }
        }
        return nil
    }

    func inferDelegateFactoryTypeFromConventionContext(
        _ delegateExpr: ExprID,
        propertySymbol: SymbolID,
        valueType: TypeID,
        isMutable: Bool,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        let callExpr: ExprID
        if case let .nullAssert(operand, _) = ctx.ast.arena.expr(delegateExpr) {
            callExpr = operand
        } else {
            callExpr = delegateExpr
        }
        let factoryName: InternedString
        let arguments: [CallArgument]
        let explicitReceiverType: TypeID?
        switch ctx.ast.arena.expr(callExpr) {
        case let .call(callee, typeArgs, args, _) where typeArgs.isEmpty:
            guard case let .nameRef(name, _) = ctx.ast.arena.expr(callee) else { return nil }
            factoryName = name
            arguments = args
            explicitReceiverType = nil
        case let .memberCall(receiver, name, typeArgs, args, _) where typeArgs.isEmpty:
            let receiverType: TypeID
            switch ctx.ast.arena.expr(receiver) {
            case let .nameRef(receiverName, _):
                guard let receiver = locals[receiverName] else { return nil }
                receiverType = receiver.0
            case .stringLiteral:
                receiverType = ctx.sema.types.stringType
            default:
                return nil
            }
            factoryName = name
            arguments = args
            explicitReceiverType = receiverType
        default:
            return nil
        }
        guard arguments.allSatisfy({ $0.label == nil && !$0.isSpread }) else { return nil }
        if explicitReceiverType != nil, let local = locals[factoryName],
           ctx.sema.symbols.symbol(local.symbol)?.kind == .function {
            return nil
        }
        if let explicitReceiverType,
           !driver.helpers.collectMemberFunctionCandidates(
               named: factoryName,
               receiverType: explicitReceiverType,
               sema: ctx.sema,
               interner: ctx.interner
           ).isEmpty
        {
            // Do not infer from an extension while a member may take priority.
            return nil
        }

        let factoryTiers = delegateContextFactoryCandidateTiers(
            named: factoryName,
            receiverType: ctx.implicitReceiverType,
            explicitReceiverType: explicitReceiverType,
            argumentCount: arguments.count,
            locals: locals,
            ctx: ctx
        )
        guard !factoryTiers.isEmpty else { return nil }
        // Argument applicability is checked by ordinary call resolution. Avoid
        // choosing a contextual type from an overload before that check.
        if !arguments.isEmpty, factoryTiers.reduce(0, { $0 + $1.count }) != 1 {
            return nil
        }

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
                                if let inferred = inferredDelegateFactoryTypeWithSetter(
                                    factory: factory,
                                    provideDelegate: provideDelegate,
                                    getValue: getValue,
                                    factoryArguments: arguments,
                                    propertySymbol: propertySymbol,
                                    valueType: valueType,
                                    isMutable: isMutable, ctx: ctx, locals: locals
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
                            if let inferred = inferredDelegateFactoryTypeWithSetter(
                                factory: factory,
                                provideDelegate: nil,
                                getValue: getValue,
                                factoryArguments: arguments,
                                propertySymbol: propertySymbol,
                                valueType: valueType,
                                isMutable: isMutable, ctx: ctx, locals: locals
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

    private func inferredDelegateFactoryTypeWithSetter(
        factory: DelegateFactoryContextCandidate,
        provideDelegate: DelegateConventionContextCandidate?,
        getValue: DelegateConventionContextCandidate,
        factoryArguments: [CallArgument],
        propertySymbol: SymbolID,
        valueType: TypeID,
        isMutable: Bool,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID? {
        if isMutable {
            let effectiveType = provideDelegate?.signature.returnType ?? factory.returnType
            let tiers = delegateConventionCandidateTiers(
                named: ctx.interner.intern("setValue"), receiverType: effectiveType,
                locals: locals, ctx: ctx
            )
            for tier in tiers {
                var results: Set<TypeID> = []
                for setter in tier {
                    guard ctx.sema.types.isSubtype(
                        setter.signature.returnType, ctx.sema.types.unitType
                    ) else { continue }
                    if let result = inferredDelegateFactoryType(
                        factory: factory, provideDelegate: provideDelegate, getValue: getValue,
                        setValue: setter, factoryArguments: factoryArguments,
                        propertySymbol: propertySymbol, valueType: valueType, ctx: ctx
                    ) { results.insert(result) }
                }
                if !results.isEmpty { return results.count == 1 ? results.first : nil }
            }
        }
        return inferredDelegateFactoryType(
            factory: factory, provideDelegate: provideDelegate, getValue: getValue,
            factoryArguments: factoryArguments, propertySymbol: propertySymbol,
            valueType: valueType, ctx: ctx
        )
    }

    private func inferredDelegateFactoryType(
        factory: DelegateFactoryContextCandidate,
        provideDelegate: DelegateConventionContextCandidate?,
        getValue: DelegateConventionContextCandidate,
        setValue: DelegateConventionContextCandidate? = nil,
        returnProvidedType: Bool = false,
        factoryArguments: [CallArgument],
        propertySymbol: SymbolID,
        valueType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let signatures = [factory.signature]
            + [provideDelegate?.signature]
            .compactMap { $0 }
            + [getValue.signature] + [setValue?.signature].compactMap { $0 }
        let typeParameterSymbols = Array(Set(signatures.flatMap(\.typeParameterSymbols)))
            .sorted { $0.rawValue < $1.rawValue }
        let typeVarBySymbol = Dictionary(uniqueKeysWithValues: typeParameterSymbols.enumerated().map {
            ($0.element, TypeVarID(rawValue: Int32($0.offset)))
        })
        var constraints: [VariableConstraint] = []

        func addSubtype(_ subtype: TypeID, _ supertype: TypeID) {
            var subtype = subtype
            var supertype = supertype
            if case let .typeParam(parameter) = sema.types.kind(of: subtype),
               parameter.nullability == .nullable,
               sema.types.nullability(of: supertype) == .nullable,
               sema.symbols.typeParameterUpperBounds(for: parameter.symbol).contains(where: {
                   sema.types.isSubtype($0, sema.types.anyType)
               })
            {
                subtype = sema.types.makeNonNullable(subtype)
                supertype = sema.types.makeNonNullable(supertype)
            }
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

        guard factoryArguments.count <= factory.signature.parameterTypes.count else {
            return nil
        }
        // Arguments that constrain factory type parameters must participate in
        // inference; do not derive a partial expected type without them.
        for (argument, parameterType) in zip(factoryArguments, factory.signature.parameterTypes) {
            if factory.signature.typeParameterSymbols.contains(where: {
                sema.types.typeContainsTypeParam(parameterType, symbol: $0)
            }) {
                guard case let .call(callee, typeArgs, args, _) = ctx.ast.arena.expr(argument.expr),
                      typeArgs.isEmpty, args.isEmpty,
                      case let .nameRef(name, _) = ctx.ast.arena.expr(callee),
                      !ctx.scope.lookup(name, matching: { sema.symbols.symbol($0)?.kind == .class }).isEmpty
                else { return nil }
            }
        }
        for index in factoryArguments.count ..< factory.signature.parameterTypes.count {
            let hasDefault = factory.signature.valueParameterHasDefaultValues.indices.contains(index)
                && factory.signature.valueParameterHasDefaultValues[index]
            let isVararg = factory.signature.valueParameterIsVararg.indices.contains(index)
                && factory.signature.valueParameterIsVararg[index]
            guard hasDefault || isVararg else { return nil }
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
            if !provideDelegate.receiverWasSpecialized {
                addSubtype(factory.returnType, provideDelegate.receiverType)
            }
            if !getValue.receiverWasSpecialized {
                addSubtype(provideDelegate.signature.returnType, getValue.receiverType)
            }
        } else {
            if !getValue.receiverWasSpecialized {
                addSubtype(factory.returnType, getValue.receiverType)
            }
        }

        if let actualReceiver = factory.callReceiverType,
           let declaredReceiver = factory.signature.receiverType
        {
            addSubtype(actualReceiver, declaredReceiver)
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
        if let setValue {
            let effectiveType = provideDelegate?.signature.returnType ?? factory.returnType
            if !setValue.receiverWasSpecialized {
                addSubtype(effectiveType, setValue.receiverType)
            }
            guard addArgumentConstraints(
                signature: setValue.signature,
                argumentTypes: propertyDelegateAccessorArgumentTypes(
                    for: propertySymbol, valueType: valueType, ctx: ctx
                )
            ) else { return nil }
        }
        addSubtype(getValue.signature.returnType, valueType)

        let variables = typeVarBySymbol.values.sorted { $0.rawValue < $1.rawValue }
        let solution = ConstraintSolver().solve(
            vars: variables,
            constraints: constraints,
            typeSystem: sema.types
        )
        guard solution.isSuccess else { return nil }
        let resultParameters = factory.signature.typeParameterSymbols
            + (returnProvidedType ? (provideDelegate?.signature.typeParameterSymbols ?? []) : [])
        for symbol in resultParameters {
            guard let variable = typeVarBySymbol[symbol],
                  let inferred = solution.substitution[variable],
                  inferred != sema.types.errorType,
                  !sema.types.typeContainsTypeParam(inferred, symbol: symbol)
            else {
                return nil
            }
        }
        let result = sema.types.substituteTypeParameters(
            in: returnProvidedType ? (provideDelegate?.signature.returnType ?? factory.returnType) : factory.returnType,
            substitution: solution.substitution,
            typeVarBySymbol: typeVarBySymbol
        )
        guard case .classType = sema.types.kind(of: result) else { return nil }
        return result
    }

    private func delegateContextFactoryCandidateTiers(
        named name: InternedString,
        receiverType: TypeID?,
        explicitReceiverType: TypeID?,
        argumentCount: Int,
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

        if explicitReceiverType == nil, let local = locals[name],
           sema.symbols.symbol(local.symbol)?.kind == .function,
           sema.symbols.functionSignature(for: local.symbol)?.receiverType == nil
        {
            appendVisibleTier([local.symbol])
        }
        if explicitReceiverType == nil, let receiverType {
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
        for receiver in explicitReceiverType == nil ? ctx.implicitReceiverMemberLookupEntries() : [] {
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
            guard let kind = sema.symbols.symbol(symbol)?.kind,
                  let signature = sema.symbols.functionSignature(for: symbol)
            else {
                return false
            }
            if explicitReceiverType != nil {
                return kind == .function && signature.receiverType != nil
                    && sema.symbols.memberExtensionOwnerSymbol(for: symbol) == nil
            }
            return kind == .constructor || (kind == .function && (
                signature.receiverType == nil || (receiverType != nil
                    && sema.symbols.memberExtensionOwnerSymbol(for: symbol) == nil)
            ))
        })
        appendVisibleTier(scopeFound)

        let classifiers = explicitReceiverType == nil ? ctx.scope.lookup(name, matching: { symbol in
            sema.symbols.symbol(symbol)?.kind == .class
        }) : []
        let constructors = classifiers.flatMap { classifier -> [SymbolID] in
            guard let declaration = sema.symbols.symbol(classifier) else { return [] }
            return sema.symbols.lookupAll(fqName: declaration.fqName + [ctx.interner.intern("<init>")])
                .filter { sema.symbols.parentSymbol(for: $0) == classifier }
        }
        appendVisibleTier(constructors)

        return symbolTiers.compactMap { symbols in
            driver.inferFunctionReturnTypesIfNeeded(for: symbols.filter { symbol in
                guard sema.symbols.symbol(symbol)?.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbol),
                      argumentCount <= signature.parameterTypes.count
                else { return false }
                return (argumentCount ..< signature.parameterTypes.count).allSatisfy { index in
                    (signature.valueParameterHasDefaultValues.indices.contains(index)
                        && signature.valueParameterHasDefaultValues[index])
                        || (signature.valueParameterIsVararg.indices.contains(index)
                            && signature.valueParameterIsVararg[index])
                }
            })
            let factories = symbols.compactMap { symbol -> DelegateFactoryContextCandidate? in
                guard let signature = sema.symbols.functionSignature(for: symbol),
                      case let .classType(returnType) = sema.types.kind(of: signature.returnType)
                else {
                    return nil
                }
                let callReceiverType = explicitReceiverType ?? (
                    scopeFound.contains(symbol) && sema.symbols.symbol(symbol)?.kind == .function
                        && signature.receiverType != nil ? receiverType : nil
                )
                if let callReceiverType {
                    guard let declaredReceiver = signature.receiverType,
                          delegateContextReceiverProjection(
                              actual: callReceiverType, declared: declaredReceiver, sema: sema
                          ) != nil
                    else { return nil }
                }
                return DelegateFactoryContextCandidate(
                    signature: signature,
                    returnType: sema.types.make(.classType(returnType)),
                    callReceiverType: callReceiverType
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
                      let projection = delegateContextReceiverProjection(
                          actual: receiverType,
                          declared: declaredReceiver,
                          sema: sema
                      )
                else {
                    return nil
                }
                if signature.classTypeParameterCount > 0,
                   let owner = sema.symbols.parentSymbol(for: symbol),
                   case let .classType(declared) = sema.types.kind(of: declaredReceiver),
                   owner == declared.classSymbol,
                   case let .classType(projected) = sema.types.kind(of: projection),
                   projected.args.count == signature.classTypeParameterCount,
                   projected.args.allSatisfy({ if case .invariant = $0 { true } else { false } })
                {
                    let parameters = Array(signature.typeParameterSymbols.prefix(signature.classTypeParameterCount))
                    var substitutions: [TypeVarID: TypeID] = [:]
                    var variables: [SymbolID: TypeVarID] = [:]
                    for (index, pair) in zip(parameters, projected.args).enumerated() {
                        guard case let .invariant(type) = pair.1 else { return nil }
                        let variable = TypeVarID(rawValue: Int32(index))
                        variables[pair.0] = variable
                        substitutions[variable] = type
                    }
                    func substitute(_ type: TypeID) -> TypeID {
                        sema.types.substituteTypeParameters(
                            in: type, substitution: substitutions, typeVarBySymbol: variables
                        )
                    }
                    let specialized = FunctionSignature(
                        receiverType: signature.receiverType.map(substitute),
                        parameterTypes: signature.parameterTypes.map(substitute),
                        returnType: substitute(signature.returnType),
                        valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
                        valueParameterIsVararg: signature.valueParameterIsVararg,
                        hasStableParameterNames: signature.hasStableParameterNames,
                        typeParameterSymbols: Array(signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount))
                    )
                    return DelegateConventionContextCandidate(
                        signature: specialized, receiverType: projection, receiverWasSpecialized: true
                    )
                }
                return DelegateConventionContextCandidate(
                    signature: signature,
                    receiverType: declaredReceiver,
                    receiverWasSpecialized: false
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
    let callReceiverType: TypeID?
}

private struct DelegateConventionContextCandidate {
    let signature: FunctionSignature
    let receiverType: TypeID
    let receiverWasSpecialized: Bool
}
