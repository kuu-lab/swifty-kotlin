// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Candidate filtering and adjustment, extracted verbatim from
    /// `inferRegularMemberCall`: expect/actual de-duplication, visibility
    /// filtering, nullable Any toString/hashCode, receiver-specificity and
    /// per-member preference rules (forEach, withDefault, coerceX, toList,
    /// take, unzip, isNullOrEmpty, format, trimMargin), ending in the
    /// no-candidate fallback when nothing remains.
    /// `earlyReturnType` carries a bound result when a rule short-circuits;
    /// otherwise the surviving candidate set is returned (never empty).
    func filterRegularMemberCallCandidates(
        _ request: MemberCallInferenceRequest,
        allCandidates: [SymbolID],
        argTypes: [TypeID],
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        isNullLiteralReceiver: Bool,
        isFlowReceiver: Bool,
        flowElementType: TypeID,
        hasLeadingLocaleArgument: Bool,
        isSuperCall: Bool,
        locals: inout LocalBindings
    ) -> (candidates: [SymbolID], earlyReturnType: TypeID?) {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        // Direct member lookup and short-name extension recovery can bypass
        // cachedScopeLookup, which normally removes an expect declaration once
        // its matching actual is linked. Apply the same rule before resolving
        // member-style calls, or the identical expect/actual signatures become
        // two viable overloads and produce a false ambiguity.
        let candidateSet = Set(allCandidates)
        let resolvedCandidates = allCandidates.filter { candidate in
            if ctx.cachedSymbol(candidate)?.flags.contains(.localFunction) == true,
               locals[calleeName]?.symbol != candidate
            {
                return false
            }
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.flags.contains(.expectDeclaration)
            else {
                return true
            }
            guard let actual = sema.symbols.actualSymbol(for: candidate) else {
                return true
            }
            return !candidateSet.contains(actual)
        }
        let (visible, invisible) = ctx.filterByVisibility(resolvedCandidates)
        let memberName = interner.resolve(calleeName)
        if !isClassNameReceiver,
           !safeCall,
           args.isEmpty,
           explicitTypeArgs.isEmpty,
           ast.arena.isExplicitCall(id),
           invisible.isEmpty,
           sema.types.nullability(of: receiverType) == .nullable,
           memberName == "toString" || memberName == "hashCode",
           !visible.contains(where: { candidate in
               guard let signature = sema.symbols.functionSignature(for: candidate),
                     signature.parameterTypes.isEmpty,
                     let declaredReceiver = signature.receiverType,
                     sema.types.nullability(of: declaredReceiver) == .nullable
               else {
                   return false
               }
               return sema.types.isSubtype(receiverType, declaredReceiver)
           })
        {
            // Kotlin exposes toString() and hashCode() through nullable Any
            // extensions. Flat-representation and class receivers can expose
            // only non-null synthetic members, which the normal resolver must
            // reject for a nullable receiver before KIR can use the Any ABI.
            let resultType = memberName == "toString" ? sema.types.stringType : sema.types.intType
            sema.bindings.bindExprType(id, type: resultType)
            return ([], resultType)
        }
        var candidates = preferMostSpecificMemberReceiverCandidates(
            visible,
            receiverType: lookupReceiverType,
            argumentTypes: argTypes,
            sema: sema,
            interner: interner
        )
        if calleeName == knownNames.forEach {
            let receiverClassification = ReceiverClassifier(sema: sema, interner: interner).classify(
                receiverID: receiverID,
                receiverType: lookupReceiverType,
                ast: ast
            )
            let isEligibleIterableReceiver = receiverClassification.isIterableReceiver
                || (
                    !receiverClassification.isCollectionReceiver
                        && !receiverClassification.isSequenceReceiver
                        && !receiverClassification.isArrayReceiver
                        && !receiverClassification.isMapReceiver
                        && !receiverClassification.isSetReceiver
                )
            if !isEligibleIterableReceiver {
                let iterableFQName = knownNames.kotlinCollectionsIterableFQName
                candidates.removeAll { candidate in
                    guard sema.symbols.isSourceBackedSymbol(candidate),
                          let signatureReceiver = sema.symbols.functionSignature(for: candidate)?.receiverType,
                          let (_, receiverSymbol) = resolveClassTypeSymbol(signatureReceiver, sema: sema)
                    else {
                        return false
                    }
                    return receiverSymbol.fqName == iterableFQName
                }
            }
        }
        // Kotlin selects MutableMap.withDefault over the less-specific
        // Map.withDefault extension for a MutableMap receiver. Resolve this
        // subtype preference before trailing-lambda overload inference sees
        // two otherwise identical function shapes.
        if calleeName == knownNames.withDefault,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(lookupReceiverType)
        {
            let mutableMapCandidates = candidates.filter { candidate in
                guard sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapCandidates.isEmpty {
                candidates = mutableMapCandidates
            }
        }
        if calleeName == knownNames.coerceIn,
           !args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            // The generic ClosedFloatingPointRange overload must not turn a
            // scalar call with the wrong arity or argument type into a type
            // constraint failure. Kotlin reports those calls as no overload.
            candidates.removeAll { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == knownNames.closedFloatingPointRange
            }
        }
        if calleeName == knownNames.coerceIn,
           args.contains(where: { sema.bindings.isFloatingPointRangeExpr($0.expr) })
        {
            // Imported `.kklib` metadata does not make a generic extension whose
            // receiver is a type parameter visible through the receiver-type
            // fallback above. Recover the source-backed range overloads here so
            // the same call resolves with bundled source injection and a library.
            let genericRangeCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let symbol = sema.symbols.symbol(candidate),
                      symbol.kind == .function,
                      sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      signature.parameterTypes.count == 1,
                      let (_, parameterSymbol) = resolveClassTypeSymbol(
                          signature.parameterTypes[0], sema: sema
                      )
                else {
                    return false
                }
                return parameterSymbol.name == knownNames.closedFloatingPointRange
            }
            candidates.append(contentsOf: genericRangeCandidates.filter { !candidates.contains($0) })
        }
        if calleeName == knownNames.coerceAtLeast
            || calleeName == knownNames.coerceAtMost
            || calleeName == knownNames.coerceIn
        {
            // A concrete `Int.coerceIn`/`UByte.coerceAtLeast`-style overload is
            // strictly more specific than the generic `T.coerceX` extensions
            // (upstream's overload ranking). Keeping both in the candidate set
            // turns calls whose arguments need literal coercion (or whose
            // argument type makes the generic's bound fail) into a constraint
            // error instead of binding the concrete overload. Keep the generic
            // only when no concrete overload has the same arity — i.e.
            // user-defined `Comparable` receivers, or shapes no concrete
            // overload covers (e.g. `Double.coerceIn(ClosedFloatingPointRange)`).
            let concreteArities = Set(candidates.compactMap { candidate -> Int? in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.isEmpty
                else {
                    return nil
                }
                return signature.parameterTypes.count
            })
            candidates.removeAll { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      signature.typeParameterSymbols.count == 1,
                      let receiver = signature.receiverType,
                      resolveClassTypeSymbol(receiver, sema: sema) == nil
                else {
                    return false
                }
                return concreteArities.contains(signature.parameterTypes.count)
            }
        }
        if calleeName == knownNames.toList {
            candidates = preferCollectionToListCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.take {
            candidates = preferListTakeCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if calleeName == knownNames.unzip {
            candidates = preferListUnzipCandidates(
                candidates,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
        }
        if isNullLiteralReceiver,
           args.isEmpty,
           calleeName == knownNames.isNullOrEmpty,
           let charSequenceType = syntheticCharSequenceType(sema: sema),
           candidates.contains(where: { candidate in
               sema.symbols.functionSignature(for: candidate)?.receiverType == sema.types.makeNullable(charSequenceType)
           })
        {
            // Kotlin stdlib also provides Array/Collection/Map nullable-receiver
            // isNullOrEmpty overloads. They are still lowered through synthetic
            // typed-receiver fallbacks here, but a bare null receiver must see the
            // same ambiguous overload set as kotlinc.
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0003",
                "Ambiguous overload resolution.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return (candidates, sema.types.errorType)
        }
        if hasLeadingLocaleArgument {
            candidates.removeAll { candidate in
                isSyntheticStringFormatCandidate(candidate, sema: sema, interner: interner)
            }
        }
        if calleeName == knownNames.trimMargin {
            let receiverTypeForCheck = safeCall
                ? sema.types.makeNonNullable(lookupReceiverType)
                : lookupReceiverType
            if sema.types.isSubtype(receiverTypeForCheck, sema.types.stringType) {
                if !explicitTypeArgs.isEmpty {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return (candidates, sema.types.errorType)
                }
                let trimMarginFQName = knownNames.kotlinTextPackage + [calleeName]
                let chosen = sema.symbols.lookupAll(fqName: trimMarginFQName).first(where: { symbolID in
                    guard let signature = sema.symbols.functionSignature(for: symbolID),
                          signature.receiverType == sema.types.stringType
                    else {
                        return false
                    }
                    switch args.count {
                    case 0:
                        return signature.parameterTypes.isEmpty
                    case 1:
                        return signature.parameterTypes.count == 1
                            && sema.types.isSubtype(sema.types.makeNonNullable(argTypes[0]), signature.parameterTypes[0])
                    default:
                        return false
                    }
                })
                if let chosen {
                    let returnType = bindCallAndResolveReturnType(
                        id,
                        chosen: chosen,
                        resolved: ResolvedCall(
                            chosenCallee: chosen,
                            substitutedTypeArguments: [:],
                            parameterMapping: args.isEmpty ? [:] : [0: 0],
                            diagnostic: nil
                        ),
                        sema: sema
                    )
                    let finalType = safeCall ? sema.types.makeNullable(returnType) : returnType
                    sema.bindings.bindExprType(id, type: finalType)
                    return (candidates, finalType)
                }
            }
        }
        if candidates.isEmpty {
            return (candidates, inferRegularMemberCallWithoutCandidates(
                request,
                receiverType: receiverType,
                lookupReceiverType: lookupReceiverType,
                memberLookupType: memberLookupType,
                argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver,
                classNameReceiverNominalSymbol: classNameReceiverNominalSymbol,
                isNullLiteralReceiver: isNullLiteralReceiver,
                isFlowReceiver: isFlowReceiver,
                flowElementType: flowElementType,
                hasLeadingLocaleArgument: hasLeadingLocaleArgument,
                invisibleCandidates: invisible,
                isSuperCall: isSuperCall,
                locals: &locals
            ))
        }

        return (candidates, nil)
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
