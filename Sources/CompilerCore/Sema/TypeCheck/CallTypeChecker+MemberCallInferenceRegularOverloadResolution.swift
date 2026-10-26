// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// The collection, Comparator and callable-property scope-priority
    /// fallbacks must run before lambda argument preparation.
    /// `earlyReturnType` carries a bound result when a fallback handles the call.
    func selectRegularMemberCallReceiverAndFallbacks(
        _ request: MemberCallInferenceRequest,
        candidates: [SymbolID],
        argTypes: [TypeID],
        isClassNameReceiver: Bool,
        isSuperCall: Bool,
        companionReceiverType: TypeID?,
        rangeSourceMemberLookupType: TypeID?,
        rangeExtensionLookupType: TypeID?,
        callableReferenceFunctionType: TypeID?,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        locals: inout LocalBindings
    ) -> (effectiveReceiverType: TypeID, earlyReturnType: TypeID?) {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let ctx = request.ctx
        let expectedType = request.expectedType
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        let mutableMapSuperReceiverType: TypeID? = {
            guard isSuperCall,
                  [interner.intern("put"), knownNames.putAll, knownNames.remove, knownNames.clear].contains(calleeName),
                  let currentType = ctx.implicitReceiverType,
                  case let .classType(current) = sema.types.kind(of: currentType),
                  case let .classType(superclass) = sema.types.kind(of: lookupReceiverType),
                  let mutableMap = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsMutableMapFQName),
                  sema.types.isNominalSubtypeSymbol(superclass.classSymbol, of: mutableMap),
                  let arguments = sema.types.liftedNominalSupertypeArgs(
                      from: current.classSymbol, childArgs: current.args, to: superclass.classSymbol
                  )
            else { return nil }
            return sema.types.make(.classType(ClassType(classSymbol: superclass.classSymbol, args: arguments)))
        }()
        let callableReferenceExtensionReceiverType: TypeID? = {
            guard let callableReferenceFunctionType,
                  candidates.contains(where: { candidate in
                      guard let signature = sema.symbols.functionSignature(for: candidate),
                            let receiver = signature.receiverType
                      else {
                          return false
                      }
                      switch sema.types.kind(of: sema.types.makeNonNullable(receiver)) {
                      case .functionType:
                          return true
                      case let .typeParam(parameter):
                          // A generic extension such as `fun <T> T.let(...)`
                          // must infer T from the structural function type of a
                          // bound callable reference. Lookup uses its KFunction
                          // view for reflection, but that nominal view cannot be
                          // invoked from the extension's callback parameter.
                          return signature.typeParameterSymbols.contains(parameter.symbol)

                      default:
                          return false
                      }
                  })
            else {
                return nil
            }
            return callableReferenceFunctionType
        }()
        let resolvedLookupReceiverType = resolvedBuilderInferenceType(lookupReceiverType, ctx: ctx)
        let effectiveReceiverType = companionReceiverType
            ?? mutableMapSuperReceiverType
            ?? rangeSourceMemberLookupType
            ?? rangeExtensionLookupType
            ?? callableReferenceExtensionReceiverType
            ?? resolvedLookupReceiverType
        // STDLIB-pipeline §5: take/drop/chunked/windowed have real require()
        // validation in SequenceWindowChunk.kt as of MIGRATION-SEQ-005. When
        // normal candidate lookup already resolved one of these names to that
        // source declaration, the synthetic collection-member fallback below
        // must not discard it — Kotlin-source candidates take priority over
        // the synthetic shortcut so chosenCallee binds to the real
        // declaration and its require() executes.
        //
        // Excludes calls with a trailing HOF lambda (chunked(size) { ... },
        // windowed(size, step) { ... }): tryCollectionMemberFallback below
        // derives the transform overload's result element type from the
        // lambda body's inferred return type (see
        // CallTypeChecker+CollectionMemberFallback.swift), which the generic
        // overload resolver cannot reproduce and fails with conflicting type
        // variable bounds. Those overloads keep going through the synthetic
        // fallback and their require() bypass is tracked separately.
        let hasTrailingLambdaArg = args.last.map { ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false
        // STDLIB-pipeline §5 / KSP-441: Source-backed Sequence transforms
        // (map, filter, etc.) must bind to the real Kotlin declaration so the
        // object-expression pipeline runs instead of a `kk_*` runtime shortcut.
        let memberNameText = interner.resolve(calleeName)
        let isMutableMapIteratorSource = memberNameText == "iterator"
            && ReceiverClassifier(sema: sema, interner: interner).isMutableMapType(memberLookupType)
        // MutableSet inherits independent Set.iterator and MutableIterable.iterator
        // candidates. Keep the mutable-aware collection fallback when lookup is
        // ambiguous, while a unique source member retains normal dispatch.
        let isUniqueIteratorSource = memberNameText == "iterator" && candidates.count == 1
        let isListSourceBackedMember: Bool = {
            guard ["get", "indexOf", "lastIndexOf", "subList"].contains(memberNameText),
                  // `lookup(fqName:)` can return the `List(size, init)` factory
                  // function that shares this fqName; `lookupNominal` keeps the
                  // interface so the subtype check compares nominal owners.
                  let listOwner = sema.symbols.lookupNominal(fqName: knownNames.kotlinCollectionsListFQName)
            else { return false }
            return driver.helpers.allNominalSymbols(of: memberLookupType, types: sema.types, symbols: sema.symbols).contains {
                sema.types.isNominalSubtypeSymbol($0, of: listOwner)
            }
        }()
        // KSP-687 resolves Array.joinToString through the dedicated primitive
        // and generic-array source candidates. KSP-429's broad trailing-lambda
        // gate is for List/Iterable source calls; applying it to Array receivers
        // prevents the array resolver from binding the source overload.
        let isArrayJoinToString = memberNameText == "joinToString"
            && isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
        let isArraySourceBackedMember = isArrayLikeReceiver(receiverID: receiverID, sema: sema, interner: interner)
            && !collectArraySourceBackedCandidates(
                named: calleeName,
                receiverType: memberLookupType,
                ctx: ctx,
                sema: sema,
                interner: interner
            ).isEmpty
        let isSourceBackedMemberName = (calleeName == knownNames.zip
            && isSequenceLikeType(lookupReceiverType, sema: sema, interner: interner))
            || Self.sourceBackedCollectionMemberNames.contains(memberNameText)
            || (Self.sourceBackedTrailingLambdaMemberNames.contains(memberNameText) && !isArrayJoinToString)
            || isArraySourceBackedMember
            || isMutableMapIteratorSource
            || isUniqueIteratorSource
            || isListSourceBackedMember
        // Keep user bulk extensions ahead of the bundled fallback. JVM List
        // and Collection overloads use the same source binding as MutableSet.
        let bulkReceiverFQName = sema.requiresResolvedLibraryCalls
            ? knownNames.kotlinCollectionsMutableCollectionFQName : knownNames.kotlinCollectionsMutableSetFQName
        let isMutableBulkCall = (calleeName == knownNames.addAll || sema.requiresResolvedLibraryCalls && calleeName == knownNames.removeAll)
            && sema.symbols.lookup(fqName: bulkReceiverFQName).map { owner in
                driver.helpers.allNominalSymbols(of: lookupReceiverType, types: sema.types, symbols: sema.symbols).contains {
                    sema.types.isNominalSubtypeSymbol($0, of: owner)
                }
            } == true
        // Ordinary lookup remains member-only until those members fail. Include
        // visible extensions here so they reach the normal shadowed-extension
        // resolver instead of being replaced by the stdlib fallback first.
        let bulkExtensionCandidates = isMutableBulkCall ? collectExtensionCallCandidates(
            named: calleeName,
            memberLookupType: memberLookupType,
            isSuperCall: isSuperCall,
            supertypeSymbols: [],
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: interner
        ) : []
        let (visibleBulkExtensions, _) = ctx.filterByVisibility(bulkExtensionCandidates)
        let hasUserBulkCandidate = isMutableBulkCall && (candidates + visibleBulkExtensions).contains { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  sema.symbols.isSourceBackedSymbol(candidate),
                  !symbol.fqName.starts(with: knownNames.kotlinCollectionsPackage),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let declaredReceiver = signature.receiverType
            else { return false }
            let receiverSymbols = driver.helpers.allNominalSymbols(
                of: lookupReceiverType, types: sema.types, symbols: sema.symbols
            )
            let declaredReceiverSymbols = driver.helpers.allNominalSymbols(
                of: declaredReceiver, types: sema.types, symbols: sema.symbols
            )
            return receiverSymbols.contains { actual in
                declaredReceiverSymbols.contains { declared in
                    sema.types.isNominalSubtypeSymbol(actual, of: declared)
                }
            }
        }
        let hasSourceBackedCandidate = hasUserBulkCandidate || isSourceBackedMemberName
            && (isArraySourceBackedMember || !Self.sourceBackedCollectionMemberNames.contains(memberNameText) || !hasTrailingLambdaArg)
            && candidates.contains { candidateID in
                sema.symbols.isSourceBackedSymbol(candidateID)
            }
        // Synthetic collection members need to short-circuit before the generic
        // overload resolver so their trailing-lambda expectations stay concrete.
        if !hasSourceBackedCandidate, let fallbackType = tryCollectionMemberFallback(
            id,
            calleeName: calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: safeCall,
            receiverID: receiverID,
            args: args,
            ctx: ctx,
            expectedType: expectedType,
            locals: &locals
        ) {
            return (effectiveReceiverType, fallbackType)
        }

        if let fallbackType = tryBindComparatorMemberFallback(
            id,
            calleeName: calleeName,
            safeCall: safeCall,
            receiverType: lookupReceiverType,
            args: args,
            ctx: ctx,
            locals: &locals
        ) {
            return (effectiveReceiverType, fallbackType)
        }
        // Scope/import priority precedes function-vs-property priority. Do this
        // before lambda preparation, which would otherwise infer a package
        // property's block as the implicitly imported T.apply receiver lambda.
        if !isClassNameReceiver, !isSuperCall,
           let functionPriority = candidates.map({ callableInvocationScopePriority($0, named: calleeName, ctx: ctx) }).min(),
           functionPriority > 0,
           let propertyType = tryInferCallableMemberPropertyInvocation(
               request, memberLookupType: memberLookupType, argTypes: argTypes,
               isClassNameReceiver: false, locals: &locals,
               maximumPropertyPriority: functionPriority - 1
           ) {
            return (effectiveReceiverType, propertyType)
        }

        return (effectiveReceiverType, nil)
    }

    /// `earlyReturnType` carries a bound result only for the ambiguity
    /// diagnostic that returns immediately.
    func prepareAndResolveRegularMemberCall(
        _ request: MemberCallInferenceRequest,
        candidates: [SymbolID],
        argTypes: [TypeID],
        effectiveReceiverType: TypeID,
        isClassNameReceiver: Bool,
        isSuperCall: Bool,
        companionReceiverType: TypeID?,
        isLongRangeLiteralContainsCall: Bool,
        isULongRangeLiteralContainsCall: Bool,
        typeAliasConstructor: TypeAliasConstructorContext?,
        locals: inout LocalBindings
    ) -> (candidates: [SymbolID], preparedArgs: PreparedCallArguments, resolved: ResolvedCall, earlyReturnType: TypeID?) {
        let id = request.id
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        var candidates = candidates
        let memberNameText = interner.resolve(calleeName)

        let hasNonNullFlowFact = if let reference = ctx.dataFlow.resolveStableReference(
            request.receiverID, locals: locals, ast: ast, sema: sema, interner: interner
        ), reference.isStable,
           let flow = ctx.flowState.includingMembers(from: locals)[reference.symbol]
        {
            flow.isStable && flow.nullability == .nonNull
        } else {
            false
        }
        // A safe call or stable non-null flow fact proves this receiver can use
        // the non-null view of its upper bounds during overload resolution.
        let receiverTypeForResolution: TypeID = {
            guard request.safeCall || hasNonNullFlowFact else { return effectiveReceiverType }

            let upperBounds: [TypeID] = switch sema.types.kind(of: effectiveReceiverType) {
            case let .typeParam(parameter):
                parameter.capture.map { [$0.upper] }
                    ?? sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
            case let .intersection(parts):
                parts.flatMap { part -> [TypeID] in
                    guard case let .typeParam(parameter) = sema.types.kind(of: part) else {
                        return []
                    }
                    return parameter.capture.map { [$0.upper] }
                        ?? sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
                }
            default:
                []
            }
            guard !upperBounds.isEmpty else { return effectiveReceiverType }
            let nonNullBounds = upperBounds.map(sema.types.makeNonNullable)
            return nonNullBounds.count == 1
                ? nonNullBounds[0]
                : sema.types.make(.intersection(nonNullBounds))
        }()

        var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in args.enumerated() {
            guard let argumentExpr = ast.arena.expr(argument.expr) else {
                continue
            }
            switch argumentExpr {
            case .lambdaLiteral, .callableRef:
                continue
            default:
                cachedNonLambdaArgTypes[index] = argTypes[index]
            }
        }
        var argumentExpectedTypeOverrides: [Int: TypeID] = [:]
        if isLongRangeLiteralContainsCall {
            argumentExpectedTypeOverrides[0] = sema.types.longType
        } else if isULongRangeLiteralContainsCall {
            argumentExpectedTypeOverrides[0] = sema.types.ulongType
        }
        let directArgumentExpectedTypeOverrides = argumentExpectedTypeOverrides
        let argumentContextTypeArgs = typeAliasConstructor.map {
            aliasConstructorArgumentContextTypes($0, explicitTypeArgs: explicitTypeArgs, sema: sema)
        } ?? explicitTypeArgs
        var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
        let expectedTypeHintIndices = prepareCallExprArgumentContexts(
            args: args,
            callRange: range,
            ctx: ctx,
            expectedType: expectedType,
            explicitTypeArgs: argumentContextTypeArgs,
            calleeName: calleeName,
            candidates: candidates,
            locals: locals,
            preInferredArgumentTypes: cachedNonLambdaArgTypes,
            withContextExpectedLambdaType: nil,
            expectedTypeOverrides: &argumentExpectedTypeOverrides,
            lambdaContextOverrides: &lambdaContextOverrides
        )
        let preparedArgs = prepareCallArguments(
            args: args,
            callRange: range,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            expectedTypeOverrides: argumentExpectedTypeOverrides,
            expectedTypeHintIndices: expectedTypeHintIndices,
            contextualCallResultType: ctx.isCallResultDiscarded && ctx.isUnitCoercionContext
                ? sema.types.unitType : expectedType,
            explicitTypeArgs: argumentContextTypeArgs,
            receiverType: effectiveReceiverType,
            lambdaContextOverrides: lambdaContextOverrides,
            ctx: ctx,
            locals: &locals
        )
        // Older imported stdlib artifacts may still expose a String callback
        // bridge alongside the bundled CharSequence declaration. Lambda
        // preparation intentionally erases return types while finding a shared
        // input shape, so prefer that compatibility bridge only when it is
        // actually present and applicable; bundled source continues through
        // the CharSequence declaration.
        if memberNameText == "replace",
           args.count == 2,
           sema.types.makeNonNullable(argTypes[0]) == sema.types.stringType,
           preparedArgs.lambdaLiteralIndices.contains(1),
           case let .functionType(lambdaType) = sema.types.kind(
               of: sema.types.makeNonNullable(preparedArgs.argTypes[1])
           ),
           sema.types.isSubtype(lambdaType.returnType, sema.types.stringType)
        {
            let regexStringBridgeCandidates = candidates.filter {
                sema.symbols.externalLinkName(for: $0) == "__kk_regex_replace_lambda"
            }
            if !regexStringBridgeCandidates.isEmpty {
                candidates = regexStringBridgeCandidates
            }
        }
        let isDeferredAwait = candidates.contains {
            sema.symbols.externalLinkName(for: $0) == "kk_kxmini_async_await"
        }
        let resolutionExpectedType = isDeferredAwait ? nil : expectedType
        // The nullable result of findAnnotation does not make its reified
        // annotation argument nullable. Keep ordinary lookup and bound checking.
        let resolutionTypeArgs: [TypeID]
        if explicitTypeArgs.isEmpty, candidates.count == 1,
           let candidate = candidates.first,
           sema.symbols.symbol(candidate)?.fqName == ["kotlin", "reflect", "full", "findAnnotation"].map(interner.intern),
           let expectedType,
           let bound = sema.symbols.functionSignature(for: candidate)?.typeParameterUpperBounds.first ?? nil {
            let expectedArgument = sema.types.makeNonNullable(expectedType)
            resolutionTypeArgs = [sema.types.isSubtype(bound, expectedArgument) ? bound : expectedArgument]
        } else {
            resolutionTypeArgs = explicitTypeArgs
        }
        let hasCandidatesBeforeNestedFiltering = !candidates.isEmpty
        let candidateSpecificNestedCallTypes = candidateSpecificNestedCallArgumentTypes(
            candidates: candidates,
            args: args,
            originalArgumentTypes: preparedArgs.argTypes,
            originalExpectedTypeOverrides: argumentExpectedTypeOverrides,
            explicitTypeArgs: resolutionTypeArgs,
            implicitReceiverType: receiverTypeForResolution,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            ctx: ctx,
            locals: locals
        )
        if let candidateSpecificNestedCallTypes {
            candidates.removeAll {
                candidateSpecificNestedCallTypes.inapplicableCandidates.contains($0)
            }
        }
        var selectedNestedCallTypes = candidateSpecificNestedCallTypes
        var resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: range,
            calleeName: calleeName,
            explicitTypeArgs: resolutionTypeArgs,
            typeAliasConstructor: typeAliasConstructor,
            expectedType: resolutionExpectedType,
            implicitReceiverType: receiverTypeForResolution,
            candidateArgumentTypes: candidateSpecificNestedCallTypes?.argumentTypesByCandidate ?? [:],
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: ctx
        )
        // Ambiguous applicable members retain precedence over extensions.
        if let diagnostic = resolved.diagnostic,
           diagnostic.code == "KSWIFTK-SEMA-0003"
        {
            // An unresolved receiver or argument already has the root diagnostic.
            let hasUnresolvedMemberInput = containsUnresolvedMemberDiagnostic(
                in: [request.receiverID] + args.map(\.expr),
                ast: ast,
                sema: sema
            )
            if !hasUnresolvedMemberInput {
                ctx.sema.diagnostics.emit(diagnostic)
            }
            return (candidates, preparedArgs, resolved, driver.helpers.bindAndReturnErrorType(id, sema: sema))
        }
        // A same-named member that cannot accept the call must not hide an
        // applicable extension. Only retried after ordinary resolution failed, so
        // a viable member (including range/lambda arguments whose provisional
        // types are unreliable before resolution) always keeps precedence.
        if resolved.diagnostic != nil,
           // Class-name receivers resolve through the companion object, so an
           // extension on a companion supertype (e.g. `Base64.encode` via
           // `Default`) must still be retried when an inherited member exists
           // but cannot accept the call.
           (!isClassNameReceiver || companionReceiverType != nil),
           !isSuperCall,
           !args.contains(where: { ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }),
           hasCandidatesBeforeNestedFiltering
        {
            let receiverForExtensionLookup = sema.types.makeNonNullable(effectiveReceiverType)
            func receiverMatchingExtensions(_ scopeCandidates: [SymbolID]) -> [SymbolID] {
                scopeCandidates.filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate),
                          symbol.kind == .function,
                          !ast.arena.isInfixCall(id) || symbol.flags.contains(.infixFunction),
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: sema.symbols)
                    else { return false }
                    let isUser = symbol.declSite.map {
                        driver.sourceManager?.origin(of: $0.start.file) == .user
                    } ?? false
                    guard isUser || sema.symbols.isSourceBackedSymbol(candidate),
                          ctx.visibilityChecker.isAccessible(
                              symbol,
                              fromFile: ctx.currentFileID,
                              enclosingClass: ctx.enclosingClassSymbol
                          )
                    else { return false }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: receiverForExtensionLookup,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                }
            }
            // Viable user extensions shadow outer bindings, not inapplicable ones.
            var extensionCandidates = receiverMatchingExtensions(ctx.scope.lookup(calleeName))
            if extensionCandidates.isEmpty || ctx.resolver.probeCall(
                candidates: extensionCandidates,
                call: CallExpr(range: range, calleeName: calleeName, args: zip(args, preparedArgs.argTypes).map { argument, type in
                    CallArg.source(argument, type: type, callRange: range, ast: ctx.ast)
                }, elvisLhsExpectedTypeHint: ctx.isElvisBranchExpectedTypeHint,
                   elvisRhsCallResultTypeHint: ctx.elvisRhsCallResultTypeHint),
                expectedType: expectedType,
                implicitReceiverType: receiverForExtensionLookup,
                ctx: ctx.sema
            ).viableCandidates.isEmpty {
                extensionCandidates = receiverMatchingExtensions(ctx.scope.lookupMergingChain(calleeName))
            }
            if !extensionCandidates.isEmpty {
                var extensionExpectedTypeOverrides = directArgumentExpectedTypeOverrides
                prepareUnambiguousNestedCallExpectedTypes(
                    args: args,
                    callRange: range,
                    candidates: extensionCandidates,
                    preInferredArgumentTypes: cachedNonLambdaArgTypes,
                    ctx: ctx,
                    locals: locals,
                    expectedTypeOverrides: &extensionExpectedTypeOverrides
                )
                let extensionArgs = prepareCallArguments(
                    args: args,
                    callRange: range,
                    candidates: extensionCandidates,
                    preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
                    expectedTypeOverrides: extensionExpectedTypeOverrides,
                    contextualCallResultType: ctx.isCallResultDiscarded && ctx.isUnitCoercionContext
                        ? sema.types.unitType : expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    receiverType: effectiveReceiverType,
                    ctx: ctx,
                    locals: &locals
                )
                let extensionNestedCallTypes = candidateSpecificNestedCallArgumentTypes(
                    candidates: extensionCandidates,
                    args: args,
                    originalArgumentTypes: extensionArgs.argTypes,
                    originalExpectedTypeOverrides: extensionExpectedTypeOverrides,
                    explicitTypeArgs: explicitTypeArgs,
                    implicitReceiverType: receiverTypeForResolution,
                    lambdaLiteralIndices: extensionArgs.lambdaLiteralIndices,
                    ctx: ctx,
                    locals: locals
                )
                if let extensionNestedCallTypes {
                    extensionCandidates.removeAll {
                        extensionNestedCallTypes.inapplicableCandidates.contains($0)
                    }
                }
                let retried = resolveCallRespectingLambdaReturnType(
                    candidates: extensionCandidates,
                    args: args,
                    argTypes: extensionArgs.argTypes,
                    range: range,
                    calleeName: calleeName,
                    explicitTypeArgs: explicitTypeArgs,
                    expectedType: expectedType,
                    implicitReceiverType: receiverTypeForResolution,
                    candidateArgumentTypes: extensionNestedCallTypes?.argumentTypesByCandidate ?? [:],
                    lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                    inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                    blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                    hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                    ctx: ctx
                )
                if retried.diagnostic == nil {
                    candidates = extensionCandidates
                    resolved = retried
                    selectedNestedCallTypes = extensionNestedCallTypes
                }
            }
        }

        if resolved.diagnostic == nil,
           let chosen = resolved.chosenCallee,
           let expectedTypes = selectedNestedCallTypes?.expectedTypesByCandidate[chosen]
        {
            for (index, expectedArgumentType) in expectedTypes.sorted(by: { $0.key < $1.key }) {
                let diagnosticsCheckpoint = sema.diagnostics.checkpoint()
                let argumentType = driver.inferExpr(
                    args[index].expr,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: expectedArgumentType
                )
                let emittedError = sema.diagnostics.diagnostics.dropFirst(diagnosticsCheckpoint).contains {
                    $0.severity == .error
                }
                if argumentType != sema.types.errorType,
                   !typeContainsErrorType(argumentType, sema: sema),
                   !emittedError,
                   let argumentRange = ast.arena.exprRange(args[index].expr)
                {
                    sema.diagnostics.removeErrorDiagnostics(containedIn: argumentRange)
                }
            }
        }

        return (candidates, preparedArgs, resolved, nil)
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
