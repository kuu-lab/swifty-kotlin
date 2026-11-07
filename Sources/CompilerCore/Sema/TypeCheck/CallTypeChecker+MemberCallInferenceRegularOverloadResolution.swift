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

        let mutableMapSuperReceiverType: TypeID? = {
            guard isSuperCall,
                  [request.interner.intern("put"), request.knownNames.putAll, request.knownNames.remove, request.knownNames.clear].contains(request.calleeName),
                  let currentType = request.ctx.implicitReceiverType,
                  case let .classType(current) = request.sema.types.kind(of: currentType),
                  case let .classType(superclass) = request.sema.types.kind(of: lookupReceiverType),
                  let mutableMap = request.sema.symbols.lookup(fqName: request.knownNames.kotlinCollectionsMutableMapFQName),
                  request.sema.types.isNominalSubtypeSymbol(superclass.classSymbol, of: mutableMap),
                  let arguments = request.sema.types.liftedNominalSupertypeArgs(
                      from: current.classSymbol, childArgs: current.args, to: superclass.classSymbol
                  )
            else { return nil }
            return request.sema.types.make(.classType(ClassType(classSymbol: superclass.classSymbol, args: arguments)))
        }()
        let callableReferenceExtensionReceiverType: TypeID? = {
            guard let callableReferenceFunctionType,
                  candidates.contains(where: { candidate in
                      guard let signature = request.sema.symbols.functionSignature(for: candidate),
                            let receiver = signature.receiverType
                      else {
                          return false
                      }
                      switch request.sema.types.kind(of: request.sema.types.makeNonNullable(receiver)) {
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
        let resolvedLookupReceiverType = resolvedBuilderInferenceType(lookupReceiverType, ctx: request.ctx)
        let channelBoundReceiverType = request.calleeName == request.knownNames.receive
            ? ReceiverClassifier(sema: request.sema, interner: request.interner).channelUpperBoundType(of: lookupReceiverType)
            : nil
        let effectiveReceiverType = companionReceiverType
            ?? mutableMapSuperReceiverType
            ?? rangeSourceMemberLookupType
            ?? rangeExtensionLookupType
            ?? callableReferenceExtensionReceiverType
            ?? channelBoundReceiverType
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
        let hasTrailingLambdaArg = request.args.last.map { request.ast.arena.expr($0.expr)?.isLambdaOrCallableRef ?? false } ?? false
        // STDLIB-pipeline §5 / KSP-441: Source-backed Sequence transforms
        // (map, filter, etc.) must bind to the real Kotlin declaration so the
        // object-expression pipeline runs instead of a `kk_*` runtime shortcut.
        let memberNameText = request.interner.resolve(request.calleeName)
        let isMutableMapIteratorSource = memberNameText == "iterator"
            && ReceiverClassifier(sema: request.sema, interner: request.interner).isMutableMapType(memberLookupType)
        // MutableSet inherits independent Set.iterator and MutableIterable.iterator
        // candidates. Keep the mutable-aware collection fallback when lookup is
        // ambiguous, while a unique source member retains normal dispatch.
        let isUniqueIteratorSource = memberNameText == "iterator" && candidates.count == 1
        let isListSourceBackedMember: Bool = {
            guard ["get", "indexOf", "lastIndexOf", "subList"].contains(memberNameText),
                  // `lookup(fqName:)` can return the `List(size, init)` factory
                  // function that shares this fqName; `lookupNominal` keeps the
                  // interface so the subtype check compares nominal owners.
                  let listOwner = request.sema.symbols.lookupNominal(fqName: request.knownNames.kotlinCollectionsListFQName)
            else { return false }
            return driver.helpers.allNominalSymbols(of: memberLookupType, types: request.sema.types, symbols: request.sema.symbols).contains {
                request.sema.types.isNominalSubtypeSymbol($0, of: listOwner)
            }
        }()
        // KSP-687 resolves Array.joinToString through the dedicated primitive
        // and generic-array source candidates. KSP-429's broad trailing-lambda
        // gate is for List/Iterable source calls; applying it to Array receivers
        // prevents the array resolver from binding the source overload.
        let isArrayJoinToString = memberNameText == "joinToString"
            && isArrayLikeReceiver(receiverID: request.receiverID, sema: request.sema, interner: request.interner)
        let isArraySourceBackedMember = isArrayLikeReceiver(receiverID: request.receiverID, sema: request.sema, interner: request.interner)
            && !collectArraySourceBackedCandidates(
                named: request.calleeName,
                receiverType: memberLookupType,
                ctx: request.ctx,
                sema: request.sema,
                interner: request.interner
            ).isEmpty
        let isSourceBackedMemberName = (request.calleeName == request.knownNames.zip
            && isSequenceLikeType(lookupReceiverType, sema: request.sema, interner: request.interner))
            || request.knownNames.sourceBackedCollectionMemberNames.contains(request.calleeName)
            || (request.knownNames.sourceBackedTrailingLambdaMemberNames.contains(request.calleeName) && !isArrayJoinToString)
            || isArraySourceBackedMember
            || isMutableMapIteratorSource
            || isUniqueIteratorSource
            || isListSourceBackedMember
        // Keep user bulk extensions ahead of the bundled fallback. JVM List
        // and Collection overloads use the same source binding as MutableSet.
        let bulkReceiverFQName = request.sema.requiresResolvedLibraryCalls
            ? request.knownNames.kotlinCollectionsMutableCollectionFQName : request.knownNames.kotlinCollectionsMutableSetFQName
        let isMutableBulkCall = (request.calleeName == request.knownNames.addAll || request.sema.requiresResolvedLibraryCalls && request.calleeName == request.knownNames.removeAll)
            && request.sema.symbols.lookup(fqName: bulkReceiverFQName).map { owner in
                driver.helpers.allNominalSymbols(of: lookupReceiverType, types: request.sema.types, symbols: request.sema.symbols).contains {
                    request.sema.types.isNominalSubtypeSymbol($0, of: owner)
                }
            } == true
        // Ordinary lookup remains member-only until those members fail. Include
        // visible extensions here so they reach the normal shadowed-extension
        // resolver instead of being replaced by the stdlib fallback first.
        let bulkExtensionCandidates = isMutableBulkCall ? collectExtensionCallCandidates(
            named: request.calleeName,
            memberLookupType: memberLookupType,
            isSuperCall: isSuperCall,
            supertypeSymbols: [],
            ctx: request.ctx,
            locals: locals,
            sema: request.sema,
            interner: request.interner
        ) : []
        let (visibleBulkExtensions, _) = request.ctx.filterByVisibility(bulkExtensionCandidates)
        let hasUserBulkCandidate = isMutableBulkCall && (candidates + visibleBulkExtensions).contains { candidate in
            guard let symbol = request.sema.symbols.symbol(candidate),
                  request.sema.symbols.isSourceBackedSymbol(candidate),
                  !symbol.fqName.starts(with: request.knownNames.kotlinCollectionsPackage),
                  let signature = request.sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count == 1,
                  let declaredReceiver = signature.receiverType
            else { return false }
            let receiverSymbols = driver.helpers.allNominalSymbols(
                of: lookupReceiverType, types: request.sema.types, symbols: request.sema.symbols
            )
            let declaredReceiverSymbols = driver.helpers.allNominalSymbols(
                of: declaredReceiver, types: request.sema.types, symbols: request.sema.symbols
            )
            return receiverSymbols.contains { actual in
                declaredReceiverSymbols.contains { declared in
                    request.sema.types.isNominalSubtypeSymbol(actual, of: declared)
                }
            }
        }
        let hasSourceBackedCandidate = hasUserBulkCandidate || isSourceBackedMemberName
            && (isArraySourceBackedMember || !request.knownNames.sourceBackedCollectionMemberNames.contains(request.calleeName) || !hasTrailingLambdaArg)
            && candidates.contains { candidateID in
                request.sema.symbols.isSourceBackedSymbol(candidateID)
            }
        // Synthetic collection members need to short-circuit before the generic
        // overload resolver so their trailing-lambda expectations stay concrete.
        if !hasSourceBackedCandidate, let fallbackType = tryCollectionMemberFallback(
            request.id,
            calleeName: request.calleeName,
            isClassNameReceiver: isClassNameReceiver,
            safeCall: request.safeCall,
            receiverID: request.receiverID,
            args: request.args,
            ctx: request.ctx,
            expectedType: request.expectedType,
            locals: &locals
        ) {
            return (effectiveReceiverType, fallbackType)
        }

        if let fallbackType = tryBindComparatorMemberFallback(
            request.id,
            calleeName: request.calleeName,
            safeCall: request.safeCall,
            receiverType: lookupReceiverType,
            args: request.args,
            ctx: request.ctx,
            locals: &locals
        ) {
            return (effectiveReceiverType, fallbackType)
        }
        // Scope/import priority precedes function-vs-property priority. Do this
        // before lambda preparation, which would otherwise infer a package
        // property's block as the implicitly imported T.apply receiver lambda.
        if !isClassNameReceiver, !isSuperCall,
           let functionPriority = candidates.map({ callableInvocationScopePriority($0, named: request.calleeName, ctx: request.ctx) }).min(),
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
        var candidates = candidates
        let memberNameText = request.interner.resolve(request.calleeName)

        let hasNonNullFlowFact = if let reference = request.ctx.dataFlow.resolveStableReference(
            request.receiverID, locals: locals, ast: request.ast, sema: request.sema, interner: request.interner
        ), reference.isStable,
           let flow = request.ctx.flowState.includingMembers(from: locals)[reference.symbol]
        {
            flow.isStable && flow.nullability == .nonNull
        } else {
            false
        }
        // A safe call or stable non-null flow fact proves this receiver can use
        // the non-null view of its upper bounds during overload resolution.
        let receiverTypeForResolution: TypeID = {
            guard request.safeCall || hasNonNullFlowFact else { return effectiveReceiverType }

            let upperBounds: [TypeID] = switch request.sema.types.kind(of: effectiveReceiverType) {
            case let .typeParam(parameter):
                parameter.capture.map { [$0.upper] }
                    ?? request.sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
            case let .intersection(parts):
                parts.flatMap { part -> [TypeID] in
                    guard case let .typeParam(parameter) = request.sema.types.kind(of: part) else {
                        return []
                    }
                    return parameter.capture.map { [$0.upper] }
                        ?? request.sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
                }
            default:
                []
            }
            guard !upperBounds.isEmpty else { return effectiveReceiverType }
            let nonNullBounds = upperBounds.map(request.sema.types.makeNonNullable)
            return nonNullBounds.count == 1
                ? nonNullBounds[0]
                : request.sema.types.make(.intersection(nonNullBounds))
        }()

        var cachedNonLambdaArgTypes: [Int: TypeID] = [:]
        for (index, argument) in request.args.enumerated() {
            guard let argumentExpr = request.ast.arena.expr(argument.expr) else {
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
            argumentExpectedTypeOverrides[0] = request.sema.types.longType
        } else if isULongRangeLiteralContainsCall {
            argumentExpectedTypeOverrides[0] = request.sema.types.ulongType
        }
        let directArgumentExpectedTypeOverrides = argumentExpectedTypeOverrides
        let argumentContextTypeArgs = typeAliasConstructor.map {
            aliasConstructorArgumentContextTypes($0, explicitTypeArgs: request.explicitTypeArgs, sema: request.sema)
        } ?? request.explicitTypeArgs
        var lambdaContextOverrides: [Int: TypeInferenceContext] = [:]
        let expectedTypeHintIndices = prepareCallExprArgumentContexts(
            args: request.args,
            callRange: request.range,
            ctx: request.ctx,
            expectedType: request.expectedType,
            explicitTypeArgs: argumentContextTypeArgs,
            calleeName: request.calleeName,
            candidates: candidates,
            locals: locals,
            preInferredArgumentTypes: cachedNonLambdaArgTypes,
            withContextExpectedLambdaType: nil,
            receiverType: effectiveReceiverType,
            expectedTypeOverrides: &argumentExpectedTypeOverrides,
            lambdaContextOverrides: &lambdaContextOverrides
        )
        let preparedArgs = prepareCallArguments(
            args: request.args,
            callRange: request.range,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            expectedTypeOverrides: argumentExpectedTypeOverrides,
            expectedTypeHintIndices: expectedTypeHintIndices,
            contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                ? request.sema.types.unitType : request.expectedType,
            explicitTypeArgs: argumentContextTypeArgs,
            receiverType: effectiveReceiverType,
            lambdaContextOverrides: lambdaContextOverrides,
            ctx: request.ctx,
            locals: &locals
        )
        // Older imported stdlib artifacts may still expose a String callback
        // bridge alongside the bundled CharSequence declaration. Lambda
        // preparation intentionally erases return types while finding a shared
        // input shape, so prefer that compatibility bridge only when it is
        // actually present and applicable; bundled source continues through
        // the CharSequence declaration.
        if memberNameText == "replace",
           request.args.count == 2,
           request.sema.types.makeNonNullable(argTypes[0]) == request.sema.types.stringType,
           preparedArgs.lambdaLiteralIndices.contains(1),
           case let .functionType(lambdaType) = request.sema.types.kind(
               of: request.sema.types.makeNonNullable(preparedArgs.argTypes[1])
           ),
           request.sema.types.isSubtype(lambdaType.returnType, request.sema.types.stringType)
        {
            let regexStringBridgeCandidates = candidates.filter {
                request.sema.symbols.externalLinkName(for: $0) == "__kk_regex_replace_lambda"
            }
            if !regexStringBridgeCandidates.isEmpty {
                candidates = regexStringBridgeCandidates
            }
        }
        let isDeferredAwait = candidates.contains {
            request.sema.symbols.externalLinkName(for: $0) == "kk_kxmini_async_await"
        }
        let resolutionExpectedType = isDeferredAwait ? nil : request.expectedType
        // The nullable result of findAnnotation does not make its reified
        // annotation argument nullable. Keep ordinary lookup and bound checking.
        let resolutionTypeArgs: [TypeID]
        if request.explicitTypeArgs.isEmpty, candidates.count == 1,
           let candidate = candidates.first,
           request.sema.symbols.symbol(candidate)?.fqName == ["kotlin", "reflect", "full", "findAnnotation"].map(request.interner.intern),
           let unwrappedExpectedType = request.expectedType,
           let bound = request.sema.symbols.functionSignature(for: candidate)?.typeParameterUpperBounds.first ?? nil {
            let expectedArgument = request.sema.types.makeNonNullable(unwrappedExpectedType)
            resolutionTypeArgs = [request.sema.types.isSubtype(bound, expectedArgument) ? bound : expectedArgument]
        } else {
            resolutionTypeArgs = request.explicitTypeArgs
        }
        let hasCandidatesBeforeNestedFiltering = !candidates.isEmpty
        let candidateSpecificNestedCallTypes = candidateSpecificNestedCallArgumentTypes(
            candidates: candidates,
            args: request.args,
            originalArgumentTypes: preparedArgs.argTypes,
            originalExpectedTypeOverrides: argumentExpectedTypeOverrides,
            explicitTypeArgs: resolutionTypeArgs,
            implicitReceiverType: receiverTypeForResolution,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            ctx: request.ctx,
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
            args: request.args,
            argTypes: preparedArgs.argTypes,
            range: request.range,
            calleeName: request.calleeName,
            explicitTypeArgs: resolutionTypeArgs,
            typeAliasConstructor: typeAliasConstructor,
            expectedType: resolutionExpectedType,
            implicitReceiverType: receiverTypeForResolution,
            candidateArgumentTypes: candidateSpecificNestedCallTypes?.argumentTypesByCandidate ?? [:],
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: request.ctx
        )
        // Ambiguous applicable members retain precedence over extensions.
        if let diagnostic = resolved.diagnostic,
           diagnostic.code == "KSWIFTK-SEMA-0003"
        {
            // An unresolved receiver or argument already has the root diagnostic.
            let hasUnresolvedMemberInput = containsUnresolvedMemberDiagnostic(
                in: [request.receiverID] + request.args.map(\.expr),
                ast: request.ast,
                sema: request.sema
            )
            if !hasUnresolvedMemberInput {
                request.ctx.sema.diagnostics.emit(diagnostic)
            }
            return (candidates, preparedArgs, resolved, driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema))
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
           !request.args.contains(where: { request.ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }),
           hasCandidatesBeforeNestedFiltering
        {
            let receiverForExtensionLookup = request.sema.types.makeNonNullable(effectiveReceiverType)
            func receiverMatchingExtensions(_ scopeCandidates: [SymbolID]) -> [SymbolID] {
                scopeCandidates.filter { candidate in
                    guard let symbol = request.ctx.cachedSymbol(candidate),
                          symbol.kind == .function,
                          !request.ast.arena.isInfixCall(request.id) || symbol.flags.contains(.infixFunction),
                          let signature = request.sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          !isHiddenByDeprecationOrVersionAnnotation(candidate, symbols: request.sema.symbols)
                    else { return false }
                    let isUser = symbol.declSite.map {
                        driver.sourceManager?.origin(of: $0.start.file) == .user
                    } ?? false
                    guard isUser || request.sema.symbols.isSourceBackedSymbol(candidate),
                          request.ctx.visibilityChecker.isAccessible(
                              symbol,
                              fromFile: request.ctx.currentFileID,
                              enclosingClass: request.ctx.enclosingClassSymbol
                          )
                    else { return false }
                    return extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: receiverForExtensionLookup,
                        declaredReceiver: declaredReceiver,
                        sema: request.sema
                    )
                }
            }
            // Viable user extensions shadow outer bindings, not inapplicable ones.
            var extensionCandidates = receiverMatchingExtensions(request.ctx.scope.lookup(request.calleeName))
            if extensionCandidates.isEmpty || request.ctx.resolver.probeCall(
                candidates: extensionCandidates,
                call: CallExpr(range: request.range, calleeName: request.calleeName, args: zip(request.args, preparedArgs.argTypes).map { argument, type in
                    CallArg.source(argument, type: type, callRange: request.range, ast: request.ctx.ast)
                }, elvisLhsExpectedTypeHint: request.ctx.isElvisBranchExpectedTypeHint,
                   elvisRhsCallResultTypeHint: request.ctx.elvisRhsCallResultTypeHint),
                expectedType: request.expectedType,
                implicitReceiverType: receiverForExtensionLookup,
                ctx: request.ctx.sema
            ).viableCandidates.isEmpty {
                extensionCandidates = receiverMatchingExtensions(request.ctx.scope.lookupMergingChain(request.calleeName))
            }
            if !extensionCandidates.isEmpty {
                var extensionExpectedTypeOverrides = directArgumentExpectedTypeOverrides
                var extensionExpectedTypeHintIndices: Set<Int> = []
                prepareUnambiguousNestedCallExpectedTypes(
                    args: request.args,
                    callRange: request.range,
                    candidates: extensionCandidates,
                    preInferredArgumentTypes: cachedNonLambdaArgTypes,
                    ctx: request.ctx,
                    locals: locals,
                    receiverType: receiverForExtensionLookup,
                    expectedType: request.expectedType,
                    expectedTypeOverrides: &extensionExpectedTypeOverrides,
                    expectedTypeHintIndices: &extensionExpectedTypeHintIndices
                )
                let extensionArgs = prepareCallArguments(
                    args: request.args,
                    callRange: request.range,
                    candidates: extensionCandidates,
                    preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
                    expectedTypeOverrides: extensionExpectedTypeOverrides,
                    expectedTypeHintIndices: extensionExpectedTypeHintIndices,
                    contextualCallResultType: request.ctx.isCallResultDiscarded && request.ctx.isUnitCoercionContext
                        ? request.sema.types.unitType : request.expectedType,
                    explicitTypeArgs: request.explicitTypeArgs,
                    receiverType: effectiveReceiverType,
                    ctx: request.ctx,
                    locals: &locals
                )
                let extensionNestedCallTypes = candidateSpecificNestedCallArgumentTypes(
                    candidates: extensionCandidates,
                    args: request.args,
                    originalArgumentTypes: extensionArgs.argTypes,
                    originalExpectedTypeOverrides: extensionExpectedTypeOverrides,
                    explicitTypeArgs: request.explicitTypeArgs,
                    implicitReceiverType: receiverTypeForResolution,
                    lambdaLiteralIndices: extensionArgs.lambdaLiteralIndices,
                    ctx: request.ctx,
                    locals: locals
                )
                if let extensionNestedCallTypes {
                    extensionCandidates.removeAll {
                        extensionNestedCallTypes.inapplicableCandidates.contains($0)
                    }
                }
                let retried = resolveCallRespectingLambdaReturnType(
                    candidates: extensionCandidates,
                    args: request.args,
                    argTypes: extensionArgs.argTypes,
                    range: request.range,
                    calleeName: request.calleeName,
                    explicitTypeArgs: request.explicitTypeArgs,
                    expectedType: request.expectedType,
                    implicitReceiverType: receiverTypeForResolution,
                    candidateArgumentTypes: extensionNestedCallTypes?.argumentTypesByCandidate ?? [:],
                    lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                    inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                    blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                    hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                    ctx: request.ctx
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
                let diagnosticsCheckpoint = request.sema.diagnostics.checkpoint()
                // The engine dedups identical diagnostics, so an error already
                // live inside the argument range makes a re-emitted identical
                // one invisible to `emittedError` — the re-inference would look
                // clean and the removal below would strip a live inference
                // failure. Clear the range first and restore the removed
                // diagnostics unless the re-inference actually succeeded
                // (KUU-4002).
                let argumentRange = request.ast.arena.exprRange(request.args[index].expr)
                let removedDiagnostics = argumentRange.map {
                    request.sema.diagnostics.removeErrorDiagnostics(containedIn: $0)
                } ?? []
                let argumentType = driver.inferExpr(
                    request.args[index].expr,
                    ctx: request.ctx,
                    locals: &locals,
                    expectedType: expectedArgumentType
                )
                let emittedError = request.sema.diagnostics.diagnostics.dropFirst(diagnosticsCheckpoint).contains {
                    $0.severity == .error
                }
                if argumentType == request.sema.types.errorType
                    || typeContainsErrorType(argumentType, sema: request.sema)
                    || emittedError
                {
                    removedDiagnostics.forEach { request.sema.diagnostics.emit($0) }
                }
            }
        }

        return (candidates, preparedArgs, resolved, nil)
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
