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
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

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
                if let actualOwner = sema.symbols.actualSymbol(for: ownerNominal),
                   let blockCompanion = companionBlockSymbol(for: actualOwner, sema: sema, interner: interner)
                {
                    return blockCompanion
                }
                if let blockCompanion = companionBlockSymbol(for: ownerNominal, sema: sema, interner: interner) {
                    return blockCompanion
                }
                return nil
            }()
            let classNameReceiverSourceCompanionSymbol: SymbolID? = {
                guard let ownerNominal = classNameReceiverNominalSymbol else { return nil }
                if let actualOwner = sema.symbols.actualSymbol(for: ownerNominal),
                   let companion = sema.symbols.companionObjectSymbol(for: actualOwner)
                {
                    return companion
                }
                return sema.symbols.companionObjectSymbol(for: ownerNominal)
            }()
            let classNameReceiverCompanionSymbol = classNameReceiverBlockSymbol
                ?? classNameReceiverSourceCompanionSymbol
            let companionExtensionReceiverType = classNameReceiverNominalSymbol.flatMap { owner in
                sema.symbols.symbol(owner).map { _ in
                    sema.types.make(.classType(ClassType(
                        classSymbol: owner,
                        args: [],
                        nullability: .nonNull
                    )))
                }
            }
            if let companionSymbol = classNameReceiverCompanionSymbol {
                let companionTypeForExtensionLookup = sema.types.make(.classType(ClassType(classSymbol: companionSymbol, args: [], nullability: .nonNull)))

                // When args are present this is a function call, so skip the
                // property short-circuit to avoid shadowing a companion function
                // of the same name.
                if args.isEmpty {
                    let directPropertyReceivers = [
                        classNameReceiverBlockSymbol.map { ($0, companionTypeForExtensionLookup) },
                        classNameReceiverSourceCompanionSymbol.map { symbol in
                            (symbol, sema.types.make(.classType(ClassType(
                                classSymbol: symbol, args: [], nullability: .nonNull
                            ))))
                        },
                    ].compactMap { $0 }
                    let directProperty = directPropertyReceivers.first { _, receiverType in
                        driver.helpers.lookupMemberProperty(
                            named: calleeName,
                            receiverType: receiverType,
                            sema: sema
                        ) != nil
                    }.flatMap { _, receiverType in
                        driver.helpers.lookupMemberProperty(
                            named: calleeName,
                            receiverType: receiverType,
                            sema: sema
                        ).map { ($0, receiverType) }
                    }
                    if let (propResult, propertyReceiverType) = directProperty {
                        let propSymbol = propResult.symbol
                        let propType = propResult.type
                        if let propSym = sema.symbols.symbol(propSymbol),
                           !ctx.visibilityChecker.isAccessible(
                               propSym,
                               fromFile: ctx.currentFileID,
                               enclosingClass: ctx.enclosingClassSymbol
                           )
                        {
                            driver.helpers.emitVisibilityError(for: propSym, name: interner.resolve(calleeName), range: range, diagnostics: ctx.sema.diagnostics)
                            return ([], companionReceiverType, driver.helpers.bindAndReturnErrorType(id, sema: sema))
                        }
                        driver.helpers.checkDeprecation(
                            for: propSymbol,
                            sema: sema,
                            interner: interner,
                            range: range,
                            diagnostics: ctx.sema.diagnostics
                        )
                        driver.helpers.checkOptIn(
                            for: propSymbol,
                            ctx: ctx,
                            range: range,
                            diagnostics: ctx.sema.diagnostics
                        )
                        // Re-bind receiver to companion type for correct KIR lowering
                        sema.bindings.bindExprType(receiverID, type: propertyReceiverType)
                        sema.bindings.bindIdentifier(id, symbol: propSymbol)
                        sema.bindings.bindExprType(id, type: propType)
                        return ([], companionReceiverType, propType)
                    }

                    if let sourceCompanion = classNameReceiverSourceCompanionSymbol,
                       sourceCompanion != classNameReceiverBlockSymbol
                    {
                        let sourceCompanionType = sema.types.make(.classType(ClassType(
                            classSymbol: sourceCompanion, args: [], nullability: .nonNull
                        )))
                        if let extensionPropertyType = resolveExtensionPropertyGetter(
                            id: id,
                            calleeName: calleeName,
                            range: range,
                            receiverType: sourceCompanionType,
                            expectedType: expectedType,
                            ctx: ctx
                        ) {
                            sema.bindings.bindExprType(receiverID, type: sourceCompanionType)
                            sema.bindings.bindExprType(id, type: extensionPropertyType)
                            return ([], sourceCompanionType, extensionPropertyType)
                        }
                    }
                    if let ownerReceiverType = companionExtensionReceiverType,
                       let extensionPropertyType = resolveExtensionPropertyGetter(
                           id: id,
                           calleeName: calleeName,
                           range: range,
                           receiverType: ownerReceiverType,
                           expectedType: expectedType,
                           ctx: ctx,
                           invocationCandidateFilter: { candidate in
                               self.isCompanionExtension(candidate, ctx: ctx)
                           }
                       )
                    {
                        companionReceiverType = ownerReceiverType
                        sema.bindings.bindExprType(receiverID, type: ownerReceiverType)
                        sema.bindings.bindExprType(id, type: extensionPropertyType)
                        return ([], companionReceiverType, extensionPropertyType)
                    }
                }

                // Then try companion function candidates
                var companionCandidates: [SymbolID] = []
                var selectedCompanionReceiverType: TypeID?
                if classNameReceiverBlockSymbol != nil {
                    companionCandidates = driver.helpers.collectMemberFunctionCandidates(
                        named: calleeName,
                        receiverType: companionTypeForExtensionLookup,
                        sema: sema,
                        interner: interner
                    )
                    if !companionCandidates.isEmpty {
                        selectedCompanionReceiverType = companionTypeForExtensionLookup
                    }
                }
                if companionCandidates.isEmpty,
                   let sourceCompanion = classNameReceiverSourceCompanionSymbol,
                   sourceCompanion != classNameReceiverBlockSymbol
                {
                    let sourceCompanionType = sema.types.make(.classType(ClassType(
                        classSymbol: sourceCompanion, args: [], nullability: .nonNull
                    )))
                    companionCandidates = driver.helpers.collectMemberFunctionCandidates(
                        named: calleeName,
                        receiverType: sourceCompanionType,
                        sema: sema,
                        interner: interner
                    )
                    if !companionCandidates.isEmpty {
                        selectedCompanionReceiverType = sourceCompanionType
                    }
                }
                if companionCandidates.isEmpty,
                   let ownerReceiverType = companionExtensionReceiverType
                {
                    companionCandidates = companionExtensionFunctionCandidates(
                        named: calleeName,
                        ownerReceiverType: ownerReceiverType,
                        ctx: ctx
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
                    sema.symbols.lookupByShortName(calleeName).filter { candidate in
                        guard let symbol = sema.symbols.symbol(candidate),
                              symbol.kind == .function,
                              symbol.flags.contains(.synthetic),
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else {
                            return false
                        }
                        guard self.isUnsignedRandomExtensionVisible(symbol, named: calleeName, ctx: ctx) else {
                            return false
                        }
                        return self.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: sema
                        )
                    }
                }
                if companionCandidates.isEmpty {
                    // Fall back to Companion-scoped extension functions
                    // (e.g. `fun Duration.Companion.parse(value: String): Duration`)
                    // written as Kotlin source at package scope. These are resolved
                    // via scope lookup (like ordinary extension functions), not the
                    // companion member lookup above.
                    companionCandidates = ctx.cachedScopeLookup(calleeName).filter { candidate in
                        guard let symbol = ctx.cachedSymbol(candidate),
                              symbol.kind == .function,
                              let signature = sema.symbols.functionSignature(for: candidate),
                              let recv = signature.receiverType
                        else { return false }
                        return extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: companionTypeForExtensionLookup,
                            declaredReceiver: recv,
                            sema: sema
                        )
                    }
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
                    sema.bindings.bindExprType(receiverID, type: selectedCompanionReceiverType)
                }
                allCandidates = companionCandidates
            } else {
                if let ownerReceiverType = companionExtensionReceiverType {
                    if args.isEmpty,
                       let extensionPropertyType = resolveExtensionPropertyGetter(
                           id: id,
                           calleeName: calleeName,
                           range: range,
                           receiverType: ownerReceiverType,
                           expectedType: expectedType,
                           ctx: ctx,
                           invocationCandidateFilter: { candidate in
                               self.isCompanionExtension(candidate, ctx: ctx)
                           }
                       )
                    {
                        companionReceiverType = ownerReceiverType
                        sema.bindings.bindExprType(receiverID, type: ownerReceiverType)
                        sema.bindings.bindExprType(id, type: extensionPropertyType)
                        return ([], companionReceiverType, extensionPropertyType)
                    }
                    allCandidates = companionExtensionFunctionCandidates(
                        named: calleeName,
                        ownerReceiverType: ownerReceiverType,
                        ctx: ctx
                    )
                    if !allCandidates.isEmpty {
                        companionReceiverType = ownerReceiverType
                        sema.bindings.bindExprType(receiverID, type: ownerReceiverType)
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
                    of: sema.types.makeNonNullable(sourceReceiverType),
                    types: sema.types
                ) else {
                    return false
                }
                return ctx.cachedScopeLookup(calleeName).contains { candidate in
                    guard let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          !symbol.flags.contains(.synthetic),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == args.count,
                          let declaredReceiver = signature.receiverType,
                          let declaredReceiverSymbol = driver.helpers.nominalSymbol(
                              of: sema.types.makeNonNullable(declaredReceiver),
                              types: sema.types
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
                        named: calleeName,
                        receiverType: $0,
                        sema: sema,
                        interner: interner
                    )
                } ?? []
            // Source-backed range overloads are recovered from the bundled
            // declaration index because their extensions are not generally
            // visible through member lookup. A same-named extension in the
            // active Kotlin scope still has normal overload priority, though;
            // keep it ahead of the bundled candidates so a user declaration
            // is not silently replaced by the stdlib fallback.
            let rangeReceiverKind = MemberRuntimeDispatch.rangeReceiverKind(
                receiverExpr: receiverID,
                receiverType: lookupReceiverType,
                sema: sema,
                interner: interner
            )
            let scopedRangeUserCandidates: [SymbolID] = if calleeName == knownNames.contains,
                                                               let rangeSourceMemberLookupType,
                                                               rangeReceiverKind == .intRange
            {
                collectScopedRangeUserExtensionCandidates(
                    named: calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard isIntRangeCrossTypeContainsCandidate(candidate, sema: sema),
                          args.count == 1,
                          argTypes.count == 1,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes[0] == argTypes[0]
                    else {
                        return false
                    }
                    guard let label = args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else if calleeName == knownNames.contains,
                      let rangeSourceMemberLookupType,
                      rangeReceiverKind == .uintRange
            {
                collectScopedRangeUserExtensionCandidates(
                    named: calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard isUIntRangeCrossTypeContainsCandidate(candidate, sema: sema),
                          args.count == 1,
                          argTypes.count == 1,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes[0] == argTypes[0]
                    else {
                        return false
                    }
                    guard let label = args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else if calleeName == knownNames.contains,
                      let rangeSourceMemberLookupType,
                      rangeReceiverKind == .longRange,
                      !isLongRangeLiteralContainsCall
            {
                collectScopedRangeUserExtensionCandidates(
                    named: calleeName,
                    receiverType: rangeSourceMemberLookupType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    guard args.count == 1,
                          argTypes.count == 1,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          signature.parameterTypes.count == 1,
                          signature.parameterTypes[0] == argTypes[0],
                          [sema.types.byteType, sema.types.intType, sema.types.shortType]
                              .contains(signature.parameterTypes[0])
                    else {
                        return false
                    }
                    guard let label = args[0].label else { return true }
                    guard signature.valueParameterSymbols.count == 1,
                          let parameter = sema.symbols.symbol(signature.valueParameterSymbols[0])
                    else {
                        return false
                    }
                    return parameter.name == label
                }
            } else {
                []
            }
            let bundledStdlibCandidates = collectBundledStdlibExtensionCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sourceFile: ctx.currentASTFile,
                sema: sema,
                interner: interner
            )
            let instantValueSemanticsCandidates = collectInstantValueSemanticsCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                interner: interner
            )
            let primitiveArraySourceCandidates = collectPrimitiveArraySourceMembers(
                named: calleeName,
                receiverType: memberLookupType,
                sema: sema,
                interner: interner
            )
            let arrayConversionSourceCandidates = collectArraySourceBackedCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                arguments: args,
                ctx: ctx,
                sema: sema,
                interner: interner
            )
            var mutableMapPutAllSourceCandidates: [SymbolID] = []
            if calleeName == knownNames.putAll,
               ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
               args.count == 1,
               let argumentType = argTypes.first,
               !ReceiverClassifier(sema: sema, interner: interner).isMapLikeCollectionType(argumentType)
            {
                let argumentExpr = args[0].expr
                let isArrayArgument = ReceiverClassifier(sema: sema, interner: interner)
                    .isArrayLikeReceiver(receiverID: argumentExpr)
                let isSequenceArgument = ReceiverClassifier(sema: sema, interner: interner)
                    .isSequenceLikeType(argumentType)
                mutableMapPutAllSourceCandidates = sema.symbols.lookupAll(
                    fqName: knownNames.kotlinCollectionsPackage + [calleeName]
                ).filter { candidate in
                    guard let candidateSymbol = sema.symbols.symbol(candidate),
                          candidateSymbol.kind == .function,
                          (!candidateSymbol.flags.contains(.synthetic)
                              || sema.symbols.isSourceBackedSymbol(candidate)),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let receiver = signature.receiverType,
                          signature.parameterTypes.count == 1,
                          let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                          let receiverInfo = sema.symbols.symbol(receiverSymbol),
                          let parameterSymbol = driver.helpers.nominalSymbol(
                              of: signature.parameterTypes[0], types: sema.types
                          ),
                          let parameterInfo = sema.symbols.symbol(parameterSymbol)
                    else {
                        return false
                    }
                    guard receiverInfo.fqName == knownNames.kotlinCollectionsMutableMapFQName else {
                        return false
                    }
                    if isArrayArgument {
                        return parameterInfo.fqName == knownNames.kotlinArrayFQName
                    }
                    if isSequenceArgument {
                        return parameterInfo.fqName == knownNames.kotlinSequenceFQName
                    }
                    return parameterInfo.fqName == knownNames.kotlinCollectionsIterableFQName
                }
            }
            let standardMemberCandidates: [SymbolID]
            let workerExecuteCandidates = collectWorkerExecuteMemberCandidates(
                named: calleeName, receiverType: memberLookupType, sema: sema, interner: interner
            )
            if !workerExecuteCandidates.isEmpty {
                standardMemberCandidates = workerExecuteCandidates
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
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    allowedOwnerSymbols: allowedOwnerSymbols,
                    interner: interner
                )
            }
            // Duration.toString(DurationUnit, Int) is a bundled source extension
            // that overloads Duration's ordinary zero-argument toString member.
            // Keep the source extension in the same candidate set when a member
            // with the same name already exists; otherwise the non-empty argument
            // call would stop at the zero-argument member and never reach the
            // normal extension fallback.
            let sourceBackedOverloads: [SymbolID] = {
                let memberName = interner.resolve(calleeName)
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
                    guard !args.isEmpty else { return [] }
                } else if memberName == "replace" {
                    guard args.count == 2,
                          ast.arena.expr(args[1].expr)?.isLambdaOrCallableRef == true
                    else {
                        return []
                    }
                }
                let receiverForExtensionLookup = sema.types.makeNonNullable(memberLookupType)
                return sema.symbols.lookupByShortName(calleeName).filter { candidate in
                    guard sema.symbols.isSourceBackedSymbol(candidate),
                          let symbol = sema.symbols.symbol(candidate),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          signature.parameterTypes.count >= args.count
                    else {
                        return false
                    }
                    guard extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: receiverForExtensionLookup,
                        declaredReceiver: declaredReceiver,
                        sema: sema
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
                    func isNominalType(_ type: TypeID, fqName: [String]) -> Bool {
                        guard let nominal = driver.helpers.nominalSymbol(of: type, types: sema.types),
                              let symbol = sema.symbols.symbol(nominal)
                        else {
                            return false
                        }
                        return symbol.fqName.map(interner.resolve) == fqName
                    }
                    guard args.count == 2,
                          signature.parameterTypes.count == 2,
                          isNominalType(declaredReceiver, fqName: ["kotlin", "CharSequence"]),
                          isNominalType(signature.parameterTypes[0], fqName: ["kotlin", "text", "Regex"]),
                          case let .functionType(transformType) = sema.types.kind(
                              of: sema.types.makeNonNullable(signature.parameterTypes[1])
                          ),
                          transformType.params.count == 1,
                          isNominalType(transformType.params[0], fqName: ["kotlin", "text", "MatchResult"]),
                          isNominalType(transformType.returnType, fqName: ["kotlin", "CharSequence"])
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
                        $0, calleeName: calleeName, receiverType: memberLookupType,
                        argTypes: argTypes, sema: sema
                    )
            }
            // An applicable reflective callBy already returned from its contextual
            // fast path. Let the ordinary extension lookup try both function and
            // KFunction receiver views when that member was inapplicable.
            let inapplicableReflectiveCallBy = callableReferenceFunctionType != nil
                && interner.resolve(calleeName) == "callBy"
                ? sema.symbols.lookup(fqName: ["kotlin", "reflect", "KCallable", "callBy"].map(interner.intern)) : nil
            // Infix eligibility precedes the member/extension priority decision.
            let memberCandidates = unfilteredMemberCandidates.filter {
                $0 != inapplicableReflectiveCallBy
                    && (!ast.arena.isExplicitCall(id) || !isSyntheticCharPropertyFacadeFunction($0, ctx: ctx))
                    && (!ast.arena.isInfixCall(id) || sema.symbols.symbol($0)?.flags.contains(.infixFunction) == true)
            }
            if !memberCandidates.isEmpty {
                // Check if the found candidates belong to a companion object so we
                // can supply the correct implicit receiver type later.
                if let first = memberCandidates.first,
                   let parentSymbol = sema.symbols.parentSymbol(for: first),
                   let ownerNominal = driver.helpers.nominalSymbol(of: memberLookupType, types: sema.types),
                   parentSymbol != ownerNominal,
                   sema.symbols.companionObjectSymbol(for: ownerNominal) == parentSymbol
                {
                    companionReceiverType = sema.types.make(.classType(ClassType(classSymbol: parentSymbol, args: [], nullability: .nonNull)))
                }
                allCandidates = memberCandidates
            } else {
                let innerCtorCandidates = driver.helpers.collectInnerClassConstructorCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    sema: sema,
                    interner: interner
                )
                if !innerCtorCandidates.isEmpty {
                    allCandidates = innerCtorCandidates
                } else if let aliasConstructors = driver.helpers.collectInnerClassTypeAliasConstructorCandidates(
                    named: calleeName,
                    receiverType: memberLookupType,
                    explicitTypeArgs: request.explicitTypeArgs,
                    ctx: ctx,
                    interner: interner
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
                            named: calleeName,
                            memberLookupType: callableReferenceFunctionType,
                            isSuperCall: isSuperCall,
                            supertypeSymbols: supertypeSymbols,
                            ctx: ctx,
                            locals: locals,
                            sema: sema,
                            interner: interner,
                            callShapeMatches: {
                                self.extensionCandidateMatchesCallShape(
                                    $0, request: request, argumentTypes: argTypes,
                                    receiverType: callableReferenceFunctionType
                                )
                            },
                            requiresInfix: ast.arena.isInfixCall(id)
                        )
                    } else {
                        allCandidates = []
                    }
                    if allCandidates.isEmpty {
                        allCandidates = collectExtensionCallCandidates(
                            named: calleeName,
                            memberLookupType: memberLookupType,
                            isSuperCall: isSuperCall,
                            supertypeSymbols: supertypeSymbols,
                            ctx: ctx,
                            locals: locals,
                            sema: sema,
                            interner: interner,
                            callShapeMatches: {
                                self.extensionCandidateMatchesCallShape(
                                    $0, request: request, argumentTypes: argTypes, receiverType: memberLookupType
                                )
                            },
                            requiresInfix: ast.arena.isInfixCall(id)
                        )
                    }
                }
            }
        }
        if ast.arena.isExplicitCall(id) {
            allCandidates.removeAll { isSyntheticCharPropertyFacadeFunction($0, ctx: ctx) }
        }
        // With no visible extension, retain the member for ordinary mismatch
        // diagnostics instead of accepting an invalid parameter map.
        if allCandidates.isEmpty,
           callableReferenceFunctionType != nil,
           interner.resolve(calleeName) == "callBy",
           let member = sema.symbols.lookup(fqName: ["kotlin", "reflect", "KCallable", "callBy"].map(interner.intern))
        {
            allCandidates = [member]
        }
        // If no infix callable exists, retain the ordinary lookup only for the
        // missing-modifier diagnostic enforced at the member-call entry point.
        // An existing but inapplicable infix candidate must never take this path.
        if ast.arena.isInfixCall(id), allCandidates.isEmpty {
            allCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName, receiverType: memberLookupType,
                sema: sema, interner: interner
            ).filter {
                primitiveCompareToCandidateMatches(
                    $0, calleeName: calleeName, receiverType: memberLookupType,
                    argTypes: argTypes, sema: sema
                )
            }
            if allCandidates.isEmpty {
                allCandidates = collectExtensionCallCandidates(
                    named: calleeName, memberLookupType: memberLookupType,
                    isSuperCall: isSuperCall, supertypeSymbols: supertypeSymbols,
                    ctx: ctx, locals: locals, sema: sema, interner: interner
                )
            }
        }
        // MutableMap.remove(key) has a source-backed projected-key overload in
        // addition to the retained interface member. Prefer the Kotlin source
        // declaration for ordinary MutableMap receiver calls while preserving
        // the synthetic member for interface and lowering bridges.
        if calleeName == knownNames.remove,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mutableMapRemoveCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMutableMapFQName
            }
            if !mutableMapRemoveCandidates.isEmpty {
                allCandidates = mutableMapRemoveCandidates
            }
        }
        // A mutable map has a source-backed iterator overload whose return type
        // is MutableIterator<MutableMap.MutableEntry<K, V>>. If the inherited
        // synthetic collection surface won the initial lookup, prefer the
        // exact bundled extension before ordinary overload resolution.
        if calleeName == knownNames.iterator,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        {
            let mutableMapIteratorCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
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
            if !mutableMapIteratorCandidates.isEmpty {
                allCandidates = mutableMapIteratorCandidates
            }
        }
        // `MutableMap.getValue(key)` is the read-only Map extension. The
        // MutableMap delegated accessor has the same short name but requires
        // `(thisRef, KProperty<*>)`; keep that two-argument delegate surface
        // out of ordinary one-argument member calls.
        if calleeName == knownNames.getValue,
           ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType),
           args.count == 1
        {
            let mapGetValueCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard let candidateSymbol = sema.symbols.symbol(candidate),
                      candidateSymbol.kind == .function,
                      (!candidateSymbol.flags.contains(.synthetic)
                          || sema.symbols.isSourceBackedSymbol(candidate)),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      signature.parameterTypes.count == 1,
                      let receiver = signature.receiverType,
                      let receiverSymbol = driver.helpers.nominalSymbol(of: receiver, types: sema.types),
                      let symbol = sema.symbols.symbol(receiverSymbol)
                else {
                    return false
                }
                return symbol.fqName == knownNames.kotlinCollectionsMapFQName
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
        for file in ctx.ast.files {
            for declID in file.topLevelDecls {
                guard case let .funDecl(function)? = ctx.ast.arena.decl(declID),
                      function.name == name,
                      function.modifiers.contains(.companion),
                      function.receiverType != nil,
                      let symbol = sema.bindings.declSymbols[declID],
                      !candidates.contains(symbol)
                else {
                    continue
                }
                candidates.append(symbol)
            }
        }
        return candidates.filter { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function,
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
