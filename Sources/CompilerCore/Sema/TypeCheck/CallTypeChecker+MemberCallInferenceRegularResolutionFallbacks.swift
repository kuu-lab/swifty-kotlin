// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// Resolution-failure fallbacks, extracted verbatim from
    /// `inferRegularMemberCall`. When overload resolution produced a
    /// diagnostic, retries through class-name static members, projection
    /// violations, the synthetic member fallbacks and the shadowed-extension /
    /// callable-property paths before emitting the error. `resolved` is updated
    /// in place when a nested-argument retry clears the diagnostic.
    /// Returns nil when no diagnostic was pending or a retry succeeded.
    func handleRegularMemberResolutionDiagnostic(
        _ request: MemberCallInferenceRequest,
        candidates: [SymbolID],
        preparedArgs: PreparedCallArguments,
        resolved: inout ResolvedCall,
        argTypes: [TypeID],
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        effectiveReceiverType: TypeID,
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        isSuperCall: Bool,
        locals: inout LocalBindings
    ) -> TypeID? {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let expectedType = request.expectedType
        let explicitTypeArgs = request.explicitTypeArgs
        let safeCall = request.safeCall
        let sema = ctx.sema
        let interner = ctx.interner

        if let diagnostic = resolved.diagnostic {
            if diagnostic.code == "KSWIFTK-SEMA-BOUND" {
                let callee = interner.resolve(calleeName)
                if callee == "sorted" || callee == "sortedDescending" {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
            }
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryRegexMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryKFunctionMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryStringMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryNativePlacementAllocExtensionFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                explicitTypeArgs: explicitTypeArgs,
                ctx: ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryNativeCInteropReadValueExtensionFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryFileMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryArrayMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRangeMemberFallback(
                id,
                calleeName: calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: safeCall,
                receiverID: receiverID,
                args: args,
                ctx: ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let retried = retryResolutionReinferringNestedCallArguments(
                candidates: candidates,
                args: args,
                argTypes: preparedArgs.argTypes,
                range: range,
                calleeName: calleeName,
                explicitTypeArgs: explicitTypeArgs,
                expectedType: expectedType,
                implicitReceiverType: effectiveReceiverType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: ctx,
                locals: &locals
            ) {
                resolved = retried
            }
            // KUU-946: an inapplicable member must not shadow same-named
            // extensions — retry against the extension candidate set before
            // reporting the member failure.
            if resolved.diagnostic != nil,
               let fallbackType = tryBindShadowedExtensionCallFallback(
                   request,
                   receiverType: receiverType,
                   lookupReceiverType: lookupReceiverType,
                   memberLookupType: memberLookupType,
                   argTypes: argTypes,
                   isClassNameReceiver: isClassNameReceiver,
                   isSuperCall: isSuperCall,
                   locals: &locals
               )
            {
                return fallbackType
            }
            if resolved.diagnostic != nil,
               let propertyType = tryInferCallableMemberPropertyInvocation(
                   request, memberLookupType: memberLookupType, argTypes: argTypes,
                   isClassNameReceiver: isClassNameReceiver, locals: &locals
               ) { return propertyType }
            if resolved.diagnostic != nil {
                if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                    candidates: candidates,
                    receiverType: lookupReceiverType,
                    calleeName: calleeName,
                    range: range,
                    sema: sema,
                    interner: interner
                ) {
                    ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                } else {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                }
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
        }

        return nil
    }

    /// Chosen-callee binding tail, extracted verbatim from
    /// `inferRegularMemberCall`: the no-callee fallbacks (class-name statics,
    /// projection violations, common fallbacks, shadowed extensions,
    /// callable-property invocation, SEMA-0024), deprecation/opt-in checks,
    /// super-call rules, use-site variance projection, contract effects and
    /// coroutine return-type narrowing.
    func bindChosenRegularMemberCall(
        _ request: MemberCallInferenceRequest,
        candidates: [SymbolID],
        resolved: ResolvedCall,
        argTypes: [TypeID],
        receiverType: TypeID,
        lookupReceiverType: TypeID,
        memberLookupType: TypeID,
        isClassNameReceiver: Bool,
        classNameReceiverNominalSymbol: SymbolID?,
        isSuperCall: Bool,
        locals: inout LocalBindings
    ) -> TypeID {
        let id = request.id
        let receiverID = request.receiverID
        let calleeName = request.calleeName
        let args = request.args
        let range = request.range
        let ctx = request.ctx
        let safeCall = request.safeCall
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner

        guard let chosen = resolved.chosenCallee else {
            if isClassNameReceiver,
               args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: calleeName,
                   sema: sema
               )
            {
                if let memberSymbol = sema.symbols.symbol(staticMember.symbol),
                   !ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: ctx.currentFileID,
                       enclosingClass: ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: ctx.semaCtx.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                sema.bindings.bindIdentifier(id, symbol: staticMember.symbol)
                sema.bindings.bindExprType(id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: calleeName,
                range: range,
                sema: sema,
                interner: interner
            ) {
                ctx.semaCtx.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let fallbackType = tryCommonMemberCallFallbacks(
                request,
                isClassNameReceiver: isClassNameReceiver,
                collectionFallbackFirst: true,
                admitNominalIterableReceiver: false,
                locals: &locals
            ) {
                return fallbackType
            }
            // KUU-946: members that produced no viable callee must not shadow
            // same-named extensions — retry against the extension candidate
            // set before reporting the member failure.
            if let fallbackType = tryBindShadowedExtensionCallFallback(
                request,
                receiverType: receiverType,
                lookupReceiverType: lookupReceiverType,
                memberLookupType: memberLookupType,
                argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver,
                isSuperCall: isSuperCall,
                locals: &locals
            ) {
                return fallbackType
            }
            if let propertyType = tryInferCallableMemberPropertyInvocation(
                request, memberLookupType: memberLookupType, argTypes: argTypes,
                isClassNameReceiver: isClassNameReceiver, locals: &locals
            ) { return propertyType }
            ctx.semaCtx.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        markRegexReplaceLambdaIfNeeded(chosenCallee: chosen, args: args, ctx: ctx)
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
        // P5-112: Prohibit super.foo() calls to abstract members.
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(SymbolFlags.abstractType),
           chosenSym.kind == SymbolKind.function || chosenSym.kind == SymbolKind.property
        {
            let memberName = interner.resolve(calleeName)
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-ABSTRACT",
                "Cannot call abstract member '\(memberName)' via super.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        // kotlinc prohibits a super-call from omitting an argument that carries
        // a default value ("super-calls with default arguments are prohibited.
        // Specify all arguments of 'super.<name>' explicitly.") -- resolving the
        // default and dispatching statically to the base implementation can
        // never re-evaluate an override's own default expression. The call is
        // otherwise fully well-typed, so diagnose without erroring the
        // expression's type -- an error type here would risk cascading into a
        // second, spurious kswiftc-only diagnostic on an unrelated line.
        if isSuperCall,
           let signature = sema.symbols.functionSignature(for: chosen)
        {
            let suppliedParameterIndices = Set(resolved.parameterMapping.values)
            let hasOmittedDefaultArgument = signature.valueParameterHasDefaultValues.indices.contains { index in
                signature.valueParameterHasDefaultValues[index] && !suppliedParameterIndices.contains(index)
            }
            if hasOmittedDefaultArgument {
                let memberName = interner.resolve(calleeName)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0306",
                    "Super-calls with default arguments are prohibited. Specify all arguments of 'super.\(memberName)' explicitly.",
                    range: range
                )
            }
        }

        // --- Use-site variance projection check ---
        // When the receiver has projected type arguments (e.g. MutableList<out Number>),
        // check that the member access respects variance constraints.
        if let signature = sema.symbols.functionSignature(for: chosen),
           let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
               receiverType: lookupReceiverType,
               signature: signature,
               symbols: sema.symbols
           )
        {
            // Check if any parameter uses a write-forbidden type parameter
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: sema, interner: interner),
               let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols
               )
            {
                let paramType = sema.types.displayName(
                    of: signature.parameterTypes[violatingParamIndex],
                    symbols: sema.symbols,
                    interner: interner
                )
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: range
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }

            // For projected types, merge the solver's substitution with the
            // variance projection (projection overrides receiver type params).
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            let mergedSubstitution = resolved.substitutedTypeArguments.merging(
                varianceResult.covariantSubstitution,
                uniquingKeysWith: { _, projected in projected }
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: mergedSubstitution
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            let projectedReturnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: mergedSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if isSuperCall { sema.bindings.markSuperCall(id) }
            let finalType = safeCall ? sema.types.makeNullable(projectedReturnType) : projectedReturnType
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }

        contextualizeArrayReduceRightLambda(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        contextualizeResolvedIntegerArguments(args: args, resolved: resolved, ctx: ctx, locals: &locals)
        let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
        // STDLIB-592 definite assignment: `x.let { ... }` / `x.apply { ... }` /
        // `x.also { ... }` / `x.run { ... }` resolve as ordinary member calls
        // through this path, so their `callsInPlace` contracts must be applied
        // here too (not just for the unqualified-call path in CallTypeChecker.swift).
        applyContractEffects(
            id: id,
            chosen: chosen,
            args: args,
            ctx: ctx,
            locals: &locals
        )
        // Narrow `CoroutineScope.async` / `Deferred.await()` using the element
        // type tracked by `coroutineBuilderNarrowedReturnType` for the
        // `async {}` call that produced this receiver.
        let adjustedReturnType: TypeID = if sema.symbols.externalLinkName(for: chosen) == "kk_coroutine_scope_async",
                                          let block = args.first(where: { $0.label == interner.intern("block") }) ?? args.last
        {
            coroutineBuilderNarrowedReturnType(
                id: id, launcherName: "async", lambdaArgExpr: block.expr,
                fallback: returnType, ast: ast, sema: sema
            )
        } else if sema.symbols.externalLinkName(for: chosen) == "kk_kxmini_async_await" {
            deferredAwaitResultType(receiverID: receiverID, fallback: returnType, ast: ast, sema: sema)
        } else {
            returnType
        }
        if isSuperCall { sema.bindings.markSuperCall(id) }
        let finalType = safeCall ? sema.types.makeNullable(adjustedReturnType) : adjustedReturnType
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
