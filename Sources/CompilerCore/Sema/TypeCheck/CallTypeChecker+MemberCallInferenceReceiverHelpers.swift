
extension CallTypeChecker {

    func lookupStdlibSymbol(_ name: String, symbols: SymbolTable, interner: StringInterner) -> SymbolID? {
        // KUU-3084: a short-name lookup can select a different nominal List
        // when a compiled artifact registers same-named declarations in a
        // different order. Synthetic results must use the classifier resolved
        // by source-level kotlin.collections.List annotations.
        if name == "List" || name == "MutableList" {
            return symbols.lookupNominal(fqName: [
                interner.intern("kotlin"),
                interner.intern("collections"),
                interner.intern(name),
            ])
        }

        // KUU-3257: `kotlin.collections.List` names both the interface and the
        // `List(size, init)` factory function. `byShortName` preserves
        // registration order, and the stdlib sema snapshot registers the
        // function first — building `List<T>` on the function symbol then
        // breaks subtype checks (e.g. `sorted().joinToString` left
        // unbound). Prefer a nominal classifier like `lookupNominal` does.
        let candidates = symbols.lookupByShortName(interner.intern(name))
        return candidates.first(where: { id in
            switch symbols.symbol(id)?.kind {
            case .class, .interface, .object, .enumClass, .annotationClass:
                true
            default:
                false
            }
        }) ?? candidates.first
    }

