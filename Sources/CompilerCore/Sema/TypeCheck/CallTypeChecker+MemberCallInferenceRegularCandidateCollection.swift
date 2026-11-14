// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// `earlyReturnType` carries a bound result when a companion property or
    /// extension short-circuits resolution; otherwise candidates and the
    /// companion receiver type are returned for the resolver.
    func collectRegularMemberCallCandidates(
        _ request: MemberCallInferenceRequest,
        argTypes: [TypeID],
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        isSuperCall: Bool,
        supertypeSymbols: Set<SymbolID>,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        rangeSourceMemberLookupType: TypeID?,
        isULongProgressionFirstLastMember: Bool,
        isLongRangeLiteralContainsCall: Bool,
        callableReferenceFunctionType: TypeID?,
        locals: LocalBindings,
        typeAliasConstructor: inout TypeAliasConstructorContext?
    ) -> (allCandidates: [SymbolID], companionReceiverType: TypeID?, earlyReturnType: TypeID?) {

        // Track the companion type so we can pass it (not the owner class type)
        // as the implicit receiver when resolving the call.
        var companionReceiverType: TypeID?

        var allCandidates: [SymbolID]
        if isClassNameReceiver {
            // Class-name receiver: only companion members are valid targets.
            // Search from the companion, rather than the owner class, so its
            // inherited members are included without exposing owner instances.
            let classNameReceiverBlockSymbol: SymbolID? = {
                guard let ownerNominal = classNameReceiverNominalSymbol else { return nil }
                // In a platform module, resolve through the implementation companion
                // so member calls bind to actual declarations with emitted symbols.
                if let actualOwner = request.sema.symbols.actualSymbol(for: ownerNominal),
                   let blockCompanion = companionBlockSymbol(for: actualOwner, sema: request.sema, interner: request.interner)
                {
                    return blockCompanion
                }
                if let blockCompanion = companionBlockSymbol(for: ownerNominal, sema: request.sema, interner: request.interner) {
                    return blockCompanion
                }
                return nil
            }()
            let classNameReceiverSourceCompanionSymbol: SymbolID? = {
                guard let ownerNominal = classNameReceiverNominalSymbol else { return nil }
                if let actualOwner = request.sema.symbols.actualSymbol(for: ownerNominal),
                   let companion = request.sema.symbols.companionObjectSymbol(for: actualOwner)
                {
                    return companion
                }
                return request.sema.symbols.companionObjectSymbol(for: ownerNominal)
            }()
            let classNameReceiverCompanionSymbol = classNameReceiverBlockSymbol
                ?? classNameReceiverSourceCompanionSymbol
            let companionExtensionReceiverType = classNameReceiverNominalSymbol.flatMap { owner in
                request.sema.symbols.symbol(owner).map { _ in
                    request.sema.types.make(.classType(ClassType(
                        classSymbol: owner,
                        args: [],
                        nullability: .nonNull
                    )))
                }
            }
            if let companionSymbol = classNameReceiverCompanionSymbol {
                let companionTypeForExtensionLookup = request.sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))

                // When args are present this is a function call, so skip the
                // property short-circuit to avoid shadowing a companion function
                // of the same name.
                if request.args.isEmpty {
                    let directPropertyReceivers = [
                        classNameReceiverBlockSymbol.map { ($0, companionTypeForExtensionLookup) },
                        classNameReceiverSourceCompanionSymbol.map { symbol in
                            (symbol, request.sema.types.make(.classType(ClassType(
                                classSymbol: symbol, args: [], nullability: .nonNull
                            ))))
                        },
                    ].compactMap { $0 }
                    let directProperty = directPropertyReceivers.first { _, receiverType in
                        driver.helpers.lookupMemberProperty(
                            named: request.calleeName,
                            receiverType: receiverType,
                            sema: request.sema
                        ) != nil
                    }.flatMap { _, receiverType in
                        driver.helpers.lookupMemberProperty(
                            named: request.calleeName,
                            receiverType: receiverType,
                            sema: request.sema
                        ).map { ($0, receiverType) }
                    }
                    if let (propResult, propertyReceiverType) = directProperty {
                        let propSymbol = propResult.symbol
                        let propType = propResult.type
                        if let propSym = request.sema.symbols.symbol(propSymbol),
                           !request.ctx.visibilityChecker.isAccessible(
                               propSym,
                               fromFile: request.ctx.currentFileID,
                               enclosingClass: request.ctx.enclosingClassSymbol
                           )
                        {
                            driver.helpers.emitVisibilityError(for: propSym, name: request.interner.resolve(request.calleeName), range: request.range, diagnostics: request.ctx.sema.diagnostics)
                            return ([], companionReceiverType, driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema))
                        }
                        driver.helpers.checkDeprecation(
                            for: propSymbol,
                            sema: request.sema,
                            interner: request.interner,
                            range: request.range,
                            diagnostics: request.ctx.sema.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: propSymbol,
                            ctx: request.ctx,
                            range: request.range,
                            diagnostics: request.ctx.sema.diagnostics
                        )
                        // Re-bind receiver to companion type for correct KIR lowering
                        request.sema.bindings.bindExprType(request.receiverID, type: propertyReceiverType)
                        request.sema.bindings.bindIdentifier(request.id, symbol: propSymbol)
                        request.sema.bindings.bindExprType(request.id, type: propType)
                        return ([], companionReceiverType, propType)
                    }

                    if let sourceCompanion = classNameReceiverSourceCompanionSymbol,
                       sourceCompanion != classNameReceiverBlockSymbol
                    {
                        let sourceCompanionType = request.sema.types.make(.classType(ClassType(
                            classSymbol: sourceCompanion, args: [], nullability: .nonNull
                        )))
                        if let extensionPropertyType = resolveExtensionPropertyGetter(
                            id: request.id,
                            calleeName: request.calleeName,
                            range: request.range,
                            receiverType: sourceCompanionType,
                            expectedType: request.expectedType,
                            ctx: request.ctx
                        ) {
                            request.sema.bindings.bindExprType(request.receiverID, type: sourceCompanionType)
                            request.sema.bindings.bindExprType(request.id, type: extensionPropertyType)
                            return ([], sourceCompanionType, extensionPropertyType)
                        }
                    }
                    if let ownerReceiverType = companionExtensionReceiverType,
                       let extensionPropertyType = resolveExtensionPropertyGetter(
                           id: request.id,
                           calleeName: request.calleeName,
                           range: request.range,
                           receiverType: ownerReceiverType,
                           expectedType: request.expectedType,
                           ctx: request.ctx,
                           invocationCandidateFilter: { candidate in
                               self.isCompanionExtension(candidate, ctx: request.ctx)
                           }
                       )
                    {
                        companionReceiverType = ownerReceiverType
                        request.sema.bindings.bindExprType(request.receiverID, type: ownerReceiverType)
                        request.sema.bindings.bindExprType(request.id, type: extensionPropertyType)
                        return ([], companionReceiverType, extensionPropertyType)
                    }
                }

                // Then try companion function candidates
                var companionCandidates: [SymbolID] = []
                var selectedCompanionReceiverType: TypeID?
                if classNameReceiverBlockSymbol != nil {
                    companionCandidates = driver.helpers.collectMemberFunctionCandidates(
                        named: request.calleeName,
                        receiverType: companionTypeForExtensionLookup,
                        sema: request.sema,
                        interner: request.interner
                    )
                    if !companionCandidates.isEmpty {
                        selectedCompanionReceiverType = companionTypeForExtensionLookup
                    }
                }
                if companionCandidates.isEmpty,
                   let sourceCompanion = classNameReceiverSourceCompanionSymbol,
                   sourceCompanion != classNameReceiverBlockSymbol
                {
                    let sourceCompanionType = request.sema.types.make(.classType(ClassType(
                        classSymbol: sourceCompanion, args: [], nullability: .nonNull
                    )))
                    companionCandidates = driver.helpers.collectMemberFunctionCandidates(
                        named: request.calleeName,
                        receiverType: sourceCompanionType,
                        sema: request.sema,
                        interner: request.interner
                    )
                    if !companionCandidates.isEmpty {
                        selectedCompanionReceiverType = sourceCompanionType
                    }
                }
                if companionCandidates.isEmpty {
                    // A nearer-scope local extension on the companion's actual
                    // type resolves before an outer dispatch-receiver member
                    // extension — Kotlin searches the innermost scope first.
                    companionCandidates = request.ctx.scope.lookup(request.calleeName, matching: { candidate in
                        guard let symbol = request.ctx.cachedSymbol(candidate),
                              symbol.flags.contains(.localFunction),
                              (!request.ast.arena.isInfixCall(request.id)
                                   || symbol.flags.contains(.infixFunction)),
                              let signature = request.sema.symbols.functionSignature(for: candidate),
                              let declaredReceiver = signature.receiverType
                        else { return false }
                        return self.extensionReceiverMatchesDuringBuilderInference(
                            callSiteReceiver: request.sema.types.makeNonNullable(companionTypeForExtensionLookup),
                            declaredReceiver: declaredReceiver,
                            ctx: request.ctx
                        )
                    }).filter {
                        self.extensionCandidateMatchesCallShape(
                            $0, request: request, argumentTypes: argTypes,
                            receiverType: companionTypeForExtensionLookup
                        )
                    }
                    if !companionCandidates.isEmpty {
                        selectedCompanionReceiverType = companionTypeForExtensionLookup
                    }
                }
                if companionCandidates.isEmpty {
                    // A member extension that cannot accept this call's
                    // argument shapes must not commit the slot — fall through
                    // to the lower-tier extension search instead. Only the
                    // argument SHAPE is checked: provisional argument types
                    // like `MutableList<Nothing>` are re-inferred against the
                    // parameter later, so an exact-type mismatch is not
                    // disqualifying here.
                    let memberExtensionCandidates = collectDispatchReceiverMemberExtensionCandidates(
                        named: request.calleeName,
                        extensionReceiverType: companionTypeForExtensionLookup,
                        ctx: request.ctx
                    ).filter { candidate in
                        guard let signature = request.sema.symbols.functionSignature(for: candidate),
                              let mapping = parameterMappingForCallArguments(
                                  request.args, in: signature, callRange: request.range, ctx: request.ctx
                              )
                        else { return false }
                        for (index, argument) in request.args.enumerated() {
                            guard case let .lambdaLiteral(lambdaParameters, _, _, _) =
                                    request.ctx.ast.arena.expr(argument.expr),
                                  let parameterIndex = mapping[index],
                                  let rawType = contextualCallArgumentType(
                                      argument, parameterIndex: parameterIndex, in: signature, ctx: request.ctx
                                  )
                            else { continue }
                            let parameterType = request.sema.types.makeNonNullable(
                                applyReceiverClassTypeArgs(
                                    to: rawType, signature: signature, candidate: candidate,
                                    receiverType: companionTypeForExtensionLookup, sema: request.sema
                                )
                            )
                            let functionType: FunctionType?
                            if case let .functionType(function) = request.sema.types.kind(of: parameterType) {
                                functionType = function
                            } else {
                                functionType = driver.helpers.samFunctionType(for: parameterType, sema: request.sema)
                            }
                            if let functionType {
                                if lambdaParameters.isEmpty {
                                    guard functionType.params.count <= 1 else { return false }
                                } else {
                                    guard functionType.params.count == lambdaParameters.count else { return false }
                                }
                            } else if parameterType != request.sema.types.anyType,
                                      parameterType != request.sema.types.errorType,
                                      !request.sema.types.typeContainsAnyTypeParam(parameterType) {
                                return false
                            }
                        }
                        return true
                    }
                    if !memberExtensionCandidates.isEmpty {
                        companionCandidates = memberExtensionCandidates
                        selectedCompanionReceiverType = companionTypeForExtensionLookup
                    }
                }
                if companionCandidates.isEmpty,
                   let ownerReceiverType = companionExtensionReceiverType
                {
                    companionCandidates = companionExtensionFunctionCandidates(
                        named: request.calleeName,
                        ownerReceiverType: ownerReceiverType,
                        ctx: request.ctx
                    )
                    if !companionCandidates.isEmpty {
                        selectedCompanionReceiverType = ownerReceiverType
                    }
                }
                // Precompiled library extensions are not inserted into
                // file scopes, because their receiver is resolved during
                // member-call inference. Recover those synthetic
                // declarations by short name for class-name receivers.
                let syntheticCompanionCandidates = {
                    request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                        guard let symbol = request.sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = request.sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else {
                            return false
                        }
                        guard self.isUnsignedRandomExtensionVisible(symbol, named: request.calleeName, ctx: request.ctx) else {
                            return false
                        }
                        return self.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: request.sema
                        )
                    }
                }
                if companionCandidates.isEmpty {
                    // Fall back to Companion-scoped extension functions
                    // (e.g. `fun Duration.Companion.parse(value: String): Duration`)
                    // written as Kotlin source at package scope. These are resolved
                    // via scope lookup (like ordinary extension functions), not the
                    // companion member lookup above.
                    companionCandidates = request.ctx.cachedScopeLookup(request.calleeName, matching: { candidate in
                        guard let symbol = request.ctx.cachedSymbol(candidate),
                              symbol.kind == .function,
                              let signature = request.sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else { return false }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: request.sema
                        )
                    })
                    if !companionCandidates.isEmpty {
                        // A scoped supertype-receiver extension (e.g.
                        // `fun Base64.encode` resolved through companion
                        // `Default`) satisfies this lookup, but the companion's
                        // synthetic members (inherited `Base64.encode(ByteArray)`)
                        // are still valid targets: keep them in the same set so
                        // member calls are not shadowed by the extension.
                        for candidate in syntheticCompanionCandidates() where !companionCandidates.contains(candidate) {
                            companionCandidates.append(candidate)
                        }
                    }
                }
                if companionCandidates.isEmpty {
                    companionCandidates = syntheticCompanionCandidates()
                }
                if !companionCandidates.isEmpty,
                   selectedCompanionReceiverType == nil
                {
                    selectedCompanionReceiverType = companionTypeForExtensionLookup
                }
                if let selectedCompanionReceiverType {
                    companionReceiverType = selectedCompanionReceiverType
                    // Re-bind receiver expression to companion type so KIR
                    // lowering passes the selected implementation receiver.
                    request.sema.bindings.bindExprType(request.receiverID, type: selectedCompanionReceiverType)
                }
                allCandidates = companionCandidates
            } else {
                if let ownerReceiverType = companionExtensionReceiverType {
                    if request.args.isEmpty,
                       let extensionPropertyType = resolveExtensionPropertyGetter(
                           id: request.id,
                           calleeName: request.calleeName,
                           range: request.range,
                           receiverType: ownerReceiverType,
                           expectedType: request.expectedType,
                           ctx: request.ctx,
                           invocationCandidateFilter: { candidate in
                               self.isCompanionExtension(candidate, ctx: request.ctx)
                           }
                       )
                    {
                        companionReceiverType = ownerReceiverType
                        request.sema.bindings.bindExprType(request.receiverID, type: ownerReceiverType)
                        request.sema.bindings.bindExprType(request.id, type: extensionPropertyType)
                        return ([], companionReceiverType, extensionPropertyType)
                    }
                    allCandidates = companionExtensionFunctionCandidates(
                        named: request.calleeName,
                        ownerReceiverType: ownerReceiverType,
                        ctx: request.ctx
                    )
                    if !allCandidates.isEmpty {
                        companionReceiverType = ownerReceiverType
                        request.sema.bindings.bindExprType(request.receiverID, type: ownerReceiverType)
                    }
                } else {
                    allCandidates = []
                }
            }
        } else {
            let allowedOwnerSymbols = isSuperCall && !supertypeSymbols.isEmpty ?
                supertypeSymbols : nil
            let hasScopedExactRangeExtension = rangeSourceMemberLookupType.map { sourceReceiverType in
                guard isULongProgressionFirstLastMember,
                      let sourceReceiverSymbol = driver.helpers.nominalSymbol(
                    of: request.sema.types.makeNonNullable(sourceReceiverType),
                    types: request.sema.types
                ) else {
                    return false
                }
                return request.ctx.cachedScopeLookup(request.calleeName).contains { candidate in
                    guard let symbol = request.sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == request.args.count,
                          let declaredReceiver = signature.receiverType,
                          let declaredReceiverSymbol = driver.helpers.nominalSymbol(
                              of: request.sema.types.makeNonNullable(declaredReceiver),
                              types: request.sema.types
                          )
                    else {
                        return false
                    }
                    return declaredReceiverSymbol == sourceReceiverSymbol
                }
            } ?? false
            let rangeSourceCandidates = hasScopedExactRangeExtension
                ? []
                : rangeSourceMemberLookupType.map {
                    collectRangeSourceExtensionCandidates(
                        named: request.calleeName,
                        receiverType: $0,
                        sema: request.sema,
                        interner: request.interner
                    )
                } ?? []
            // Source-backed range overloads are recovered from the bundled
            // declaration index because their extensions are not generally
            // visible through member lookup. A same-named extension in the
            // active Kotlin scope still has normal overload priority, though;
            // keep it ahead of the bundled candidates so a user declaration
            // is not silently replaced by the stdlib fallback.
            let rangeReceiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: request.receiverID,
                receiverType: lookupReceiverType,
                sema: request.sema,
                interner: request.interner
            )
            let scopedRangeUserCandidates: [SymbolID] = if request.calleeName == request.knownNames.contains,
                                                               let rangeSourceMemberLookupType,
                                                               rangeReceiverKind == .intRange
            {
                collectScopedRangeUserExtensionCandidates(
                    named: request.calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: request.ctx,
                    sema: request.sema,
                    interner: request.interner
                ).filter { candidate in
                    guard isIntRangeCrossTypeContainsCandidate(candidate, sema: request.sema),
                          request.args.count == 1,
                          argTypes.count == 1,
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes[0] == argTypes[0]
                    else {
                        return false
                    }
                    guard let label = request.args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = request.sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else if request.calleeName == request.knownNames.contains,
                      let rangeSourceMemberLookupType,
                      rangeReceiverKind == .uintRange
            {
                collectScopedRangeUserExtensionCandidates(
                    named: request.calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: request.ctx,
                    sema: request.sema,
                    interner: request.interner
                ).filter { candidate in
                    guard isUIntRangeCrossTypeContainsCandidate(candidate, sema: request.sema),
                          request.args.count == 1,
                          argTypes.count == 1,
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes[0] == argTypes[0]
                    else {
                        return false
                    }
                    guard let label = request.args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = request.sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else if request.calleeName == request.knownNames.contains,
                      let rangeSourceMemberLookupType,
                      rangeReceiverKind == .longRange,
                      !isLongRangeLiteralContainsCall
            {
                collectScopedRangeUserExtensionCandidates(
                    named: request.calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: request.ctx,
                    sema: request.sema,
                    interner: request.interner
                ).filter { candidate in
                    guard request.args.count == 1,
                          argTypes.count == 1,
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == 1,
                          signature.parameterTypes[0] == argTypes[0],
                          [request.sema.types.byteType, request.sema.types.intType, request.sema.types.shortType]
                              .contains(signature.parameterTypes[0])
                    else {
                        return false
                    }
                    guard let label = request.args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = request.sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else {
                []
            }
            let bundledStdlibCandidates = collectBundledStdlibExtensionCandidates(
                named: request.calleeName,
                receiverType: memberLookupType,
                sourceFile: request.ctx.currentASTFile,
                sema: request.sema,
                interner: request.interner
            )
            let instantValueSemanticsCandidates = collectInstantValueSemanticsCandidates(
                named: request.calleeName,
                receiverType: memberLookupType,
                sema: request.sema,
                interner: request.interner
            )
            let primitiveArraySourceCandidates = collectPrimitiveArraySourceMembers(
                named: request.calleeName,
                receiverType: memberLookupType,
                sema: request.sema,
                interner: request.interner
            )
            let arrayConversionSourceCandidates = collectArraySourceBackedCandidates(
                named: request.calleeName,
                receiverType: memberLookupType,
                arguments: request.args,
                ctx: request.ctx,
                sema: request.sema,
                interner: request.interner
            )
            var mutableMapPutAllSourceCandidates: [SymbolID] = []
            if request.calleeName == request.knownNames.putAll,
               ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType),
               request.args.count == 1,
               let argumentType = argTypes.first,
               !ReceiverClassifier(sema: request.sema, interner: request.interner).isMapLikeCollectionType(argumentType)
            {
                let argumentExpr = request.args[0].expr
                let isArrayArgument = ReceiverClassifier(sema: request.sema, interner: request.interner)
                    .isArrayLikeReceiver(receiverID: argumentExpr)
                let isSequenceArgument = ReceiverClassifier(sema: request.sema, interner: request.interner)
                    .isSequenceLikeType(argumentType)
                mutableMapPutAllSourceCandidates = request.sema.symbols.lookupAll(
                    fqName: request.knownNames.kotlinCollectionsPackage + [request.calleeName]
                ).filter { candidate in
                    guard let candidateSymbol = request.sema.symbols.symbol(candidate),
                          candidateSymbol.kind == .function,
                          (!candidateSymbol.flags.contains(.synthetic)
                              || request.sema.symbols.isSourceBackedSymbol(candidate)),
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          let receiver = signature.receiverType,
                          signature.parameterTypes.count == 1,
                          let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                          let receiverInfo = request.sema.symbols.symbol(receiverSymbol),
                          let parameterSymbol = driver.helpers.nominalSymbol(
                              of: signature.parameterTypes[0], types: request.sema.types
                          ),
                          let parameterInfo = request.sema.symbols.symbol(parameterSymbol)
                    else {
                        return false
                    }
                    guard receiverInfo.fqName == request.knownNames.kotlinCollectionsMutableMapFQName else {
                        return false
                    }
                    if isArrayArgument {
                        return parameterInfo.fqName == request.knownNames.kotlinArrayFQName
                    }
                    if isSequenceArgument {
                        return parameterInfo.fqName == request.knownNames.kotlinSequenceFQName
                    }
                    return parameterInfo.fqName == request.knownNames.kotlinCollectionsIterableFQName
                }
            }
            let standardMemberCandidates: [SymbolID]
            let workerMemberCandidates = collectWorkerMemberCandidates(
                named: request.calleeName, receiverType: memberLookupType, sema: request.sema, interner: request.interner
            )
            if !workerMemberCandidates.isEmpty {
                standardMemberCandidates = workerMemberCandidates
            } else if !arrayConversionSourceCandidates.isEmpty {
                standardMemberCandidates = arrayConversionSourceCandidates
            } else if !mutableMapPutAllSourceCandidates.isEmpty {
                standardMemberCandidates = mutableMapPutAllSourceCandidates
            } else if !primitiveArraySourceCandidates.isEmpty {
                // Primitive-array source members are bundled Kotlin extensions. Prefer the
                // exact source receiver over synthetic member stubs, including
                // joinToString(transform), whose legacy stub shares the same name.
                standardMemberCandidates = primitiveArraySourceCandidates
            } else if !scopedRangeUserCandidates.isEmpty {
                standardMemberCandidates = scopedRangeUserCandidates
            } else if !rangeSourceCandidates.isEmpty {
                standardMemberCandidates = rangeSourceCandidates
            } else if !instantValueSemanticsCandidates.isEmpty {
                // Instant's source-backed value-semantics extensions intentionally
                // replace inherited Any members for a statically typed Instant.
                // Without this preference, the nominal source shell makes
                // Any.equals/hashCode/toString win before extension fallback.
                standardMemberCandidates = instantValueSemanticsCandidates
            } else if !bundledStdlibCandidates.isEmpty {
                // Source-backed bundled declarations are the live implementation
                // for migrated atomic APIs and should win over residual synthetic
                // candidates such as inherited Any members.
                standardMemberCandidates = bundledStdlibCandidates
            } else {
                standardMemberCandidates = driver.helpers.collectMemberFunctionCandidates(
                    named: request.calleeName,
                    receiverType: memberLookupType,
                    sema: request.sema,
                    allowedOwnerSymbols: allowedOwnerSymbols,
                    interner: request.interner
                )
            }
            // Duration.toString(DurationUnit, Int) is a bundled source extension
            // that overloads Duration's ordinary zero-argument toString member.
            // Keep the source extension in the same candidate set when a member
            // with the same name already exists; otherwise the non-empty argument
            // call would stop at the zero-argument member and never reach the
            // normal extension fallback.
            let sourceBackedOverloads: [SymbolID] = {
                let memberName = request.interner.resolve(request.calleeName)
                // kotlinx.io.bytestring Base64 codec functions are bundled source
                // extensions whose first parameter is ByteString, disjoint from
                // every same-named kotlin.io.encoding.Base64 member's
                // ByteArray/CharSequence source, so merging them is unambiguous.
                guard memberName == "toString" || memberName == "replace"
                    || memberName == "encode" || memberName == "decode"
                    || memberName == "encodeToByteArray" || memberName == "encodeIntoByteArray"
                    || memberName == "decodeIntoByteArray" || memberName == "encodeToAppendable"
                else {
                    return []
                }
                if memberName == "toString" {
                    guard !request.args.isEmpty else { return [] }
                } else if memberName == "replace" {
                    guard request.args.count == 2,
                          request.ast.arena.expr(request.args[1].expr)?.isLambdaOrCallableRef == true
                    else {
                        return []
                    }
                }
                let receiverForExtensionLookup = request.sema.types.makeNonNullable(memberLookupType)
                return request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                    guard request.sema.symbols.isSourceBackedSymbol(candidate),
                          let symbol = request.sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          signature.parameterTypes.count >= request.args.count
                    else {
                        return false
                    }
                    guard extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: receiverForExtensionLookup,
                        declaredReceiver: declaredReceiver,
                        sema: request.sema
                    ) else {
                        return false
                    }
                    if memberName != "replace" {
                        return true
                    }

                    // String has a legacy member-shaped `replace(Regex, String)`
                    // candidate. Keep the bundled CharSequence transform overload
                    // beside it so its function parameter supplies the lambda's
                    // implicit `it` type before overload resolution rejects the
                    // String replacement candidate.
                    let knownNames = KnownCompilerNames(interner: request.interner)
                    func isNominalType(_ type: TypeID, fqName: [InternedString]) -> Bool {
                        guard let nominal = driver.helpers.nominalSymbol(of: type, types: request.sema.types),
                              let symbol = request.sema.symbols.symbol(nominal)
                        else {
                            return false
                        }
                        return symbol.fqName == fqName
                    }
                    guard request.args.count == 2,
                          signature.parameterTypes.count == 2,
                          isNominalType(declaredReceiver, fqName: knownNames.kotlinCharSequenceFQName),
                          isNominalType(signature.parameterTypes[0], fqName: knownNames.kotlinRegexFQName),
                          case let .functionType(transformType) = request.sema.types.kind(
                              of: request.sema.types.makeNonNullable(signature.parameterTypes[1])
                          ),
                          transformType.params.count == 1,
                          isNominalType(transformType.params[0], fqName: knownNames.kotlinTextMatchResultFQName),
                          isNominalType(transformType.returnType, fqName: knownNames.kotlinCharSequenceFQName)
                    else {
                        return false
                    }
                    return true
                }
            }()
            // Imported extensions can be reached both through the explicit
            // source-backed overload path above and through ordinary member
            // collection after the compact index restores their receiver
            // owner. Keep one instance of the same symbol so overload
            // resolution does not report a self-ambiguity.
            var seenMemberCandidates: Set<SymbolID> = []
            let unfilteredMemberCandidates = (sourceBackedOverloads + standardMemberCandidates).filter {
                seenMemberCandidates.insert($0).inserted
                    && primitiveCompareToCandidateMatches(
                        $0, calleeName: request.calleeName, receiverType: memberLookupType,
                        argTypes: argTypes, sema: request.sema
                    )
            }
            // An applicable reflective callBy already returned from its contextual
            // fast path. Let the ordinary extension lookup try both function and
            // KFunction receiver views when that member was inapplicable.
            let inapplicableReflectiveCallBy = callableReferenceFunctionType != nil
                && request.calleeName == request.knownNames.callBy
                ? request.sema.symbols.lookup(fqName: ["kotlin", "reflect", "KCallable", "callBy"].map(request.interner.intern)) : nil
            // Infix eligibility precedes the member/extension priority decision.
            let memberCandidates = unfilteredMemberCandidates.filter {
                $0 != inapplicableReflectiveCallBy
                    && (!request.ast.arena.isExplicitCall(request.id) || !isSyntheticCharPropertyFacadeFunction($0, ctx: request.ctx))
                    && (!request.ast.arena.isInfixCall(request.id) || request.sema.symbols.symbol($0)?.flags.contains(.infixFunction) == true)
            }
            // KUU-4345: for primitive receivers the member probe also surfaces
            // kotlin/kotlin.ranges/kotlin.text package extensions as
            // pseudo-members. Those are really default-import-tier extensions,
            // so a scope-visible extension (same package, explicit or wildcard
            // import) must outrank them. When every member candidate is such a
            // package-parented pseudo-member, resolve through the ordinary
            // extension path instead; it yields the same candidates when
            // nothing nearer applies.
            let effectiveMemberCandidates: [SymbolID] = {
                let primitiveProbePackages: [[InternedString]] = [
                    [request.knownNames.kotlin],
                    request.knownNames.kotlinRangesPackage,
                    request.knownNames.kotlinTextPackage,
                ]
                func isPrimitiveProbePseudoMember(_ candidate: SymbolID) -> Bool {
                    guard let parent = request.sema.symbols.parentSymbol(for: candidate),
                          let parentSymbol = request.sema.symbols.symbol(parent),
                          parentSymbol.kind == .package,
                          request.sema.symbols.functionSignature(for: candidate)?.receiverType != nil
                    else {
                        return false
                    }
                    return primitiveProbePackages.contains(parentSymbol.fqName)
                }
                guard !memberCandidates.isEmpty,
                      !isSuperCall,
                      memberCandidates.allSatisfy(isPrimitiveProbePseudoMember)
                else {
                    return memberCandidates
                }
                let scopedExtensionCandidates = collectExtensionCallCandidates(
                    named: request.calleeName,
                    memberLookupType: memberLookupType,
                    isSuperCall: isSuperCall,
                    supertypeSymbols: supertypeSymbols,
                    ctx: request.ctx,
                    locals: locals,
                    sema: request.sema,
                    interner: request.interner,
                    callShapeMatches: {
                        self.extensionCandidateMatchesCallShape(
                            $0, request: request, argumentTypes: argTypes, receiverType: memberLookupType
                        )
                    },
                    requiresInfix: request.ast.arena.isInfixCall(request.id)
                )
                // A nearer-scope extension only shadows the pseudo-members
                // when it can actually apply to this call; an inapplicable
                // same-named declaration must not hide the bundled overload
                // (matches kotlinc, which keeps resolving lower tiers).
                let applicableScopedCandidates = scopedExtensionCandidates.filter {
                    self.extensionCandidateMatchesCallShape(
                        $0, request: request, argumentTypes: argTypes, receiverType: memberLookupType
                    )
                }
                return applicableScopedCandidates.isEmpty ? memberCandidates : applicableScopedCandidates
            }()
            if !effectiveMemberCandidates.isEmpty {
                // Check if the found candidates belong to a companion object so we
                // can supply the correct implicit receiver type later.
                if let first = effectiveMemberCandidates.first,
                   let parentSymbol = request.sema.symbols.parentSymbol(for: first),
                   let ownerNominal = driver.helpers.nominalSymbol(of: memberLookupType, types: request.sema.types),
                   parentSymbol != ownerNominal,
                   request.sema.symbols.companionObjectSymbol(for: ownerNominal) == parentSymbol
                {
                    companionReceiverType = request.sema.types.make(.classType(ClassType(classSymbol: parentSymbol, args: [], nullability: .nonNull)))
                }
                allCandidates = effectiveMemberCandidates
            } else {
                let innerCtorCandidates = driver.helpers.collectInnerClassConstructorCandidates(
                    named: request.calleeName,
                    receiverType: memberLookupType,
                    sema: request.sema,
                    interner: request.interner
                )
                if !innerCtorCandidates.isEmpty {
                    allCandidates = innerCtorCandidates
                } else if let aliasConstructors = driver.helpers.collectInnerClassTypeAliasConstructorCandidates(
                    named: request.calleeName,
                    receiverType: memberLookupType,
                    explicitTypeArgs: request.explicitTypeArgs,
                    ctx: request.ctx,
                    interner: request.interner
                ) {
                    allCandidates = aliasConstructors.candidates
                    typeAliasConstructor = aliasConstructors.typeAliasConstructor
                } else {
                    if let callableReferenceFunctionType {
                        // A callable reference is both a reflective KFunction and an
                        // invokable function value. Resolve generic extensions such as
                        // `let` against its structural function type first so the inferred
                        // receiver type retains its parameter list. Reflection-specific
                        // extensions still use the KFunction lookup below as a fallback.
                        allCandidates = collectExtensionCallCandidates(
                            named: request.calleeName,
                            memberLookupType: callableReferenceFunctionType,
                            isSuperCall: isSuperCall,
                            supertypeSymbols: supertypeSymbols,
                            ctx: request.ctx,
                            locals: locals,
                            sema: request.sema,
                            interner: request.interner,
                            callShapeMatches: {
                                self.extensionCandidateMatchesCallShape(
                                    $0, request: request, argumentTypes: argTypes,
                                    receiverType: callableReferenceFunctionType
                                )
                            },
                            requiresInfix: request.ast.arena.isInfixCall(request.id)
                        )
                    } else {
                        allCandidates = []
                    }
                    if allCandidates.isEmpty {
                        allCandidates = collectExtensionCallCandidates(
                            named: request.calleeName,
                            memberLookupType: memberLookupType,
                            isSuperCall: isSuperCall,
                            supertypeSymbols: supertypeSymbols,
                            ctx: request.ctx,
                            locals: locals,
                            sema: request.sema,
                            interner: request.interner,
                            callShapeMatches: {
                                self.extensionCandidateMatchesCallShape(
                                    $0, request: request, argumentTypes: argTypes, receiverType: memberLookupType
                                )
                            },
                            requiresInfix: request.ast.arena.isInfixCall(request.id)
                        )
                    }
                }
            }
        }
        if request.ast.arena.isExplicitCall(request.id) {
            allCandidates.removeAll { isSyntheticCharPropertyFacadeFunction($0, ctx: request.ctx) }
        }
        // With no visible extension, retain the member for ordinary mismatch
        // diagnostics instead of accepting an invalid parameter map.
        if allCandidates.isEmpty,
           callableReferenceFunctionType != nil,
           request.calleeName == request.knownNames.callBy,
           let member = request.sema.symbols.lookup(fqName: ["kotlin", "reflect", "KCallable", "callBy"].map(request.interner.intern))
        {
            allCandidates = [member]
        }
        // If no infix callable exists, retain the ordinary lookup only for the
        // missing-modifier diagnostic enforced at the member-call entry point.
        // An existing but inapplicable infix candidate must never take this path.
        if request.ast.arena.isInfixCall(request.id), allCandidates.isEmpty {
            allCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: request.calleeName, receiverType: memberLookupType,
                sema: request.sema, interner: request.interner
            ).filter {
                primitiveCompareToCandidateMatches(
                    $0, calleeName: request.calleeName, receiverType: memberLookupType,
                    argTypes: argTypes, sema: request.sema
                )
            }
            if allCandidates.isEmpty {
                allCandidates = collectExtensionCallCandidates(
                    named: request.calleeName, memberLookupType: memberLookupType,
                    isSuperCall: isSuperCall, supertypeSymbols: supertypeSymbols,
                    ctx: request.ctx, locals: locals, sema: request.sema, interner: request.interner
                )
            }
        }
        // MutableMap.remove(key) has a source-backed projected-key overload in
        // addition to the retained interface member. Prefer the Kotlin source
        // declaration for ordinary MutableMap receiver calls while preserving
        // the synthetic member for interface and lowering bridges.
        if request.calleeName == request.knownNames.remove,
           ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType),
           request.args.count == 1
        {
            let mutableMapRemoveCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                guard let candidateSymbol = request.sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || request.sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                      let symbol = request.sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == request.knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapRemoveCandidates.isEmpty {
                allCandidates = mutableMapRemoveCandidates
            }
        }
        // A mutable map has a source-backed iterator overload whose return type
        // is MutableIterator<MutableMap.MutableEntry<K, V>>. If the inherited
        // synthetic collection surface won the initial lookup, prefer the
        // exact bundled extension before ordinary overload resolution.
        if request.calleeName == request.knownNames.iterator,
           ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType)
        {
            let mutableMapIteratorCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                guard request.sema.symbols.isSourceBackedSymbol(candidate),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                      let symbol = request.sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == request.knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapIteratorCandidates.isEmpty {
                allCandidates = mutableMapIteratorCandidates
            }
        }
        // `MutableMap.getValue(key)` is the read-only Map extension. The
        // MutableMap delegated accessor has the same short name but requires
        // `(thisRef, KProperty<*>)`; keep that two-argument delegate surface
        // out of ordinary one-argument member calls.
        if request.calleeName == request.knownNames.getValue,
           ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType),
           request.args.count == 1
        {
            let mapGetValueCandidates = request.sema.symbols.lookupByShortName(request.calleeName).filter { candidate in
                guard let candidateSymbol = request.sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || request.sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = request.sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: request.sema.types),
                      let symbol = request.sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == request.knownNames.kotlinCollectionsMapFQName
            }
            if !mapGetValueCandidates.isEmpty {
                allCandidates = mapGetValueCandidates
            }
        }

        return (allCandidates, companionReceiverType, nil)
    }

    private func companionBlockSymbol(
        for owner: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> SymbolID? {
        sema.symbols.companionBlockObjectSymbol(for: owner, interner: interner)
    }

    func companionExtensionFunctionCandidates(
        named name: InternedString,
        ownerReceiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        var candidates = ctx.cachedScopeLookup(name)
        // Name-indexed companion extension decls replace a per-call scan of
        // every file's `topLevelDecls` (same order, built once per module).
        for symbol in driver.companionExtensionFunctionDeclsByName[name] ?? []
        where !candidates.contains(symbol) {
            candidates.append(symbol)
        }
        return candidates.filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
                  sema.symbols.isFilePrivateTopLevelVisible(symbol, fileID: ctx.currentFileID),
                  isCompanionExtension(candidate, ctx: ctx),
                  let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType
            else {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: ownerReceiverType,
                declaredReceiver: receiver,
                sema: sema
            )
        }
    }

    /// Whether the symbol is declared by a `companion`-marked top-level
    /// extension (`companion fun A.f` / `companion val A.x`) — the only
    /// extension declarations reachable through the owner class-name's
    /// companion scope.
    func isCompanionExtension(_ symbolID: SymbolID, ctx: TypeInferenceContext) -> Bool {
        guard let symbol = ctx.sema.symbols.symbol(symbolID),
              let sourceFileID = symbol.declSite?.start.file,
              let file = ctx.ast.file(for: sourceFileID)
        else {
            return false
        }
        for declID in file.topLevelDecls {
            guard let decl = ctx.ast.arena.decl(declID) else { continue }
            switch decl {
            case let .funDecl(funDecl) where funDecl.range == symbol.declSite:
                return funDecl.modifiers.contains(.companion) && funDecl.receiverType != nil
            case let .propertyDecl(propertyDecl) where propertyDecl.range == symbol.declSite:
                return propertyDecl.modifiers.contains(.companion) && propertyDecl.receiverType != nil
            default:
                continue
            }
        }
        return false
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
