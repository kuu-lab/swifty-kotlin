// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Main overload-resolution pass for `inferCallExpr`: resolves the
/// collected candidates against the prepared argument types, recovering
/// coroutine-builder result types and applying coroutine/launcher and
/// deprecation semantics.
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
extension CallTypeChecker {
    func resolveCallExprCandidates(
        _ id: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        candidates: [SymbolID],
        callImplicitReceiverType: TypeID?,
        memberExtensionReceiverMarks: [SymbolID: SymbolID],
        mergedImplicitReceiverMembers: [SymbolID],
        expectedTypeOverrides: [Int: TypeID],
        preparedArgs: PreparedCallArguments,
        argTypes: [TypeID]
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if !candidates.isEmpty {
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
            let isCoroutineBuilderWithHardcodedAnyReturn = candidates.contains { candidate in
                isCoroutineBuilderCandidate(candidate)
                    && sema.symbols.externalLinkName(for: candidate) != "kk_with_timeout"
                    && sema.symbols.externalLinkName(for: candidate) != "kk_with_timeout_or_null_throwing"
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
                return candidates.contains { candidate in
                    sema.symbols.parentSymbol(for: candidate) == outerClass
                }
            }?.type ?? candidates.lazy.compactMap { candidate -> TypeID? in
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
                candidates: candidates,
                args: args,
                originalExpectedTypeOverrides: expectedTypeOverrides,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                ctx: ctx,
                locals: locals
            )
            var resolved = resolveCallRespectingLambdaReturnType(
                candidates: candidates,
                args: args,
                argTypes: argTypes,
                range: range,
                calleeName: calleeName ?? InternedString(),
                explicitTypeArgs: explicitTypeArgs,
                expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                implicitReceiverType: callImplicitReceiverType,
                candidateArgumentTypes: candidateSpecificNestedCallTypes?.argumentTypesByCandidate ?? [:],
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx
            )
            if resolved.diagnostic != nil {
                if let calleeName,
                   let recovered = tryBindImplicitReceiverMemberCallForInapplicableScopeCandidates(
                       id,
                       calleeName: calleeName,
                       args: args,
                       argTypes: argTypes,
                       range: range,
                       explicitTypeArgs: explicitTypeArgs,
                       expectedType: expectedType,
                       scopeCandidates: candidates,
                       ctx: ctx
                   )
                {
                    return recovered
                }
                if resolved.diagnostic != nil,
                   mergedImplicitReceiverMembers.count == 1,
                   let bestCandidate = mergedImplicitReceiverMembers.first,
                   let signature = sema.symbols.functionSignature(for: bestCandidate),
                   let calleeName
                {
                    // The merged implicit-receiver member failed constraint
                    // solving — e.g. `FlowCollector<R>.emit` inside
                    // `transform`, where `R` is an outer call's type parameter
                    // opaque to this resolver. The general member path below
                    // would still bind such a lone member leniently; mirror
                    // that fallback here so the call is not hard-errored.
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
                if resolved.diagnostic?.code == "KSWIFTK-SEMA-0002",
                   let calleeName,
                   let recovered = resolveOuterImplicitReceiverExtensionCall(
                       candidates: candidates,
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
                        ctx.semaCtx.diagnostics.emit(diagnostic)
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
                       candidates: candidates,
                       args: args,
                       argTypes: argTypes,
                       range: range,
                       calleeName: calleeName ?? InternedString(),
                       explicitTypeArgs: explicitTypeArgs,
                       expectedType: isCoroutineBuilderWithHardcodedAnyReturn ? nil : expectedType,
                       implicitReceiverType: ctx.implicitReceiverType,
                       lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                       inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                       blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                       hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                       ctx: ctx,
                       locals: &locals
                   ) {
                    resolved = retried
                }
            }
            if resolved.diagnostic == nil,
               let chosen = resolved.chosenCallee,
               let expectedTypes = candidateSpecificNestedCallTypes?.expectedTypesByCandidate[chosen]
            {
                for (index, expectedArgumentType) in expectedTypes.sorted(by: { $0.key < $1.key }) {
                    _ = driver.inferExpr(
                        args[index].expr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: expectedArgumentType
                    )
                }
            }
            if let diagnostic = resolved.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            guard let chosen = resolved.chosenCallee else {
                let nameStr = calleeName.map { interner.resolve($0) } ?? "<unknown>"
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0023",
                    "Unresolved function '\(nameStr)'.",
                    range: range
                )
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
            // KSP-1543: source-backed channelFlow/callbackFlow still use the
            // launcher continuation ABI for their suspend ProducerScope receiver.
            // KSP-1583: the bundled kotlinx.coroutines.test.runTest extern uses
            // the same convention for its suspend TestScope receiver. Mark the
            // lambda only after overload resolution selects the bundled
            // declaration, so a same-named user function keeps the regular ABI.
            if isSourceBackedProducerFlowBuilder(chosen, ctx: ctx)
            {
                for argument in args {
                    if case .lambdaLiteral = ast.arena.expr(argument.expr) {
                        sema.bindings.markCoroutineLauncherLambdaExpr(argument.expr)
                    }
                }
            }
            // ANNO-001: Check for @Deprecated annotation on the resolved callee.
            driver.helpers.checkDeprecation(
                for: chosen,
                sema: sema,
                interner: interner,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: chosen,
                ctx: ctx,
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
            if let extensionReceiverSymbol = memberExtensionReceiverMarks[chosen] {
                sema.bindings.markImplicitExtensionReceiver(id, symbol: extensionReceiverSymbol)
            }
            if let calleeName, let receiverType = callImplicitReceiverType,
               let owner = sema.symbols.parentSymbol(for: chosen),
               let receiverClass = resolveClassType(receiverType, sema: sema),
               sema.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
            {
                sema.bindings.markImplicitReceiverMember(id, name: calleeName)
            }
            // Scope lookup can resolve an inherited outer member before the
            // receiver tower fallback runs. Preserve the actual enclosing
            // instance for capture analysis even when its class differs from
            // the member's declaring class.
            if sema.symbols.memberExtensionOwnerSymbol(for: chosen) == nil,
               sema.symbols.functionSignature(for: chosen)?.receiverType != nil,
               let owner = sema.symbols.parentSymbol(for: chosen),
               let activeType = ctx.implicitReceiverType,
               resolveClassType(activeType, sema: sema).map({
                   sema.types.isNominalSubtypeSymbol($0.classSymbol, of: owner)
               }) != true,
               let outerReceiver = ctx.outerReceiverTypes.reversed().first(where: { receiver in
                   receiver.symbol != nil && resolveClassType(receiver.type, sema: sema).map {
                       sema.types.isNominalSubtypeSymbol($0.classSymbol, of: owner)
                   } == true
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
                   !KnownCompilerNames.arrayFactoryFunctionNames.contains(resolvedName)
                {
                    sema.bindings.markCollectionExpr(id)
                }
            }
            let isRangeCallBinding = if let externalLinkName = sema.symbols.externalLinkName(for: chosen) {
                [
                    "kk_op_rangeTo",
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
}