    func preferCollectionToListCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let collectionSymbol = sema.symbols.lookup(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Collection"),
        ]),
        let iterableSymbol = sema.symbols.lookupNominal(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]),
        let receiverNominal = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(receiverType),
            types: sema.types
        ),
        sema.types.isNominalSubtypeSymbol(receiverNominal, of: collectionSymbol),
        candidates.contains(where: { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return false
            }
            return candidateNominal == collectionSymbol
        })
        else {
            return candidates
        }

        return candidates.filter { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return true
            }
            return candidateNominal != iterableSymbol
        }
    }

    func preferMostSpecificMemberReceiverCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        argumentTypes: [TypeID] = [],
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard candidates.count > 1 else { return candidates }
        let actualReceiver = sema.types.makeNonNullable(receiverType)
        let receiverTypes: [(SymbolID, TypeID)] = candidates.compactMap { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                return nil
            }
            return (candidate, sema.types.makeNonNullable(receiver))
        }
        guard receiverTypes.count == candidates.count else { return candidates }

        // Receiver specificity must not hide a viable generic extension behind
        // a more-specific receiver overload that cannot accept the arguments.
        // For example, String.contains(String) must keep the CharSequence
        // overload when the more-specific String overload is contains(Regex).
        let potentiallyApplicableCandidates: Set<SymbolID> = if argumentTypes.isEmpty {
            Set(candidates)
        } else {
            Set(candidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                guard argumentTypes.count <= signature.parameterTypes.count
                    || signature.valueParameterIsVararg.contains(true)
                else {
                    return false
                }
                let parameterCount = signature.parameterTypes.count
                func normalizedFlags(_ flags: [Bool]) -> [Bool] {
                    if flags.count == parameterCount {
                        return flags
                    }
                    if flags.count > parameterCount {
                        return Array(flags.prefix(parameterCount))
                    }
                    return flags + Array(repeating: false, count: parameterCount - flags.count)
                }
                let hasDefaultValues = normalizedFlags(signature.valueParameterHasDefaultValues)
                let isVararg = normalizedFlags(signature.valueParameterIsVararg)
                if argumentTypes.count < parameterCount {
                    let omittedParameterIndices = argumentTypes.count ..< parameterCount
                    guard omittedParameterIndices.allSatisfy({
                        hasDefaultValues[$0] || isVararg[$0]
                    }) else {
                        return false
                    }
                }
                for (index, argumentType) in argumentTypes.enumerated() {
                    let parameterIndex: Int
                    if index < signature.parameterTypes.count {
                        parameterIndex = index
                    } else if let varargIndex = isVararg.firstIndex(of: true) {
                        parameterIndex = varargIndex
                    } else {
                        return false
                    }
                    let parameterType = signature.parameterTypes[parameterIndex]
                    let actual = sema.types.makeNonNullable(argumentType)
                    let expected = sema.types.makeNonNullable(parameterType)
                    if actual == sema.types.errorType
                        || expected == sema.types.errorType
                        || actual == sema.types.anyType
                        || expected == sema.types.anyType
                    {
                        continue
                    }
                    if sema.types.typeContainsAnyTypeParam(actual)
                        || sema.types.typeContainsAnyTypeParam(expected)
                    {
                        continue
                    }
                    guard sema.types.isSubtype(actual, expected) else {
                        return false
                    }
                }
                return true
            })
        }
        let specificityCandidates = potentiallyApplicableCandidates

        let collectionFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Collection"),
        ]
        let iterableFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]
        var remainingCandidates = candidates
        let hasCollectionReceiver = receiverTypes.contains { candidate, receiver in
            guard specificityCandidates.contains(candidate) else { return false }
            return driver.helpers.nominalSymbol(of: receiver, types: sema.types)
                .flatMap { sema.symbols.symbol($0)?.fqName } == collectionFQName
        }
        if hasCollectionReceiver,
           let actualNominal = driver.helpers.nominalSymbol(of: actualReceiver, types: sema.types),
           sema.types.isNominalSubtypeSymbol(
               actualNominal,
               of: sema.symbols.lookup(fqName: collectionFQName) ?? actualNominal
           )
        {
            let filtered = remainingCandidates.filter { candidate in
                guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                      let nominal = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(nominal)
                else {
                    return true
                }
                return symbol.fqName != iterableFQName
            }
            if !filtered.isEmpty { remainingCandidates = filtered }
        }

        let actualNominal = driver.helpers.nominalSymbol(of: actualReceiver, types: sema.types)
        let lessSpecific = Set(receiverTypes.compactMap { candidate, candidateReceiver -> SymbolID? in
            guard remainingCandidates.contains(candidate), specificityCandidates.contains(candidate) else { return nil }
            let candidateNominal = driver.helpers.nominalSymbol(of: candidateReceiver, types: sema.types)
            let hasMoreSpecific = receiverTypes.contains { other, otherReceiver in
                guard remainingCandidates.contains(other), specificityCandidates.contains(other), candidate != other else { return false }
                let nominallyMoreSpecific: Bool = if let actualNominal,
                                                     let candidateNominal,
                                                     let otherNominal = driver.helpers.nominalSymbol(of: otherReceiver, types: sema.types)
                {
                    actualNominal != candidateNominal
                        && candidateNominal != otherNominal
                        && sema.types.isNominalSubtypeSymbol(actualNominal, of: otherNominal)
                        && sema.types.isNominalSubtypeSymbol(otherNominal, of: candidateNominal)
                } else {
                    false
                }
                let receiverMoreSpecific: Bool = if nominallyMoreSpecific {
                    true
                } else if sema.types.isSubtype(actualReceiver, otherReceiver),
                          sema.types.isSubtype(otherReceiver, candidateReceiver)
                {
                    !sema.types.isSubtype(candidateReceiver, otherReceiver)
                } else {
                    false
                }
                guard receiverMoreSpecific else { return false }

                // Receiver specificity must not hide an overload whose parameters
                // are strictly more specific for the call than the competing overload.
                // For example, RawSink.write(Buffer, Long) must not be suppressed
                // by Sink.write(RawSource, Long) when called on a Sink receiver with a Buffer argument.
                if let candSig = sema.symbols.functionSignature(for: candidate),
                   let otherSig = sema.symbols.functionSignature(for: other)
                {
                    let count = min(candSig.parameterTypes.count, otherSig.parameterTypes.count)
                    var candidateHasMoreSpecificParam = false
                    for i in 0..<count {
                        let candParam = sema.types.makeNonNullable(candSig.parameterTypes[i])
                        let otherParam = sema.types.makeNonNullable(otherSig.parameterTypes[i])
                        if candParam == otherParam { continue }
                        if sema.types.typeContainsAnyTypeParam(candParam) || sema.types.typeContainsAnyTypeParam(otherParam) {
                            continue
                        }
                        if sema.types.isSubtype(candParam, otherParam) && !sema.types.isSubtype(otherParam, candParam) {
                            candidateHasMoreSpecificParam = true
                            break
                        }
                    }
                    if candidateHasMoreSpecificParam {
                        return false
                    }
                }
                return true
            }
            return hasMoreSpecific ? candidate : nil
        })
        let filtered = remainingCandidates.filter { !lessSpecific.contains($0) }
        return filtered.isEmpty ? candidates : filtered
    }

    func preferListUnzipCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        guard let listSymbol = sema.symbols.lookupNominal(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]),
        let iterableSymbol = sema.symbols.lookupNominal(fqName: [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterable"),
        ]),
        let receiverNominal = driver.helpers.nominalSymbol(
            of: sema.types.makeNonNullable(receiverType),
            types: sema.types
        ),
        sema.types.isNominalSubtypeSymbol(receiverNominal, of: listSymbol),
        candidates.contains(where: { candidate in
            guard sema.symbols.isSourceBackedSymbol(candidate),
                  let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return false
            }
            return candidateNominal == listSymbol
        })
        else {
            return candidates
        }

        return candidates.filter { candidate in
            guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return true
            }
            return candidateNominal != iterableSymbol
        }
    }

    func preferListTakeCandidates(
        _ candidates: [SymbolID],
        receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        let listFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("List"),
        ]
        guard let listSymbol = sema.symbols.lookupNominal(fqName: listFQName),
              let receiverNominal = driver.helpers.nominalSymbol(
                  of: sema.types.makeNonNullable(receiverType),
                  types: sema.types
              ),
              sema.types.isNominalSubtypeSymbol(receiverNominal, of: listSymbol)
        else {
            return candidates
        }

        let listTakeCandidates = candidates.filter { candidate in
            guard sema.symbols.isSourceBackedSymbol(candidate),
                  let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                  let candidateNominal = driver.helpers.nominalSymbol(
                      of: sema.types.makeNonNullable(receiver),
                      types: sema.types
                  )
            else {
                return false
            }
            return candidateNominal == listSymbol
        }
        return listTakeCandidates.isEmpty ? candidates : listTakeCandidates
    }

    func collectDispatchReceiverMemberExtensionCandidates(
        named calleeName: InternedString,
        extensionReceiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let receivers = ctx.implicitReceiverMemberLookupEntries().map(\.type)
        for receiver in receivers {
            var deferredConstraintsByCandidate: [SymbolID: [VariableConstraint]] = [:]
            let candidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: receiver,
                sema: sema,
                interner: ctx.interner
            ).filter { candidateID in
                guard let symbol = ctx.cachedSymbol(candidateID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: candidateID),
                      let declaredReceiver = signature.receiverType
                else { return false }
                let strictMatch = extensionReceiverMatchesDuringBuilderInference(
                    callSiteReceiver: extensionReceiverType,
                    declaredReceiver: declaredReceiver,
                    ctx: ctx
                )
                if let constraints = deferredMemberExtensionReceiverConstraints(
                    callSiteReceiver: extensionReceiverType,
                    declaredReceiver: declaredReceiver,
                    signature: signature,
                    candidate: candidateID,
                    ctx: ctx
                ) {
                    deferredConstraintsByCandidate[candidateID] = constraints
                    return true
                }
                return strictMatch
            }
            if !candidates.isEmpty {
                if candidates.count == 1,
                   let candidate = candidates.first,
                   let constraints = deferredConstraintsByCandidate[candidate]
                {
                    ctx.builderInference?.constraints.append(contentsOf: constraints)
                }
                return candidates
            }
        }
        return []
    }

    func extensionSyntheticFallbackReceiverMatches(
        callSiteReceiver: TypeID,
        declaredReceiver: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard implicitReceiverEntryNullabilityCompatible(
            callSiteReceiver: callSiteReceiver,
            declaredReceiver: declaredReceiver,
            sema: sema
        ) else {
            return false
        }
        let actual = sema.types.makeNonNullable(callSiteReceiver)
        let declared = sema.types.makeNonNullable(declaredReceiver)
        if sema.types.isSubtype(actual, declared) {
            return true
        }
        if case let .intersection(parts) = sema.types.kind(of: actual),
           !sema.types.canHoldNull(callSiteReceiver),
           parts.contains(where: { part in
               guard case let .typeParam(typeParam) = sema.types.kind(of: part) else {
                   return false
               }
               return typeParameterHasNonNullUpperBoundMatchingReceiver(
                   typeParam.symbol,
                   declaredReceiver: declaredReceiver,
                   declaredNonNull: declared,
                   sema: sema
               )
           })
        {
            return true
        }
        if case let .intersection(parts) = sema.types.kind(of: actual),
           parts.contains(where: {
               extensionSyntheticFallbackReceiverMatches(
                   callSiteReceiver: $0, declaredReceiver: declared, sema: sema
               )
           })
        {
            return true
        }
        if case let .classType(actualClass) = sema.types.kind(of: actual),
           case let .classType(declaredClass) = sema.types.kind(of: declared),
           actualClass.args.isEmpty,
           declaredClass.args.isEmpty,
           let actualSymbol = sema.symbols.symbol(actualClass.classSymbol),
           let declaredSymbol = sema.symbols.symbol(declaredClass.classSymbol),
           actualSymbol.fqName == declaredSymbol.fqName
        {
            return true
        }
        if case let .typeParam(actualParam) = sema.types.kind(of: actual),
           sema.symbols.typeParameterUpperBounds(for: actualParam.symbol).contains(where: {
               sema.types.isSubtype($0, declaredReceiver)
           })
        {
            return true
        }
        if case let .typeParam(actualParam) = sema.types.kind(of: actual),
           case let .classType(declaredClass) = sema.types.kind(of: declared),
           sema.symbols.typeParameterUpperBounds(for: actualParam.symbol).contains(where: { bound in
               guard sema.types.nullabilitySubtype(
                   sema.types.nullability(of: bound),
                   sema.types.nullability(of: declaredReceiver)
               ) else {
                   return false
               }
               guard case let .classType(boundClass) = sema.types.kind(of: sema.types.makeNonNullable(bound)) else {
                   return false
               }
               return boundClass.classSymbol == declaredClass.classSymbol
           })
        {
            return true
        }
        if case .typeParam = sema.types.kind(of: declared) {
            return true
        }
        func typeArgumentLikeMatch(actual: TypeID?, declared: TypeID?) -> Bool {
            switch (actual, declared) {
            case let (actual?, declared?):
                let actualNonNull = sema.types.makeNonNullable(actual)
                let declaredNonNull = sema.types.makeNonNullable(declared)
                if sema.types.isSubtype(actualNonNull, declaredNonNull) {
                    return true
                }
                if case .typeParam = sema.types.kind(of: declaredNonNull) {
                    return true
                }
                return false
            case (nil, nil):
                return true
            default:
                return false
            }
        }
        func containsTypeParam(_ t: TypeID) -> Bool {
            let nonNull = sema.types.makeNonNullable(t)
            if case .typeParam = sema.types.kind(of: nonNull) { return true }
            if case let .classType(ct) = sema.types.kind(of: nonNull) {
                return ct.args.contains(where: { arg in
                    switch arg {
                    case let .invariant(inner), let .out(inner), let .in(inner):
                        return containsTypeParam(inner)
                    case .star:
                        return false
                    }
                })
            }
            return false
        }
        if case let .functionType(declaredFn) = sema.types.kind(of: declared),
           case let .functionType(actualFn) = sema.types.kind(of: actual)
        {
            let declaredParameters = (declaredFn.receiver.map { [$0] } ?? []) + declaredFn.params
            let actualParameters = (actualFn.receiver.map { [$0] } ?? []) + actualFn.params
            if declaredFn.contextReceivers.count == actualFn.contextReceivers.count,
               declaredFn.isSuspend == actualFn.isSuspend,
               declaredParameters.count == actualParameters.count,
               zip(actualFn.contextReceivers, declaredFn.contextReceivers).allSatisfy({ actualContext, declaredContext in
                   typeArgumentLikeMatch(actual: actualContext, declared: declaredContext)
               }),
               zip(actualParameters, declaredParameters).allSatisfy({ actualParameter, declaredParameter in
                   typeArgumentLikeMatch(actual: actualParameter, declared: declaredParameter)
               }),
               typeArgumentLikeMatch(actual: actualFn.returnType, declared: declaredFn.returnType)
            {
                return true
            }
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .kClassType(actualKClass) = sema.types.kind(of: actual),
           declaredCt.classSymbol == sema.types.kClassInterfaceSymbol,
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t):
                   return typeArgumentLikeMatch(actual: actualKClass.argument, declared: t)
               case .in:
                   return true
               case .star:
                   return true
               }
           })
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .classType(actualCt) = sema.types.kind(of: actual),
           actualCt.classSymbol != declaredCt.classSymbol,
           sema.types.isNominalSubtypeSymbol(actualCt.classSymbol, of: declaredCt.classSymbol),
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t), let .in(t):
                   return containsTypeParam(t)
               case .star:
                   return false
               }
           })
        {
            return true
        }
        if case let .classType(declaredCt) = sema.types.kind(of: declared),
           case let .classType(actualCt) = sema.types.kind(of: actual),
           actualCt.classSymbol == declaredCt.classSymbol,
           declaredCt.args.contains(where: { arg in
               switch arg {
               case let .invariant(t), let .out(t), let .in(t):
                   return containsTypeParam(t)
               case .star:
                   return false
               }
           })
        {
            return true
        }
        if case let .kClassType(declaredKClass) = sema.types.kind(of: declared),
           case .typeParam = sema.types.kind(of: declaredKClass.argument),
           case let .classType(actualClass) = sema.types.kind(of: actual),
           actualClass.classSymbol == sema.types.kClassInterfaceSymbol,
           actualClass.args.count == 1
        {
            return true
        }
        if case let .kClassType(declaredKClass) = sema.types.kind(of: declared),
           case let .classType(actualClass) = sema.types.kind(of: actual),
           actualClass.classSymbol == sema.types.kClassInterfaceSymbol,
           actualClass.args.count == 1
        {
            let argument: TypeID
            switch actualClass.args[0] {
            case let .invariant(type), let .out(type): argument = type
            case .star, .in: argument = sema.types.anyType
            }
            return typeArgumentLikeMatch(actual: argument, declared: declaredKClass.argument)
        }
        if case let .kClassType(declaredKClass) = sema.types.kind(of: declared),
           case let .kClassType(actualKClass) = sema.types.kind(of: actual)
        {
            return typeArgumentLikeMatch(actual: actualKClass.argument, declared: declaredKClass.argument)
        }
        return false
    }

    private func typeParameterHasNonNullUpperBoundMatchingReceiver(
        _ symbol: SymbolID,
        declaredReceiver: TypeID,
        declaredNonNull: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard case let .classType(declaredClass) = sema.types.kind(of: declaredNonNull) else {
            return false
        }
        return sema.symbols.typeParameterUpperBounds(for: symbol).contains { bound in
            let nonNullBound = sema.types.makeNonNullable(bound)
            guard case let .classType(boundClass) = sema.types.kind(of: nonNullBound),
                  boundClass.classSymbol == declaredClass.classSymbol,
                  sema.types.nullabilitySubtype(
                      sema.types.nullability(of: nonNullBound),
                      sema.types.nullability(of: declaredReceiver)
                  )
            else {
                return false
            }
            // Class-symbol equality stays lenient for F-bounded parameters
            // (the bound's `Comparable<T>` and the candidate's
            // `Comparable<T_C>` are different type-parameter symbols), but
            // concrete type arguments must still agree: `T : Cell<Int>?`
            // must not match a `Cell<String>` receiver.
            if typeMentionsTypeParameter(nonNullBound, sema: sema)
                || typeMentionsTypeParameter(declaredReceiver, sema: sema)
            {
                return true
            }
            return sema.types.isSubtype(nonNullBound, declaredNonNull)
        }
    }

    func tryBuiltinFlowMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverElementType: TypeID,
        args: [CallArgument],
        safeCall: Bool,
        ast: ASTModule,
        sema: SemaModule,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let memberName = ctx.interner.resolve(calleeName)
        // KUU-1351: this set must stay within the real kotlinx-coroutines Flow
        // surface; `onErrorReturn`/`onErrorResume`/`delayEach` are not kotlinx
        // Flow operators, so admitting them here would accept code that kotlinc
        // rejects as unresolved.
        guard KnownCompilerNames(interner: ctx.interner).builtinFlowMemberNames.contains(calleeName) else {
            return nil
        }

        switch memberName {
        case "toList":
            guard args.isEmpty else {
                return nil
            }
            let listSymbol = sema.symbols.lookupByShortName(ctx.interner.intern("List")).first
            let resultType: TypeID = if let listSymbol {
                sema.types.make(.classType(ClassType(
                    classSymbol: listSymbol,
                    args: [.invariant(receiverElementType)],
                    nullability: .nonNull
                )))
            } else {
                sema.types.anyType
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "first":
            guard args.isEmpty else {
                return nil
            }
            let firstType = receiverElementType
            let finalType = safeCall ? sema.types.makeNullable(firstType) : firstType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "single":
            guard args.isEmpty else {
                return nil
            }
            let singleType = receiverElementType
            let finalType = safeCall ? sema.types.makeNullable(singleType) : singleType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        case "take", "buffer", "debounce", "flowOn":
            guard args.count == 1 else {
                return nil
            }
            let expectedArgType: TypeID = memberName == "flowOn" ? sema.types.anyType : sema.types.intType
            _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedArgType)
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "conflate":
            guard args.isEmpty else {
                return nil
            }
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "retry":
            guard args.count == 1 else {
                return nil
            }
            _ = driver.inferExpr(
                args[0].expr,
                ctx: ctx,
                locals: &locals,
                expectedType: sema.types.intType
            )
            sema.bindings.markFlowExpr(id)
            sema.bindings.bindFlowElementType(receiverElementType, forExpr: id)
            let flowType = driver.helpers.makeFlowType(
                elementType: receiverElementType, sema: sema, interner: ctx.interner
            ) ?? sema.types.anyType
            let resultType = safeCall ? sema.types.makeNullable(flowType) : flowType
            sema.bindings.bindExprType(id, type: resultType)
            return resultType

        case "map", "filter", "collect", "collectLatest", "transform", "takeWhile", "dropWhile",
             "flatMapConcat", "flatMapMerge", "flatMapLatest",
             "catch", "retryWhen":
            let lambdaArgIndex: Int
            if memberName == "flatMapMerge" && args.count == 2 {
                _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: sema.types.intType)
                lambdaArgIndex = 1
            } else if args.count == 1 {
                lambdaArgIndex = 0
            } else {
                return nil
            }
            let expectsLambdaTypeConstraint = switch ast.arena.expr(args[lambdaArgIndex].expr) {
            case .callableRef:
                false
            default:
                true
            }
            let lambdaReturnType: TypeID = switch memberName {
            case "filter", "takeWhile", "dropWhile":
                sema.types.booleanType
            case "collect", "collectLatest":
                sema.types.unitType
            case "transform":
                sema.types.unitType
            case "catch":
                sema.types.unitType
            case "retryWhen":
                sema.types.booleanType
            default:
                sema.types.anyType
            }
            let lambdaParameterTypes: [TypeID] = switch memberName {
            case "catch":
                [sema.types.anyType]
            case "retryWhen":
                [sema.types.anyType, sema.types.longType]
            default:
                [receiverElementType]
            }
            let lambdaExpectedType = sema.types.make(.functionType(FunctionType(
                params: lambdaParameterTypes,
                returnType: lambdaReturnType,
                isSuspend: ["collect", "collectLatest", "takeWhile", "dropWhile", "map", "filter", "flatMapConcat", "flatMapMerge", "flatMapLatest", "retryWhen"].contains(memberName),
                nullability: .nonNull
            )))
            if expectsLambdaTypeConstraint {
                _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals, expectedType: lambdaExpectedType)
            } else {
                _ = driver.inferExpr(args[lambdaArgIndex].expr, ctx: ctx, locals: &locals)
            }

            if memberName != "collect" && memberName != "collectLatest" {
                sema.bindings.markFlowExpr(id)
                let resultElementType: TypeID = if memberName == "map",
                                                   case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[lambdaArgIndex].expr),
                                                   let mappedType = sema.bindings.exprType(for: bodyExpr)
                {
                    mappedType
                } else if memberName == "transform" {
                    sema.types.anyType
                } else if memberName == "flatMapConcat" || memberName == "flatMapMerge" || memberName == "flatMapLatest",
                          case let .lambdaLiteral(_, bodyExpr, _, _) = ast.arena.expr(args[lambdaArgIndex].expr)
                {
                    if let elem = sema.bindings.flowElementType(forExpr: bodyExpr) {
                        elem
                    } else if case .nameRef = ast.arena.expr(bodyExpr),
                              let sym = sema.bindings.identifierSymbol(for: bodyExpr),
                              let elem = sema.bindings.flowElementType(forSymbol: sym)
                    {
                        elem
                    } else if let bodyType = sema.bindings.exprType(for: bodyExpr),
                              let flowClassSymbol = sema.symbols.lookup(fqName: [
                                  ctx.interner.intern("kotlinx"), ctx.interner.intern("coroutines"),
                                  ctx.interner.intern("flow"), ctx.interner.intern("Flow"),
                              ]),
                              case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(bodyType)),
                              classType.classSymbol == flowClassSymbol,
                              let firstArg = classType.args.first
                    {
                        switch firstArg {
                        case let .invariant(t), let .out(t), let .in(t):
                            t
                        case .star:
                            sema.types.anyType
                        }
                    } else {
                        sema.types.anyType
                    }
                } else {
                    receiverElementType
                }
                sema.bindings.bindFlowElementType(resultElementType, forExpr: id)
            }

            let resultType: TypeID
            if memberName == "collect" || memberName == "collectLatest" {
                resultType = sema.types.unitType
            } else {
                let resultElement = sema.bindings.flowElementType(forExpr: id) ?? receiverElementType
                resultType = driver.helpers.makeFlowType(
                    elementType: resultElement, sema: sema, interner: ctx.interner
                ) ?? sema.types.anyType
            }
            let finalType = safeCall ? sema.types.makeNullable(resultType) : resultType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType

        default:
            return nil
        }
    }

    func tryContinuationSyntheticMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let knownNames = KnownCompilerNames(interner: ctx.interner)
        guard calleeName == knownNames.resume || calleeName == knownNames.resumeWith || calleeName == knownNames.resumeWithException else {
            return nil
        }
        guard let continuationSymbol = ctx.sema.symbols.lookup(fqName: knownNames.kotlinContinuationFQName),
              let (_, receiverSymbol) = resolveClassTypeSymbol(receiverType, sema: ctx.sema),
              receiverSymbol.id == continuationSymbol
        else {
            return nil
        }
        guard args.count == 1 else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "No viable overload found for call.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: ctx.sema)
        }

        var expectedArgType: TypeID = ctx.sema.types.anyType
        if calleeName == knownNames.resume,
           let classType = resolveClassType(receiverType, sema: ctx.sema),
           let continuationArg = classType.args.first
        {
            switch continuationArg {
            case let .invariant(type), let .out(type), let .in(type):
                expectedArgType = type
            case .star:
                expectedArgType = ctx.sema.types.anyType
            }
        } else if calleeName == knownNames.resumeWith,
                  let classType = resolveClassType(receiverType, sema: ctx.sema),
                  let continuationArg = classType.args.first,
                  let resultSymbol = ctx.sema.symbols.lookup(fqName: [ctx.interner.intern("kotlin"), ctx.interner.intern("Result")])
        {
            let innerType: TypeID
            switch continuationArg {
            case let .invariant(type), let .out(type), let .in(type):
                innerType = type
            case .star:
                innerType = ctx.sema.types.anyType
            }
            expectedArgType = ctx.sema.types.make(.classType(ClassType(
                classSymbol: resultSymbol,
                args: [.out(innerType)],
                nullability: .nonNull
            )))
        }

        _ = driver.inferExpr(args[0].expr, ctx: ctx, locals: &locals, expectedType: expectedArgType)

        let expectedExternalLinkName = if calleeName == knownNames.resume {
            "__kk_coroutine_continuation_resume"
        } else if calleeName == knownNames.resumeWith {
            "__kk_coroutine_continuation_resume_with"
        } else {
            "__kk_coroutine_continuation_resume_with_exception"
        }
        let functionSymbol = ctx.sema.symbols.lookupByShortName(calleeName).first(where: { candidate in
            guard let symbol = ctx.sema.symbols.symbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            return ctx.sema.symbols.externalLinkName(for: candidate) == expectedExternalLinkName
        })
        if let functionSymbol {
            ctx.sema.bindings.bindCall(id, binding: CallBinding(
                chosenCallee: functionSymbol,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            ))
            ctx.sema.bindings.bindIdentifier(id, symbol: functionSymbol)
            ctx.sema.bindings.bindExprType(id, type: ctx.sema.types.unitType)
            return ctx.sema.types.unitType
        }
        return nil
    }

    func isFileType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        return symbol.fqName.count >= 2
            && symbol.fqName.last! == knownNames.file
            && symbol.fqName[symbol.fqName.count - 2] == knownNames.io
    }

    func isBufferedReaderType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let knownNames = KnownCompilerNames(interner: interner)
        let nonNullType = sema.types.makeNonNullable(receiverType)
        guard let (_, symbol) = resolveClassTypeSymbol(nonNullType, sema: sema) else {
            return false
        }
        return symbol.fqName.count >= 2
            && symbol.fqName.last! == knownNames.bufferedReader
            && symbol.fqName[symbol.fqName.count - 2] == knownNames.io
    }

    func kClassReceiverArgumentType(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let nonNullReceiverType = sema.types.makeNonNullable(receiverType)
        if case let .kClassType(kClassType) = sema.types.kind(of: nonNullReceiverType) {
            return kClassType.argument
        }

        guard let (classType, symbol) = resolveClassTypeSymbol(nonNullReceiverType, sema: sema) else {
            return nil
        }

        let kotlinReflectKClassFQName = [
            interner.intern("kotlin"),
            interner.intern("reflect"),
            interner.intern("KClass"),
        ]
        let kClassName = interner.intern("KClass")
        let isKClassSymbol = symbol.fqName == kotlinReflectKClassFQName
            || (symbol.name == kClassName && symbol.fqName.isEmpty)
        guard isKClassSymbol else {
            return nil
        }
        guard let firstArg = classType.args.first else {
            return sema.types.anyType
        }
        return switch firstArg {
        case let .invariant(type), let .out(type), let .in(type):
            type
        case .star:
            sema.types.anyType
        }
    }

    func tryInferNumericCompanionMemberCall(
        _ id: ExprID,
        receiverID: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard case let .nameRef(receiverName, _) = ast.arena.expr(receiverID),
              locals[receiverName] == nil
        else {
            return nil
        }

        let receiverStr = interner.resolve(receiverName)
        let memberStr = interner.resolve(calleeName)

        if args.isEmpty,
           let (constantType, constantValue) = numericCompanionConstant(
               typeName: receiverStr, memberName: memberStr)
        {
            sema.bindings.bindConstExprValue(id, value: constantValue)
            sema.bindings.bindExprType(id, type: constantType)
            return constantType
        }

        guard memberStr == "fromBits",
              args.count == 1,
              let receiverType = driver.helpers.resolveBuiltinTypeName(
                  receiverName, types: sema.types, interner: interner
              )
        else {
            return nil
        }
        let resultType: TypeID? = if receiverType == sema.types.doubleType {
            sema.types.doubleType
        } else if receiverType == sema.types.floatType {
            sema.types.floatType
        } else {
            nil
        }
        guard let resultType else {
            return nil
        }

        let expectedArgumentType = receiverType == sema.types.doubleType
            ? sema.types.longType
            : sema.types.intType
        let argumentTypes = args.map { argument in
            driver.inferExpr(
                argument.expr,
                ctx: ctx,
                locals: &locals,
                expectedType: expectedArgumentType
            )
        }
        let sourceFQName = [interner.intern("kotlin"), calleeName]
        guard let chosenCallee = sema.symbols.lookupAll(fqName: sourceFQName).first(where: { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isSourceBackedSymbol(candidate),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.receiverType == nil,
                  signature.returnType == resultType,
                  signature.parameterTypes.count == argumentTypes.count
            else {
                return false
            }
            return zip(signature.parameterTypes, argumentTypes).allSatisfy { parameterType, argumentType in
                argumentType == parameterType || sema.types.isSubtype(argumentType, parameterType)
            }
        }) else {
            return nil
        }

        sema.bindings.bindIdentifier(id, symbol: chosenCallee)
        sema.bindings.bindCall(
            id,
            binding: CallBinding(
                chosenCallee: chosenCallee,
                substitutedTypeArguments: [],
                parameterMapping: [0: 0]
            )
        )
        sema.bindings.bindCallableTarget(id, target: .symbol(chosenCallee))
        sema.bindings.bindExprType(id, type: resultType)
        // Lowering must not pass the type-name receiver as a runtime value.
        sema.bindings.bindExprType(receiverID, type: sema.types.unitType)
        return resultType
    }

}
