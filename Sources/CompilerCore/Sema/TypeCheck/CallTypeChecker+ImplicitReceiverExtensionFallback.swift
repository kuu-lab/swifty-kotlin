extension CallTypeChecker {
    /// Prefer the receiver-specific predicate extension before contextual lambda
    /// inference. An implicit receiver call currently starts with package-scope
    /// candidates, so keeping the Collection overload beside the predicate
    /// overload leaves a bare `it` without a unique function type.
    func preferImplicitReceiverPredicateCandidates(
        _ candidates: [SymbolID],
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
        guard !predicateCandidates.isEmpty else { return candidates }
        return preferMostSpecificMemberReceiverCandidates(
            predicateCandidates,
            receiverType: nonNullReceiver,
            sema: sema,
            interner: ctx.interner
        )
    }

    /// Resolve collection members before package-scope extensions for an
    /// implicit receiver. This preserves Kotlin member precedence for calls such
    /// as `apply { remove(1) }` and avoids the deprecated `MutableList.remove`
    /// extension being selected first.
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
        guard name == "remove" || name == "iterator" else { return nil }
        guard !args.contains(where: { ctx.ast.arena.expr($0.expr)?.isLambdaOrCallableRef == true }) else {
            return nil
        }
        let receiverClassifier = ReceiverClassifier(sema: sema, interner: ctx.interner)
        guard receiverClassifier.isCollectionLikeType(nonNullReceiver) else { return nil }

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
            diagnostics: ctx.semaCtx.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            ctx: ctx,
            range: range,
            diagnostics: ctx.semaCtx.diagnostics
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
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let receiver = signature.receiverType
            else { return false }
            if let parentID = sema.symbols.parentSymbol(for: candidate),
               let parent = sema.symbols.symbol(parentID),
               parent.kind == .property
            {
                return false
            }
            return extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiver,
                declaredReceiver: receiver,
                sema: sema
            )
        }

        var candidates = ctx.cachedScopeLookup(calleeName).filter {
            matches($0, requireSynthetic: false)
        }
        candidates.append(contentsOf: sema.symbols.lookupByShortName(calleeName).filter {
            matches($0, requireSynthetic: true)
        })
        // Bundled stdlib source extensions are omitted from ordinary file scopes.
        // Prefer their source-backed declarations over residual synthetic members
        // when an atomic receiver exposes the migrated surface.
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
        guard !candidates.isEmpty else { return nil }

        let argTypes = args.map { argument in
            driver.inferExpr(argument.expr, ctx: ctx, locals: &locals)
        }
        let resolvedArgs = zip(args, argTypes).map { argument, type in
            CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
        }
        let resolved = ctx.resolver.resolveCall(
            candidates: candidates,
            call: CallExpr(
                range: range,
                calleeName: calleeName,
                args: resolvedArgs,
                explicitTypeArgs: explicitTypeArgs
            ),
            expectedType: expectedType,
            implicitReceiverType: nonNullReceiver,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else { return nil }

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

    /// Scope lookup for an unqualified call also returns package-scope extension
    /// functions that merely share the simple name but declare a receiver the
    /// enclosing implicit receiver cannot satisfy (e.g. `AtomicInt.compareAndSet`
    /// seen from an `AtomicBoolean` extension body), or whose arguments cannot
    /// be satisfied even though the receiver matches (e.g. the kotlin.text
    /// `T.append(vararg CharSequence?)` extension seen from an `Appendable`
    /// extension body calling `append('\n')`).  Scope-candidate resolution has
    /// already failed when this runs, so the call has to resolve against the
    /// implicit receiver's own members instead of failing overload resolution.
    /// Only recovers calls that would otherwise be reported as errors.
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

        // Kotlin's implicit-receiver tower: the innermost receiver first, then
        // enclosing receivers whose `this` value is reachable through capture.
        // Only entries carrying a receiver symbol participate — the symbol is
        // what capture analysis stores into an object literal's fields so KIR
        // lowering can materialize the receiver value from it.
        var receiverChain: [(type: TypeID, symbol: SymbolID?)] = [
            (type: nonNullReceiver, symbol: nil)
        ]
        for outerReceiver in ctx.outerReceiverTypes.reversed() {
            let outerNonNullReceiver = sema.types.makeNonNullable(outerReceiver.type)
            guard let outerReceiverSymbol = outerReceiver.symbol,
                  outerNonNullReceiver != nonNullReceiver
            else {
                continue
            }
            receiverChain.append((type: outerNonNullReceiver, symbol: outerReceiverSymbol))
        }

        for receiver in receiverChain {
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: receiver.type,
                sema: sema,
                interner: ctx.interner
            )
            guard !memberCandidates.isEmpty else { continue }
            let resolvedArgs = zip(args, argTypes).map { argument, type in
                CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: memberCandidates,
                call: CallExpr(
                    range: range,
                    calleeName: calleeName,
                    args: resolvedArgs,
                    explicitTypeArgs: explicitTypeArgs
                ),
                expectedType: expectedType,
                implicitReceiverType: receiver.type,
                ctx: ctx.semaCtx
            )
            guard resolved.diagnostic == nil,
                  let chosen = resolved.chosenCallee
            else { continue }

            let resultType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            sema.bindings.markImplicitReceiverMember(id, name: calleeName)
            if let receiverSymbol = receiver.symbol {
                sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: receiverSymbol)
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
        return nil
    }
}
