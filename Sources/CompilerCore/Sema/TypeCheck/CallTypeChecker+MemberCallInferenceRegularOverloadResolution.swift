// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Effective receiver selection and the pre-resolution synthetic fallbacks,
    /// extracted verbatim from `inferRegularMemberCall`: super MutableMap and
    /// callable-reference receiver adjustments, then the collection,
    /// ThreadLocal getOrSet, comparator and callable-property scope-priority
    /// fallbacks that must run before lambda argument preparation.
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

        // Use the companion type as implicit receiver when the candidates were
        // redirected from the owner class to its companion object.
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
                      guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                          return false
                      }
                      if case .functionType = sema.types.kind(of: receiver) {
                          return true
                      }
                      return false
                  })
            else {
                return nil
            }
            return callableReferenceFunctionType
        }()
        let effectiveReceiverType = companionReceiverType
            ?? mutableMapSuperReceiverType
            ?? rangeSourceMemberLookupType
            ?? rangeExtensionLookupType
            ?? callableReferenceExtensionReceiverType
            ?? lookupReceiverType
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
                  let listOwner = sema.symbols.lookup(fqName: knownNames.kotlinCollectionsListFQName)
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
        let hasSourceBackedCandidate = isSourceBackedMemberName
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
        if let fallbackType = tryBindThreadLocalGetOrSetFallback(
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

    /// Argument preparation and overload resolution, extracted verbatim from
    /// `inferRegularMemberCall`: lambda-aware argument inference, the
    /// regex-replace String bridge, the deferred-await expected-type bypass,
    /// candidate resolution and the shadowed-extension retry.
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
        let preparedArgs = prepareCallArguments(
            args: args,
            candidates: candidates,
            preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
            expectedTypeOverrides: {
                if isLongRangeLiteralContainsCall {
                    return [0: sema.types.longType]
                }
                if isULongRangeLiteralContainsCall {
                    return [0: sema.types.ulongType]
                }
                return [:]
            }(),
            contextualCallResultType: expectedType,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: effectiveReceiverType,
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
        var resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: range,
            calleeName: calleeName,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: resolutionExpectedType,
            implicitReceiverType: effectiveReceiverType,
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
            ctx.semaCtx.diagnostics.emit(diagnostic)
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
           !candidates.isEmpty
        {
            let receiverForExtensionLookup = sema.types.makeNonNullable(effectiveReceiverType)
            func receiverMatchingExtensions(_ scopeCandidates: [SymbolID]) -> [SymbolID] {
                scopeCandidates.filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          !isHiddenByDeprecatedAnnotation(candidate, symbols: sema.symbols)
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
                call: CallExpr(range: range, calleeName: calleeName, args: preparedArgs.argTypes.map { CallArg(type: $0) }),
                expectedType: expectedType,
                implicitReceiverType: receiverForExtensionLookup,
                ctx: ctx.semaCtx
            ).viableCandidates.isEmpty {
                extensionCandidates = receiverMatchingExtensions(ctx.scope.lookupMergingChain(calleeName))
            }
            if !extensionCandidates.isEmpty {
                let extensionArgs = prepareCallArguments(
                    args: args,
                    candidates: extensionCandidates,
                    preInferredNonLambdaArgTypes: cachedNonLambdaArgTypes,
                    contextualCallResultType: expectedType,
                    explicitTypeArgs: explicitTypeArgs,
                    receiverType: effectiveReceiverType,
                    ctx: ctx,
                    locals: &locals
                )
                let retried = resolveCallRespectingLambdaReturnType(
                    candidates: extensionCandidates,
                    args: args,
                    argTypes: extensionArgs.argTypes,
                    range: range,
                    calleeName: calleeName,
                    explicitTypeArgs: explicitTypeArgs,
                    expectedType: expectedType,
                    implicitReceiverType: effectiveReceiverType,
                    lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                    inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                    blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                    hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                    ctx: ctx
                )
                if retried.diagnostic == nil {
                    candidates = extensionCandidates
                    resolved = retried
                }
            }
        }

        return (candidates, preparedArgs, resolved, nil)
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
