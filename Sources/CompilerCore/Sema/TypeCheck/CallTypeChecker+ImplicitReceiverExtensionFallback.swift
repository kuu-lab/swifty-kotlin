extension CallTypeChecker {
    func implicitReceiverEntryNullabilityCompatible(
        callSiteReceiver: TypeID,
        declaredReceiver: TypeID,
        sema: SemaModule
    ) -> Bool {
        guard sema.types.nullability(of: callSiteReceiver) == .nullable else { return true }
        if sema.types.isSubtype(callSiteReceiver, declaredReceiver) {
            return true
        }
        guard case let .typeParam(parameter) = sema.types.kind(
            of: sema.types.makeNonNullable(declaredReceiver)
        ) else {
            return false
        }
        return sema.symbols.typeParameterUpperBounds(for: parameter.symbol).allSatisfy { bound in
            sema.types.nullabilitySubtype(
                sema.types.nullability(of: callSiteReceiver),
                sema.types.nullability(of: bound)
            )
        }
    }

    func isUnsafeNullableImplicitReceiverCall(
        _ candidate: SymbolID,
        supplyingReceiverType: TypeID,
        argCount: Int,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard sema.types.nullability(of: supplyingReceiverType) == .nullable,
              let signature = sema.symbols.functionSignature(for: candidate),
              let declaredReceiver = signature.receiverType,
              !implicitReceiverEntryNullabilityCompatible(
                  callSiteReceiver: supplyingReceiverType,
                  declaredReceiver: declaredReceiver,
                  sema: sema
              )
        else { return false }
        guard sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
              let name = sema.symbols.symbol(candidate)?.name
        else { return true }
        let knownNames = KnownCompilerNames(interner: interner)
        switch name {
        case knownNames.toString, knownNames.hashCode:
            return argCount != 0
        case knownNames.equals:
            return argCount != 1
        default:
            return true
        }
    }

    func implicitMemberExtensionReceiverMatches(_ actual: TypeID, declared: TypeID, sema: SemaModule) -> Bool {
        guard implicitReceiverEntryNullabilityCompatible(
            callSiteReceiver: actual,
            declaredReceiver: declared,
            sema: sema
        ) else {
            return false
        }
        let actual = sema.types.makeNonNullable(actual)
        let declared = sema.types.makeNonNullable(declared)
        if sema.types.isSubtype(actual, declared) { return true }
        guard case let .typeParam(parameter) = sema.types.kind(of: declared) else { return false }
        let variables = sema.types.makeTypeVarBySymbol([parameter.symbol])
        guard let variable = variables[parameter.symbol] else { return false }
        return sema.symbols.typeParameterUpperBounds(for: parameter.symbol).allSatisfy { bound in
            let bound = sema.types.substituteTypeParameters(
                in: bound, substitution: [variable: actual], typeVarBySymbol: variables
            )
            return sema.types.isSubtype(actual, sema.types.makeNonNullable(bound))
        }
    }
    func scopeCallCandidatesConsideringImplicitReceivers(
        named name: InternedString,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let samePackage = ctx.currentASTFile?.packageFQName
        func isNonCallableProperty(_ candidate: SymbolID) -> Bool {
            guard let symbol = ctx.cachedSymbol(candidate), symbol.kind == .property,
                  let type = ctx.sema.symbols.propertyType(for: candidate)
            else { return false }
            if case .functionType = ctx.sema.types.kind(of: ctx.sema.types.makeNonNullable(type)) {
                return false
            }
            return driver.helpers.collectMemberFunctionCandidates(
                named: ctx.interner.intern("invoke"), receiverType: type, sema: ctx.sema, interner: ctx.interner
            ).isEmpty
        }
        let callableCandidates = ctx.scope.lookup(name, matching: { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  !ctx.isExpectDeclarationSupersededByActual(candidate),
                  !ctx.isImportedSymbolShadowedBySource(candidate)
            else { return false }
            if symbol.kind == .property {
                if isNonCallableProperty(candidate) { return false }
                if let samePackage, Array(symbol.fqName.dropLast()) == samePackage {
                    return false
                }
            }
            return true
        })
        let candidates = scopeCallCandidatesWithExplicitImportOverloads(
            named: name,
            candidates: callableCandidates,
            ctx: ctx
        )
        guard !candidates.isEmpty else { return candidates }
        func matchesReceiver(_ candidate: SymbolID, receiverType: TypeID) -> Bool {
            guard let receiver = ctx.sema.symbols.functionSignature(for: candidate)?.receiverType
            else { return false }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: receiver,
                sema: ctx.sema
            )
        }
        guard candidates.allSatisfy({ ctx.sema.symbols.functionSignature(for: $0)?.receiverType != nil }) else {
            return candidates
        }
        let scopeExtensionsOnly = candidates.allSatisfy { isScopeExtensionCandidate($0, ctx: ctx) }
        for entry in ctx.implicitReceiverMemberLookupEntries() {
            let applicable = candidates.filter { matchesReceiver($0, receiverType: entry.type) }
            if !applicable.isEmpty {
                return applicable
            }
            if scopeExtensionsOnly {
                let matchingScopeCandidates = ctx.scope.lookup(name, matching: { candidate in
                    isScopeExtensionCandidate(candidate, ctx: ctx)
                        && matchesReceiver(candidate, receiverType: entry.type)
                })
                if !matchingScopeCandidates.isEmpty {
                    return matchingScopeCandidates
                }
            }
        }
        return candidates
    }

    private func scopeCallCandidatesWithExplicitImportOverloads(
        named name: InternedString,
        candidates: [SymbolID],
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        guard let file = ctx.currentASTFile else {
            return candidates
        }
        let matchingImports = file.imports.filter {
            !$0.isWildcard && ($0.alias ?? $0.path.last) == name
        }
        guard !matchingImports.isEmpty,
              candidates.contains(where: { candidate in
                  guard let symbol = sema.symbols.symbol(candidate),
                        symbol.kind == .function,
                        !symbol.flags.contains(.localFunction),
                        Array(symbol.fqName.dropLast()) == file.packageFQName,
                        let signature = sema.symbols.functionSignature(for: candidate)
                  else {
                      return false
                  }
                  return signature.receiverType == nil
              })
        else {
            return candidates
        }

        var result = candidates
        var seen = Set(candidates)
        for importDecl in matchingImports {
            for imported in sema.symbols.lookupAll(fqName: importDecl.path) {
                guard let symbol = sema.symbols.symbol(imported),
                      symbol.kind == .function,
                      !ctx.isExpectDeclarationSupersededByActual(imported),
                      let signature = sema.symbols.functionSignature(for: imported),
                      signature.receiverType == nil,
                      seen.insert(imported).inserted
                else {
                    continue
                }
                result.append(imported)
            }
        }
        return result
    }

    func isScopeExtensionCandidate(_ candidate: SymbolID, ctx: TypeInferenceContext) -> Bool {
        guard let symbol = ctx.sema.symbols.symbol(candidate),
              symbol.kind == .function,
              ctx.sema.symbols.functionSignature(for: candidate)?.receiverType != nil,
              ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil
        else { return false }
        if let parentID = ctx.sema.symbols.parentSymbol(for: candidate),
           let parent = ctx.sema.symbols.symbol(parentID),
           parent.kind != .package
        {
            return symbol.fqName != parent.fqName + [symbol.name]
        }
        return true
    }

    func callCandidateDeclaredReceiver(
        _ candidate: SymbolID,
        matchesTowerEntryType entryType: TypeID,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard let declaredReceiver = ctx.sema.symbols.functionSignature(for: candidate)?.receiverType
        else { return false }
        if ctx.sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil {
            return implicitMemberExtensionReceiverMatches(
                entryType, declared: declaredReceiver, sema: ctx.sema
            )
        }
        return extensionSyntheticFallbackReceiverMatches(
            callSiteReceiver: entryType,
            declaredReceiver: declaredReceiver,
            sema: ctx.sema
        )
    }

    func isCallCandidateBlockedByDslHiddenReceivers(
        _ candidate: SymbolID,
        hiddenReceiverTypes: Set<TypeID>,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard !hiddenReceiverTypes.isEmpty,
              ctx.sema.symbols.functionSignature(for: candidate)?.receiverType != nil
        else { return false }
        var sawMatchingEntry = false
        for entry in ctx.implicitReceiverMemberLookupEntries()
        where callCandidateDeclaredReceiver(candidate, matchesTowerEntryType: entry.type, ctx: ctx) {
            guard hiddenReceiverTypes.contains(entry.type) else { return false }
            sawMatchingEntry = true
        }
        return sawMatchingEntry
    }

    func resolveOuterImplicitReceiverExtensionCall(
        candidates: [SymbolID],
        args: [CallArgument],
        preparedArgs: PreparedCallArguments,
        range: SourceRange,
        calleeName: InternedString,
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        ctx: TypeInferenceContext
    ) -> (resolved: ResolvedCall, receiverSymbol: SymbolID)? {
        let extensions = candidates.filter { isScopeExtensionCandidate($0, ctx: ctx) }
        guard !extensions.isEmpty else { return nil }
        let dslHiddenReceiverTypes = ctx.dslHiddenImplicitReceiverTypes()
        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            guard let symbol = receiver.symbol,
                  !dslHiddenReceiverTypes.contains(receiver.type)
            else { continue }
            let resolved = resolveCallRespectingLambdaReturnType(
                candidates: extensions,
                args: args,
                argTypes: preparedArgs.argTypes,
                range: range,
                calleeName: calleeName,
                explicitTypeArgs: explicitTypeArgs,
                expectedType: expectedType,
                implicitReceiverType: receiver.type,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx
            )
            // Ambiguity at a nearer receiver must not fall through to a farther one.
            if resolved.chosenCallee != nil || resolved.diagnostic?.code == "KSWIFTK-SEMA-0003" {
                return (resolved, symbol)
            }
        }
        return nil
    }

    func preferImplicitReceiverPredicateCandidates(
        _ candidates: [SymbolID],
        fallbackCandidates: [SymbolID] = [],
        args: [CallArgument],
        receiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        let lambdaIndices = args.indices.filter { index in
            ctx.ast.arena.expr(args[index].expr)?.isLambdaOrCallableRef == true
        }
        guard !lambdaIndices.isEmpty else { return candidates }

        func preferredCandidates(in candidates: [SymbolID]) -> [SymbolID]? {
            let receiverCandidates = candidates.filter { candidate in
                guard let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType else {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: receiver,
                    sema: sema
                )
            }
            let predicateCandidates = receiverCandidates.filter { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return false
                }
                return lambdaIndices.allSatisfy { index in
                    guard let parameterType = parameterTypeForArgument(at: index, in: signature) else {
                        return false
                    }
                    return if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                        true
                    } else {
                        false
                    }
                }
            }
            guard !predicateCandidates.isEmpty else { return nil }
            return preferMostSpecificMemberReceiverCandidates(
                predicateCandidates,
                receiverType: nonNullReceiver,
                sema: sema,
                interner: ctx.interner
            )
        }

        if let preferred = preferredCandidates(in: candidates) {
            return preferred
        }

        let hasFunctionTypedLambdaParameter = candidates.contains { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            return lambdaIndices.allSatisfy { index in
                guard let parameterType = parameterTypeForArgument(at: index, in: signature) else {
                    return false
                }
                return if case .functionType = sema.types.kind(of: sema.types.makeNonNullable(parameterType)) {
                    true
                } else {
                    false
                }
            }
        }
        guard !hasFunctionTypedLambdaParameter,
              let preferred = preferredCandidates(in: fallbackCandidates)
        else {
            return candidates
        }
        return preferred
    }

    func tryBindImplicitReceiverCollectionMemberCall(
        _ id: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else { return nil }
        guard locals[calleeName] == nil else { return nil }
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        let name = ctx.interner.resolve(calleeName)
        guard name == "remove" || name == "iterator" || name == "contains" else { return nil }
        guard !args.contains(where: { ctx.ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }) else {
            return nil
        }
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: ctx.interner)
        guard name == "contains" || receiverClassifier.isCollectionLikeType(nonNullReceiver) else { return nil }

        var candidates = driver.helpers.collectMemberFunctionCandidates(
            named: calleeName,
            receiverType: nonNullReceiver,
            sema: sema,
            interner: ctx.interner
        )
        guard !candidates.isEmpty else { return nil }
        let usesMutableCollectionIterator = name == "iterator"
            && (
                receiverClassifier.isMutableListCollectionType(nonNullReceiver)
                    || receiverClassifier.isMutableSetType(nonNullReceiver)
                    || receiverClassifier.isMutableCollectionType(nonNullReceiver)
            )
        if usesMutableCollectionIterator {
            let runtimeIteratorCandidates = sema.symbols.lookupByShortName(calleeName).filter { candidate in
                guard sema.symbols.externalLinkName(for: candidate) == "kk_list_iterator",
                      let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType
                else {
                    return false
                }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: receiver,
                    sema: sema
                )
            }
            if let runtimeIteratorCandidate = runtimeIteratorCandidates.first {
                candidates = [runtimeIteratorCandidate]
            }
        }

        let preparedArgs = prepareCallArguments(
            args: args,
            callRange: range,
            candidates: candidates,
            explicitTypeArgs: explicitTypeArgs,
            receiverType: nonNullReceiver,
            ctx: ctx,
            locals: &locals
        )
        let resolved = resolveCallRespectingLambdaReturnType(
            candidates: candidates,
            args: args,
            argTypes: preparedArgs.argTypes,
            range: range,
            calleeName: calleeName,
            explicitTypeArgs: explicitTypeArgs,
            expectedType: overloadResolutionExpectedType(from: expectedType, sema: sema),
            implicitReceiverType: receiverType,
            lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
            inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
            blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
            hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
            ctx: ctx
        )
        guard resolved.diagnostic == nil,
              let chosen = resolved.chosenCallee
        else { return nil }

        driver.helpers.checkDeprecation(
            for: chosen,
            sema: sema,
            interner: ctx.interner,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: ctx,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        let boundResultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        var resultType = boundResultType
        if usesMutableCollectionIterator,
           let mutableIteratorSymbol = sema.symbols.lookup(fqName: [
               ctx.interner.intern("kotlin"),
               ctx.interner.intern("collections"),
               ctx.interner.intern("MutableIterator"),
           ]) {
            let elementType = getCollectionElementType(
                nonNullReceiver,
                sema: sema,
                interner: ctx.interner
            )
            resultType = sema.types.make(.classType(ClassType(
                classSymbol: mutableIteratorSymbol,
                args: [.out(elementType)],
                nullability: .nonNull
            )))
        }
        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
        markCoroutineScopeImplicitReceiverCallIfNeeded(
            id,
            chosenCallee: chosen,
            receiverType: receiverType,
            ctx: ctx
        )
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    func tryBindImplicitReceiverSyntheticExtensionCall(
        _ id: ExprID,
        calleeName: InternedString,
        receiverType: TypeID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID]
    ) -> TypeID? {
        let sema = ctx.sema
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        var seen: Set<SymbolID> = []

        func matches(_ candidate: SymbolID, requireSynthetic: Bool) -> Bool {
            guard seen.insert(candidate).inserted,
                  let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  requireSynthetic == false || symbol.flags.contains(.synthetic),
                  requireSynthetic == false || !symbol.flags.contains(.importedLibrary),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let receiver = signature.receiverType
            else { return false }
            if let parentID = sema.symbols.parentSymbol(for: candidate),
               let parent = sema.symbols.symbol(parentID),
               parent.kind == .property
            {
                return false
            }
            // Match against the original receiver type, not its non-null
            // core: a nullable implicit receiver must not satisfy a non-null
            // extension declaration (KUU-4501).
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: receiver,
                sema: sema
            )
        }

        // Ordinary name lookup stops at the innermost scope tier that binds
        // the name, so a same-named extension declared in the current package
        // hides every outer-tier (star/default-import) extension on the same
        // implicit receiver — e.g. `Instant.plus(Duration)` from
        // `kotlin.time.*` behind a package-level `Instant.plus(TimeBased)`
        // (KUU-4276). This recovery runs only after scope-candidate
        // resolution already failed, so merge the whole scope chain and let
        // overload resolution pick the applicable outer-tier declaration,
        // mirroring the explicit-receiver extension fallback.
        var candidates = ctx.scope.lookupMergingChain(calleeName).filter {
            !ctx.isExpectDeclarationSupersededByActual($0)
                && !ctx.isImportedSymbolShadowedBySource($0)
                && matches($0, requireSynthetic: false)
        }
        let visibleExtensions = ctx.scope.lookupMergingChain(calleeName).filter { candidate in
            guard isScopeExtensionCandidate(candidate, ctx: ctx),
                  let symbol = ctx.cachedSymbol(candidate),
                  ctx.visibilityChecker.isAccessible(
                      symbol, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
                  ),
                  let receiver = sema.symbols.functionSignature(for: candidate)?.receiverType
            else { return false }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType, declaredReceiver: receiver, sema: sema
            )
        }
        candidates.append(contentsOf: visibleExtensions.filter {
            matches($0, requireSynthetic: false)
        })
        candidates.append(contentsOf: sema.symbols.lookupByShortName(calleeName).filter {
            matches($0, requireSynthetic: true)
        })
        let bundledCandidates = collectBundledStdlibExtensionCandidates(
            named: calleeName,
            receiverType: nonNullReceiver,
            sourceFile: ctx.currentASTFile,
            sema: sema,
            interner: ctx.interner
        )
        if !bundledCandidates.isEmpty {
            candidates = bundledCandidates
        }
        candidates = ctx.filterByVisibility(candidates).visible
        guard !candidates.isEmpty else { return nil }

        let argTypes = args.map { argument in
            driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            let literal = integerLiteralValues(argument.expr, ast: ctx.ast)
            return CallArg.source(
                argument, type: type, callRange: range, ast: ctx.ast,
                signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned
            )
        }
        // Preserve the existing lambda inference in this recovery path. Literal
        // values let the resolver narrow each viable numeric overload, without
        // re-contextualizing star-projected receiver lambdas as non-null Any.
        // The receiver constraint must run against the call site's real
        // nullability — re-resolving with the stripped receiver would let a
        // nullable implicit receiver bind a non-null extension receiver
        // without `?.` (KUU-4501).
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range, calleeName: calleeName, args: resolvedArgs,
                explicitTypeArgs: explicitTypeArgs,
                dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
            ),
            expectedType: overloadResolutionExpectedType(from: expectedType, sema: sema),
            implicitReceiverType: receiverType,
            ctx: ctx.sema
        )
        if let diagnostic = resolved.diagnostic {
            if sema.types.nullability(of: receiverType) == .nullable {
                let probe = ctx.resolver.resolveCall(
                    candidates: candidates,
                    call: CallExpr(
                        range: range, calleeName: calleeName, args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs,
                        dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                    ),
                    expectedType: nil,
                    implicitReceiverType: nonNullReceiver,
                    ctx: ctx.sema
                )
                if probe.chosenCallee != nil {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0026",
                        "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
            }
            ctx.sema.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else { return nil }

        contextualizeResolvedIntegerArguments(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        driver.helpers.checkDeprecation(
            for: chosen, sema: sema, interner: ctx.interner,
            range: range, diagnostics: ctx.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen, ctx: ctx, range: range, diagnostics: ctx.sema.diagnostics
        )
        let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        sema.bindings.markImplicitReceiverMember(id, name: calleeName)
        markCoroutineScopeImplicitReceiverCallIfNeeded(
            id,
            chosenCallee: chosen,
            receiverType: receiverType,
            ctx: ctx
        )
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    func tryBindImplicitReceiverMemberCallForInapplicableScopeCandidates(
        _ id: ExprID,
        calleeName: InternedString,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        explicitTypeArgs: [TypeID],
        expectedType: TypeID?,
        scopeCandidates: [SymbolID],
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        guard let implicitReceiverType = ctx.implicitReceiverType,
              !scopeCandidates.isEmpty,
              args.count == argTypes.count
        else { return nil }
        let nonNullReceiver = sema.types.makeNonNullable(implicitReceiverType)
        let scopeExtensions = Set(scopeCandidates.filter { isScopeExtensionCandidate($0, ctx: ctx) })

        var receiverChain: [(type: TypeID, symbol: SymbolID?)] = [
            (type: implicitReceiverType, symbol: nil)
        ]
        for outerReceiver in ctx.outerReceiverTypes.reversed() {
            let outerNonNullReceiver = sema.types.makeNonNullable(outerReceiver.type)
            guard let outerReceiverSymbol = outerReceiver.symbol,
                  outerNonNullReceiver != nonNullReceiver
            else {
                continue
            }
            receiverChain.append((type: outerReceiver.type, symbol: outerReceiverSymbol))
        }

        for receiver in receiverChain {
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: sema.types.makeNonNullable(receiver.type),
                sema: sema,
                interner: ctx.interner
            ).filter { !scopeExtensions.contains($0) }
            guard !memberCandidates.isEmpty else { continue }
            var regularMemberCandidates: [SymbolID] = []
            var memberExtensionGroups: [(
                symbols: [SymbolID], receiverType: TypeID, symbol: SymbolID?
            )] = []
            for candidate in memberCandidates {
                guard let signature = sema.symbols.functionSignature(for: candidate),
                      sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil,
                      let declaredReceiver = signature.receiverType
                else {
                    regularMemberCandidates.append(candidate)
                    continue
                }
                guard let picked = ctx.implicitReceiverMemberLookupEntries().first(where: { entry in
                    implicitMemberExtensionReceiverMatches(entry.type, declared: declaredReceiver, sema: sema)
                })
                else { continue }
                if let groupIndex = memberExtensionGroups.firstIndex(where: {
                    $0.receiverType == picked.type
                }) {
                    memberExtensionGroups[groupIndex].symbols.append(candidate)
                } else {
                    memberExtensionGroups.append(([candidate], picked.type, picked.symbol))
                }
            }
            var orderedGroups: [(
                symbols: [SymbolID], receiverType: TypeID, extensionSymbol: SymbolID?
            )] = regularMemberCandidates.isEmpty
                ? []
                : [(regularMemberCandidates, sema.types.makeNonNullable(receiver.type), nil)]
            orderedGroups.append(
                contentsOf: memberExtensionGroups.map {
                    ($0.symbols, $0.receiverType, $0.symbol)
                }
            )
            let resolvedArgs = zip(args, argTypes).map { argument, type in
                CallArg.source(argument, type: type, callRange: range, ast: ctx.ast)
            }
            for group in orderedGroups {
                let resolved = ctx.resolver.resolveCall(
                    candidates: group.symbols,
                    call: CallExpr(
                        range: range,
                        calleeName: calleeName,
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs,
                        dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: group.receiverType,
                    ctx: ctx.sema
                )
                guard resolved.diagnostic == nil,
                      let chosen = resolved.chosenCallee,
                      !regularMemberCandidates.contains(chosen)
                          || !isUnsafeNullableImplicitReceiverCall(
                              chosen,
                              supplyingReceiverType: receiver.type,
                              argCount: args.count,
                              sema: sema,
                              interner: ctx.interner
                          )
                else { continue }

                let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
                sema.bindings.markImplicitReceiverMember(id, name: calleeName)
                if let receiverSymbol = receiver.symbol {
                    sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
                }
                if let extensionSymbol = group.extensionSymbol {
                    sema.bindings.markImplicitExtensionReceiver(id, symbol: extensionSymbol)
                }
                markCoroutineScopeImplicitReceiverCallIfNeeded(
                    id,
                    chosenCallee: chosen,
                    receiverType: receiver.type,
                    ctx: ctx
                )
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
        }
        return nil
    }
}
