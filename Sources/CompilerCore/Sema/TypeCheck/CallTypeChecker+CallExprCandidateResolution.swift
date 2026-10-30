// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func contextApplicableCallCandidates(
        _ candidates: [SymbolID],
        ctx: TypeInferenceContext,
        argumentLabels: [InternedString?] = []
    ) -> [SymbolID] {
        let sema = ctx.sema
        let availableContextTypes = ctx.contextReceiverTypes
            + ctx.implicitReceiverStack.map(\.type)
            + ctx.outerReceiverTypes.map(\.type)
            + (ctx.implicitReceiverType.map { [$0] } ?? [])
            + ctx.implicitReceiverMemberLookupEntries().map(\.type)
        return candidates.filter { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return true
            }
            guard let explicitContextArguments = ctx.resolver.explicitContextParameterArgumentMapping(
                signature: signature,
                argumentLabels: argumentLabels,
                symbols: sema.symbols
            ) else {
                return false
            }
            return signature.contextParameterTypes.enumerated().allSatisfy { contextIndex, requiredType in
                if explicitContextArguments.values.contains(contextIndex) {
                    return true
                }
                if sema.types.typeContainsAnyTypeParam(requiredType) {
                    return !availableContextTypes.isEmpty
                }
                return availableContextTypes.contains { availableType in
                    sema.types.isSubtype(
                        sema.types.makeNonNullable(availableType),
                        sema.types.makeNonNullable(requiredType)
                    )
                }
            }
        }
    }

    func firstContextParameterType(
        in candidates: [SymbolID],
        ctx: TypeInferenceContext,
        argumentLabels: [InternedString?] = []
    ) -> TypeID? {
        let sema = ctx.sema
        let availableContextTypes = ctx.contextReceiverTypes
            + ctx.implicitReceiverStack.map(\.type)
            + ctx.outerReceiverTypes.map(\.type)
            + (ctx.implicitReceiverType.map { [$0] } ?? [])
            + ctx.implicitReceiverMemberLookupEntries().map(\.type)
        return candidates.compactMap { candidate -> TypeID? in
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  let explicitlyProvided = ctx.resolver.explicitContextParameterArgumentMapping(
                      signature: signature,
                      argumentLabels: argumentLabels,
                      symbols: sema.symbols
                  )
            else {
                return nil
            }
            return signature.contextParameterTypes.enumerated().first { index, requiredType in
                guard !explicitlyProvided.values.contains(index) else { return false }
                if sema.types.typeContainsAnyTypeParam(requiredType) {
                    return availableContextTypes.isEmpty
                }
                return !availableContextTypes.contains { availableType in
                    sema.types.isSubtype(
                        sema.types.makeNonNullable(availableType),
                        sema.types.makeNonNullable(requiredType)
                    )
                }
            }?.element
        }.first
    }

    func resolveCallExprCandidates(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        candidates: [SymbolID],
        constructorTypeAlias: SymbolID?,
        typeAliasConstructor: TypeAliasConstructorContext?,
        typeNameCompanionInvokeCandidates: Set<SymbolID>,
        typeNameCompanionInvokeReceiverType: TypeID?,
        callImplicitReceiverType: TypeID?,
        memberExtensionReceiverMarks: [SymbolID: SymbolID],
        mergedImplicitReceiverMembers: [SymbolID],
        knownApplicableImplicitMembers: Set<SymbolID>,
        preferredInheritedNestedConstructors: Set<SymbolID>,
        outerNestedConstructorFallbacks: Set<SymbolID>,
        expectedTypeOverrides: [Int: TypeID],
        preparedArgs: PreparedCallArguments,
        argTypes: [TypeID]
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        let argumentLabels = args.map(\.label)
        let contextApplicableCandidates = contextApplicableCallCandidates(
            candidates, ctx: ctx, argumentLabels: argumentLabels
        )
        var resolvedCandidates: [SymbolID]
        if !contextApplicableCandidates.isEmpty {
            resolvedCandidates = contextApplicableCandidates
        } else if let missingType = firstContextParameterType(
            in: candidates, ctx: ctx, argumentLabels: argumentLabels
        ) {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-CTX-002",
                "No context value is available for parameter type '\(sema.types.renderType(missingType))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        } else {
            resolvedCandidates = candidates
        }

        if !resolvedCandidates.isEmpty {
            // Coroutine builders erase their result type. Resolve arguments first,
            // then recover the actual block result instead of constraining Any.
            let coroutineBuilderNames: Set<String> = [
                "runBlocking", "async", "withContext", "withTimeout", "withTimeoutOrNull",
            ]
            let isCoroutineBuilderCandidate: (SymbolID) -> Bool = { candidate in
                guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                let externalLinkName = sema.symbols.externalLinkName(for: candidate)
                return externalLinkName == "kk_coroutine_scope_async"
                    || externalLinkName == "kk_with_timeout"
                    || externalLinkName == "kk_with_timeout_or_null_throwing"
                    || sema.symbols.isSourceBackedSymbol(candidate)
                    && (symbol.name == knownNames.coroutineScope || symbol.name == knownNames.supervisorScope)
                    && symbol.fqName.dropLast() == [interner.intern("kotlinx"), interner.intern("coroutines")][...]
                    || symbol.flags.contains(.synthetic)
                    && symbol.fqName.dropLast() == [interner.intern("kotlinx"), interner.intern("coroutines")][...]
                    && coroutineBuilderNames.contains(interner.resolve(symbol.name))
            }
            // Nested class member scopes are chained lexically, so a bare
            // member call can arrive here with a candidate owned by an outer
            // class. Resolve it against that enclosing receiver's type rather
            // than the inner class's implicit receiver.
            // Object-literal outer receivers carry a capture symbol; leave
            // those to the later implicit-receiver tower so KIR can load
            // `this@Outer` from the captured field (kuu_544).
            let callImplicitReceiverType = ctx.outerReceiverTypes.reversed().first { outerReceiver in
                guard outerReceiver.symbol == nil,
                      let outerClass = resolveClassType(outerReceiver.type, sema: sema)?.classSymbol
                else {
                    return false
                }
                return resolvedCandidates.contains { candidate in
                    sema.symbols.parentSymbol(for: candidate) == outerClass
                }
            }?.type ?? resolvedCandidates.lazy.compactMap { candidate -> TypeID? in
                guard let owner = sema.symbols.parentSymbol(for: candidate),
                      let containingClass = sema.symbols.parentSymbol(for: owner),
                      sema.symbols.companionObjectSymbol(for: containingClass) == owner,
                      let receiverType = sema.symbols.functionSignature(for: candidate)?.receiverType,
                      resolveClassType(receiverType, sema: sema)?.classSymbol == owner
                else {
                    return nil
                }
                return receiverType
            }.first ?? callImplicitReceiverType
            let candidateSpecificNestedCallTypes = candidateSpecificNestedCallArgumentTypes(
                candidates: resolvedCandidates,
                args: args,
                originalArgumentTypes: argTypes,
                originalExpectedTypeOverrides: expectedTypeOverrides,
                explicitTypeArgs: explicitTypeArgs,
                implicitReceiverType: callImplicitReceiverType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                ctx: ctx,
                locals: locals
            )
            if let candidateSpecificNestedCallTypes {
                resolvedCandidates.removeAll {
                    candidateSpecificNestedCallTypes.inapplicableCandidates.contains($0)
                }
            }
            let inheritedNestedConstructors = resolvedCandidates.filter {
                preferredInheritedNestedConstructors.contains($0)
            }
            let outerConstructorFallbacks = resolvedCandidates.filter {
                outerNestedConstructorFallbacks.contains($0)
            }
            if !inheritedNestedConstructors.isEmpty, !outerConstructorFallbacks.isEmpty {
                let constructorCall = CallExpr(
                    range: range,
                    calleeName: calleeName ?? InternedString(),
                    args: zip(args, preparedArgs.argTypes).map { argument, type in
                        CallArg.source(argument, type: type, callRange: range, ast: ast)
                    },
                    explicitTypeArgs: explicitTypeArgs
                )
                let inheritedProbe = ctx.resolver.probeCall(
                    candidates: inheritedNestedConstructors,
                    call: constructorCall,
                    expectedType: expectedType,
                    implicitReceiverType: callImplicitReceiverType,
                    candidateArgumentTypes: candidateSpecificNestedCallTypes?.argumentTypesByCandidate ?? [:],
                    ctx: sema
                )
                if !inheritedProbe.viableCandidates.isEmpty {
                    resolvedCandidates.removeAll { outerNestedConstructorFallbacks.contains($0) }
                }
            }
            var resolvedTypeNameInvokeCandidates = typeNameCompanionInvokeCandidates.intersection(
                resolvedCandidates
            )
            let constructors = resolvedCandidates.filter {
                sema.symbols.symbol($0)?.kind == .constructor
            }
            if !constructors.isEmpty, !resolvedTypeNameInvokeCandidates.isEmpty {
                let constructorCall = CallExpr(
                    range: range,
                    calleeName: calleeName ?? InternedString(),
                    args: zip(args, preparedArgs.argTypes).map { argument, type in
                        CallArg.source(argument, type: type, callRange: range, ast: ast)
                    },
                    explicitTypeArgs: explicitTypeArgs
                )
                let constructorProbe = ctx.resolver.probeCall(
                    candidates: constructors,
                    call: constructorCall,
                    expectedType: nil,
                    candidateArgumentTypes: candidateSpecificNestedCallTypes?.argumentTypesByCandidate ?? [:],
                    ctx: sema
                )
                if !constructorProbe.viableCandidates.isEmpty {
                    resolvedCandidates.removeAll { resolvedTypeNameInvokeCandidates.contains($0) }
                    resolvedTypeNameInvokeCandidates.removeAll()
                }
            }
            resolvedCandidates = preferApplicableExplicitTopLevelImportTier(
                candidates: resolvedCandidates,
                args: args,
                argTypes: argTypes,
                range: range,
                calleeName: calleeName,
                explicitTypeArgs: explicitTypeArgs,
                expectedType: expectedType,
                implicitReceiverType: callImplicitReceiverType,
                candidateArgumentTypes: candidateSpecificNestedCallTypes?.argumentTypesByCandidate ?? [:],
                hasApplicableImplicitMembers: !knownApplicableImplicitMembers.isEmpty,
                ctx: ctx
            )
            resolvedTypeNameInvokeCandidates.formIntersection(resolvedCandidates)
            let isCoroutineBuilderWithHardcodedAnyReturn = resolvedCandidates.contains { candidate in
                isCoroutineBuilderCandidate(candidate)
                    && sema.symbols.externalLinkName(for: candidate) != "kk_with_timeout"
                    && sema.symbols.externalLinkName(for: candidate) != "kk_with_timeout_or_null_throwing"
            }
            var resolvedImplicitReceiverType = callImplicitReceiverType
            let resolutionDiagnosticsCheckpoint = ctx.sema.diagnostics.checkpoint()
            var resolved = resolveCallRespectingLambdaReturnType(
                candidates: resolvedCandidates,
                args: args,
                argTypes: argTypes,
                range: range,
                calleeName: calleeName ?? InternedString(),
                explicitTypeArgs: explicitTypeArgs,
                typeAliasConstructor: typeAliasConstructor,
                expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                implicitReceiverType: callImplicitReceiverType,
                bindsObjectDispatchReceiver: true,
                additionalDispatchReceiverTypes: typeNameCompanionInvokeReceiverType.map { [$0] } ?? [],
                additionalBoundObjectDispatchReceiverCandidates: resolvedTypeNameInvokeCandidates,
                candidateArgumentTypes: candidateSpecificNestedCallTypes?.argumentTypesByCandidate ?? [:],
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx
            )
            let hasUninferredLinkedHashMapArgument = args.indices.contains { index in
                !preparedArgs.lambdaLiteralIndices.contains(index)
                    && index < argTypes.count
                    && isReinferableLinkedHashMapConstructor(args[index].expr, ctx: ctx)
            }
            if hasUninferredLinkedHashMapArgument,
               let retried = retryResolutionReinferringNestedCallArguments(
                   candidates: resolvedCandidates,
                   args: args,
                   argTypes: argTypes,
                   range: range,
                   calleeName: calleeName ?? InternedString(),
                   explicitTypeArgs: explicitTypeArgs,
                   expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                   implicitReceiverType: callImplicitReceiverType,
                   bindsObjectDispatchReceiver: true,
                   additionalDispatchReceiverTypes: typeNameCompanionInvokeReceiverType.map { [$0] } ?? [],
                   additionalBoundObjectDispatchReceiverCandidates: resolvedTypeNameInvokeCandidates,
                   lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                   inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                   blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                   hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                   ctx: ctx,
                   locals: &locals
               )
            {
                ctx.sema.diagnostics.rollback(to: resolutionDiagnosticsCheckpoint)
                resolved = retried
                resolvedImplicitReceiverType = callImplicitReceiverType
            }
            // An unresolved member argument already has the root diagnostic.
            if resolved.diagnostic?.code == "KSWIFTK-SEMA-0003",
               containsUnresolvedMemberDiagnostic(in: args.map(\.expr), ast: ast, sema: sema)
            {
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            // An applicable member keeps precedence even when the surrounding
            // result expectation fails, or its own overload set is ambiguous.
            if let diagnostic = resolved.diagnostic,
               !knownApplicableImplicitMembers.isEmpty,
               resolvedCandidates.allSatisfy({ knownApplicableImplicitMembers.contains($0) })
            {
                ctx.sema.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if resolved.diagnostic != nil, typeAliasConstructor == nil {
                if let calleeName,
                   let recovered = tryBindImplicitReceiverMemberCallForInapplicableScopeCandidates(
                       id,
                       calleeName: calleeName,
                       args: args,
                       argTypes: argTypes,
                       range: range,
                       explicitTypeArgs: explicitTypeArgs,
                       expectedType: expectedType,
                       scopeCandidates: resolvedCandidates,
                       ctx: ctx
                   )
                {
                    return recovered
                }
                if resolved.diagnostic != nil,
                   mergedImplicitReceiverMembers.count == 1,
                   let bestCandidate = mergedImplicitReceiverMembers.first,
                   let signature = sema.symbols.functionSignature(for: bestCandidate),
                   !narrowedCallCandidates(
                       candidates: [bestCandidate], args: args, callRange: range,
                       inferredNonLambdaArgTypes: Dictionary(uniqueKeysWithValues: argTypes.enumerated().map {
                           ($0.offset, $0.element)
                       }),
                       receiverType: callImplicitReceiverType, forImplicitMemberApplicability: true, ctx: ctx
                   ).isEmpty,
                   let calleeName
                {
                    if signature.classTypeParameterCount > 0 {
                        if let receiver = callImplicitReceiverType,
                           let result = bindClassOnlyImplicitReceiverMemberFallback(
                               id, chosen: bestCandidate, calleeName: calleeName,
                               args: args, argTypes: argTypes, range: range,
                               receiverType: receiver, explicitTypeArgs: explicitTypeArgs, ctx: ctx
                           ) {
                            return result
                        }
                    } else {
                        // The merged implicit-receiver member failed constraint
                        // solving — e.g. `FlowCollector<R>.emit` inside
                        // `transform`, where `R` is an outer call's type parameter
                        // opaque to this resolver. The general member path below
                        // would still bind such a lone member leniently; mirror
                        // that fallback here so the call is not hard-errored.
                        // Concrete argument mismatches must still be rejected.
                        var mapping: [Int: Int] = [:]
                        for i in args.indices { mapping[i] = i }
                        sema.bindings.bindCall(
                            id,
                            binding: CallBinding(
                                chosenCallee: bestCandidate,
                                substitutedTypeArguments: [],
                                parameterMapping: mapping
                            )
                        )
                        sema.bindings.bindCallableTarget(id, target: .symbol(bestCandidate))
                        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                        let resultType = signature.returnType
                        sema.bindings.bindExprType(id, type: resultType)
                        return resultType
                    }
                }
                if resolved.diagnostic?.code == "KSWIFTK-SEMA-0002",
                   let calleeName,
                   let recovered = resolveOuterImplicitReceiverExtensionCall(
                       candidates: resolvedCandidates,
                       args: args,
                       preparedArgs: preparedArgs,
                       range: range,
                       calleeName: calleeName,
                       explicitTypeArgs: explicitTypeArgs,
                       expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                       ctx: ctx
                   )
                {
                    resolved = recovered.resolved
                    if resolved.chosenCallee != nil {
                        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                        sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: recovered.receiverSymbol)
                    } else if let diagnostic = resolved.diagnostic {
                        ctx.sema.diagnostics.emit(diagnostic)
                        sema.bindings.bindExprType(id, type: sema.types.errorType)
                        return sema.types.errorType
                    }
                }
                if resolved.diagnostic != nil,
                   let calleeName,
                   let receiverType = ctx.implicitReceiverType,
                   let recovered = tryBindImplicitReceiverSyntheticExtensionCall(
                       id,
                       calleeName: calleeName,
                       receiverType: receiverType,
                       args: args,
                       range: range,
                       ctx: ctx,
                       locals: &locals,
                       expectedType: expectedType,
                       explicitTypeArgs: explicitTypeArgs
                   )
                {
                    return recovered
                }
                if resolved.diagnostic != nil,
                   let retried = retryResolutionReinferringNestedCallArguments(
                       candidates: resolvedCandidates,
                       args: args,
                       argTypes: argTypes,
                       range: range,
                       calleeName: calleeName ?? InternedString(),
                       explicitTypeArgs: explicitTypeArgs,
                       expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                       implicitReceiverType: ctx.implicitReceiverType,
                       bindsObjectDispatchReceiver: true,
                       lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                       inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                       blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                       hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                       ctx: ctx,
                       locals: &locals
                   ) {
                    resolved = retried
                    resolvedImplicitReceiverType = ctx.implicitReceiverType
                }
                // The innermost scope tier produced no viable — or only
                // inaccessible — candidates. Kotlin's call tower continues to
                // outer tiers in that case: a package-level `minOf(Long, Int)`
                // must not hide the default-imported `kotlin.math.minOf` for
                // `(Long, Long)` arguments, and a bundled-internal overload a
                // module cannot call must not report 'cannot access' when a
                // visible outer overload applies. Lambda arguments carry
                // per-candidate expected types, so only retry plain calls.
                if let calleeName,
                   resolved.diagnostic?.code == "KSWIFTK-SEMA-0002"
                       || resolved.diagnostic?.code == "KSWIFTK-SEMA-0044",
                   !args.contains(where: { isLambdaOrCallableRefArg($0.expr, ast: ast) })
                {
                    let mergedCandidates = ctx.scope.lookupMergingChain(calleeName).filter { candidate in
                        !resolvedCandidates.contains(candidate)
                            && !ctx.isCandidateBlockedByDslMarker(candidate)
                            && [.function, .constructor].contains(ctx.cachedSymbol(candidate)?.kind)
                    }
                    let outerTierCandidates = ctx.filterByVisibility(mergedCandidates).visible
                    if !outerTierCandidates.isEmpty {
                        let retried = resolveCallRespectingLambdaReturnType(
                            candidates: outerTierCandidates,
                            args: args,
                            argTypes: argTypes,
                            range: range,
                            calleeName: calleeName,
                            explicitTypeArgs: explicitTypeArgs,
                            expectedType: expectedType,
                            implicitReceiverType: callImplicitReceiverType,
                            bindsObjectDispatchReceiver: true,
                            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                            ctx: ctx
                        )
                        if retried.chosenCallee != nil, retried.diagnostic == nil {
                            resolved = retried
                        }
                    }
                }
            }
            if resolved.diagnostic == nil,
               let chosen = resolved.chosenCallee,
               let expectedTypes = candidateSpecificNestedCallTypes?.expectedTypesByCandidate[chosen]
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
            // An applicable member keeps precedence even when the surrounding
            // result expectation fails, or its own overload set is ambiguous.
            if let diagnostic = resolved.diagnostic,
               !knownApplicableImplicitMembers.isEmpty,
               resolvedCandidates.allSatisfy({ knownApplicableImplicitMembers.contains($0) })
            {
                ctx.sema.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if let diagnostic = resolved.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                // Inherited `private` members are not candidates (they are not
                // inherited) but still report as inaccessible, not unresolved
                // (KUU-3766).
                if let calleeName,
                   let privateMember = driver.helpers.inaccessiblePrivateImplicitReceiverMember(
                       named: calleeName, ctx: ctx
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: privateMember,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.sema.diagnostics
                    )
                } else {
                    let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0023",
                        "Unresolved function '\(nameStr)'.",
                        range: range
                    )
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if sema.symbols.externalLinkName(for: chosen) == "__kk_deep_recursive_function_new" {
                for argument in args {
                    if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                        sema.bindings.markRawSuspendEntryLambdaExpr(argument.expr)
                    }
                }
            }
            if let externalLinkName = sema.symbols.externalLinkName(for: chosen),
               externalLinkName == "kk_with_timeout" || externalLinkName == "kk_with_timeout_or_null_throwing",
               let coroutineScopeType = coroutineScopeType(sema: sema, interner: interner)
            {
                for argument in args {
                    if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                        sema.bindings.markCoroutineLauncherLambdaExpr(argument.expr)
                        sema.bindings.bindCoroutineScopeLambdaReceiverType(argument.expr, type: coroutineScopeType)
                    }
                }
            }
            contextualizeResolvedIntegerArguments(args: args, resolved: resolved, ctx: ctx, locals: &locals)
            if resolvedTypeNameInvokeCandidates.contains(chosen),
               let typeNameCompanionInvokeReceiverType
            {
                _ = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: typeNameCompanionInvokeReceiverType
                )
                sema.bindings.markInvokeOperatorCall(id)
            }
            // KSP-1543: source-backed channelFlow/callbackFlow still use the
            // launcher continuation ABI for their suspend ProducerScope receiver.
            // KSP-1583: the bundled kotlinx.coroutines.test.runTest extern uses
            // the same convention for its suspend TestScope receiver. Mark the
            // lambda only after overload resolution selects the bundled
            // declaration, so a same-named user function keeps the regular ABI.
            markSourceBackedCoroutineLauncherArguments(chosen, args: args, ctx: ctx)
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: sema,
                interner: interner,
                range: range,
                diagnostics: ctx.sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: chosen,
                constructorTypeAlias: constructorTypeAlias,
                ctx: ctx,
                range: range,
                diagnostics: ctx.sema.diagnostics
            )
            let importedDispatchReceiver = importedObjectDispatchReceiverOwners(
                named: calleeName,
                candidates: [chosen],
                ctx: ctx
            )[chosen]
            let companionDispatchReceiver = ctx.inheritedCompanionReceiver(for: chosen).flatMap { companion -> SymbolID? in
                guard let resolvedImplicitReceiverType,
                      case let .classType(receiverClass) = sema.types.kind(
                          of: sema.types.makeNonNullable(resolvedImplicitReceiverType)
                      ),
                      sema.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: companion)
                else {
                    return nil
                }
                return companion
            }
            let contextParameterReceiverSymbols = contextParameterReceiverSymbols(
                for: chosen,
                substitution: resolved.substitutedTypeArguments,
                ctx: ctx
            )
            let returnType = bindCallAndResolveReturnType(
                id,
                chosen: chosen,
                resolved: resolved,
                sema: sema,
                dispatchReceiverSymbol: importedDispatchReceiver ?? companionDispatchReceiver,
                contextParameterReceiverSymbols: contextParameterReceiverSymbols
            )
            if sema.wellKnownSymbols.isContractIntrinsic(for: chosen) {
                // The contract DSL is compiler-only, but only after ordinary
                // overload resolution selects kotlin.contracts.contract.
                sema.bindings.markStdlibSpecialCallExpr(id, kind: .contract)
            }
            if let extensionReceiverSymbol = memberExtensionReceiverMarks[chosen] {
                sema.bindings.markImplicitExtensionReceiver(id, symbol: extensionReceiverSymbol)
            } else if sema.bindings.implicitExtensionReceiver(for: id) == nil,
                      sema.symbols.memberExtensionOwnerSymbol(for: chosen) != nil,
                      let signature = sema.symbols.functionSignature(for: chosen),
                      let declaredReceiver = signature.receiverType,
                      let receiver = ctx.implicitReceiverMemberLookupEntries().first(where: {
                          let substituted = sema.types.substituteTypeParameters(
                              in: declaredReceiver,
                              substitution: resolved.substitutedTypeArguments,
                              typeVarBySymbol: sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                          )
                          return sema.types.isSubtype(sema.types.makeNonNullable($0.type), sema.types.makeNonNullable(substituted))
                      }), let symbol = receiver.symbol {
                // Scope lookup can resolve a member extension without passing
                // through the receiver-tower fallback. Preserve its extension
                // receiver identity separately from the lexical dispatch owner.
                sema.bindings.markImplicitExtensionReceiver(id, symbol: symbol)
            }
            if sema.bindings.implicitReceiverOuterReceiver(for: id) == nil,
               let owner = sema.symbols.memberExtensionOwnerSymbol(for: chosen),
               let outerEntry = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                   driver.helpers.allNominalSymbols(
                       of: entry.type,
                       types: sema.types,
                       symbols: sema.symbols,
                       interner: interner
                   ).contains { root in
                       root == owner || sema.types.isNominalSubtypeSymbol(root, of: owner)
                   }
               }),
               let receiverSymbol = outerEntry.symbol
            {
                // Scope lookup records a member extension's extension receiver
                // above, but KIR also needs the lexical owner for its dispatch
                // receiver slot when an inner receiver lambda shadows `this`.
                sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
            }
            if let calleeName, let receiverType = callImplicitReceiverType,
               let owner = sema.symbols.parentSymbol(for: chosen),
               let receiverClass = resolveClassType(receiverType, sema: sema),
               sema.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
            {
                sema.bindings.markImplicitReceiverMember(id, name: calleeName)
            }
            // Kotlin member scope: a `private` member is not inherited, so a
            // bare call reaching it from a subtype body (e.g. `object : X()`
            // nested in `X`) dispatches on the enclosing instance that
            // declares it — `this@X` — never the subtype's `this`. The scope
            // chain still surfaces the callee; pin that outer receiver so KIR
            // lowering reads the captured `this@X` instead of the active
            // receiver, whose inherited same-named slot would shadow the
            // enclosing value (KUU-3212).
            if let chosenInfo = sema.symbols.symbol(chosen),
               chosenInfo.kind == .function,
               chosenInfo.visibility == .private,
               sema.symbols.memberExtensionOwnerSymbol(for: chosen) == nil,
               sema.bindings.implicitReceiverOuterReceiver(for: id) == nil,
               let owner = sema.symbols.parentSymbol(for: chosen),
               let outerEntry = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                   driver.helpers.nominalSymbol(
                       of: sema.types.makeNonNullable(entry.type),
                       types: sema.types
                   ) == owner
               }),
               let receiverSymbol = outerEntry.symbol
            {
                sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
            }
            // Scope lookup can resolve an outer member or package extension
            // before the receiver tower fallback runs. Preserve the selected
            // receiver for capture analysis, including builtin receivers
            // such as String that have no nominal dispatch owner.
            if sema.symbols.memberExtensionOwnerSymbol(for: chosen) == nil,
               sema.bindings.implicitReceiverOuterReceiver(for: id) == nil,
               sema.symbols.functionSignature(for: chosen)?.receiverType != nil,
               let resolvedImplicitReceiverType,
               let outerReceiver = ctx.implicitReceiverMemberLookupEntries().first(where: { receiver in
                   // Use the resolver's actual receiver, not the declaration's
                   // generic receiver before type argument substitution.
                   receiver.type == resolvedImplicitReceiverType
               }),
               let receiverSymbol = outerReceiver.symbol
            {
                sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
            }
            let adjustedReturnType: TypeID = if let calleeName,
                let blockArgument = args.first(where: { $0.label == interner.intern("block") }) ?? args.last,
                isCoroutineBuilderCandidate(chosen)
                    || calleeName == knownNames.coroutineScope || calleeName == knownNames.supervisorScope
            {
                coroutineBuilderNarrowedReturnType(
                    id: id,
                    launcherName: interner.resolve(calleeName),
                    lambdaArgExpr: blockArgument.expr,
                    fallback: returnType,
                    ast: ast,
                    sema: sema
                )
            } else {
                returnType
            }
            if let implicitReceiverType = ctx.implicitReceiverType {
                markCoroutineScopeImplicitReceiverCallIfNeeded(
                    id,
                    chosenCallee: chosen,
                    receiverType: implicitReceiverType,
                    ctx: ctx
                )
            }
            applyContractEffects(
                id: id,
                chosen: chosen,
                args: args,
                ctx: ctx,
                locals: &locals
            )
            if let calleeName {
                let resolvedName = interner.resolve(calleeName)
                if KnownCompilerNames.stdlibCollectionFactoryNames.contains(resolvedName),
                   !KnownCompilerNames.arrayFactoryFunctionNames.contains(resolvedName),
                   let symbol = sema.symbols.symbol(chosen),
                   (symbol.fqName.starts(with: [knownNames.kotlin, knownNames.collections])
                       || symbol.fqName.starts(with: [knownNames.kotlin, knownNames.sequences]))
                {
                    sema.bindings.markCollectionExpr(id)
                }
            }
            let isRangeCallBinding = if let externalLinkName = sema.symbols.externalLinkName(for: chosen) {
                [
                    "__kk_op_rangeTo",
                    "__kk_op_rangeUntil",
                    "__kk_uint_rangeTo",
                    "__kk_ulong_rangeTo",
                    "__kk_char_rangeTo",
                    "__kk_int_progression_fromClosedRange",
                    "__kk_long_progression_fromClosedRange",
                    "__kk_uint_progression_fromClosedRange",
                    "__kk_ulong_progression_fromClosedRange",
                    "__kk_op_ulong_rangeUntil",
                ].contains(externalLinkName)
            } else if let symbol = sema.symbols.symbol(chosen) {
                // Source-backed range constructors have no external link. Keep
                // the range markers in sync so later member lookup and lowering
                // can recognize the returned UIntRange/UIntProgression value.
                ["rangeTo", "until", "rangeUntil", "downTo", "step", "fromClosedRange"].contains(
                    interner.resolve(symbol.name)
                ) && driver.helpers.isRangeLikeType(adjustedReturnType, sema: sema, interner: interner)
            } else {
                false
            }
            if isRangeCallBinding {
                markRangeCallBindings(id, chosen: chosen, returnType: adjustedReturnType, sema: sema)
            }
            sema.bindings.bindExprType(id, type: adjustedReturnType)
            return adjustedReturnType
        }
        return nil
    }

    func contextParameterReceiverSymbols(
        for callee: SymbolID,
        substitution: [TypeVarID: TypeID],
        ctx: TypeInferenceContext
    ) -> [SymbolID?] {
        guard let signature = ctx.sema.symbols.functionSignature(for: callee),
              !signature.contextParameterTypes.isEmpty
        else {
            return []
        }

        var candidates: [(type: TypeID, symbol: SymbolID)] = []
        if let enclosingFunction = ctx.enclosingFunctionSymbol ?? ctx.currentDeclSymbol,
           let enclosingSignature = ctx.sema.symbols.functionSignature(for: enclosingFunction)
        {
            candidates.append(contentsOf: zip(
                enclosingSignature.contextParameterTypes,
                enclosingSignature.contextParameterSymbols
            ).map { (type: $0.0, symbol: $0.1) })
        }
        candidates.append(contentsOf: ctx.implicitReceiverStack.reversed())
        candidates.append(contentsOf: ctx.outerReceiverTypes.reversed().compactMap { receiver in
            receiver.symbol.map { (type: receiver.type, symbol: $0) }
        })
        candidates.append(contentsOf: ctx.implicitReceiverMemberLookupEntries().compactMap { receiver in
            receiver.symbol.map { (type: receiver.type, symbol: $0) }
        })

        let typeVariables = ctx.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        return signature.contextParameterTypes.map { requestedType in
            let resolvedType = ctx.sema.types.substituteTypeParameters(
                in: requestedType,
                substitution: substitution,
                typeVarBySymbol: typeVariables
            )
            let targetType = ctx.sema.types.makeNonNullable(resolvedType)
            return candidates.first { candidate in
                ctx.sema.types.isSubtype(
                    ctx.sema.types.makeNonNullable(candidate.type),
                    targetType
                )
            }?.symbol
        }
    }
}
