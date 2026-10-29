// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    /// `resolved` is updated in place when a nested-argument retry clears the
    /// diagnostic.
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
                    ctx.sema.diagnostics.emit(diagnostic)
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
               ),
               !(receiverQualifierIsTypeAlias(receiverID: receiverID, ctx: ctx)
                   && sema.symbols.symbol(staticMember.symbol)?.kind == .object),
               // An explicit `()` on a nested `object` is a function invocation,
               // not a value read — fall through so `invoke` can dispatch
               // (KUU-3662).
               !(ctx.ast.arena.isExplicitCall(id)
                   && sema.symbols.symbol(staticMember.symbol)?.kind == .object)
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
                        diagnostics: ctx.sema.diagnostics
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
                ctx.sema.diagnostics.emit(projectionDiagnostic)
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
                    ctx.sema.diagnostics.emit(projectionDiagnostic)
                } else {
                    ctx.sema.diagnostics.emit(diagnostic)
                }
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
        }

        return nil
    }

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
        typeAliasConstructor: TypeAliasConstructorContext? = nil,
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
               ),
               !(receiverQualifierIsTypeAlias(receiverID: receiverID, ctx: ctx)
                   && sema.symbols.symbol(staticMember.symbol)?.kind == .object),
               // An explicit `()` on a nested `object` is a function invocation,
               // not a value read — fall through so `invoke` can dispatch
               // (KUU-3662).
               !(ctx.ast.arena.isExplicitCall(id)
                   && sema.symbols.symbol(staticMember.symbol)?.kind == .object)
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
                        diagnostics: ctx.sema.diagnostics
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
                ctx.sema.diagnostics.emit(projectionDiagnostic)
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
            ctx.sema.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(interner.resolve(calleeName))'.", range: range)
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        markRegexReplaceLambdaIfNeeded(chosenCallee: chosen, args: args, ctx: ctx)
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            constructorTypeAlias: typeAliasConstructor?.typeAliasSymbol,
            ctx: ctx,
            range: range,
            diagnostics: ctx.sema.diagnostics
        )
        if isSuperCall,
           let chosenSym = sema.symbols.symbol(chosen),
           chosenSym.flags.contains(SymbolFlags.abstractType),
           chosenSym.kind == SymbolKind.function || chosenSym.kind == SymbolKind.property
        {
            let memberName = interner.resolve(calleeName)
            ctx.sema.diagnostics.error(
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
            let defaultSignature = resolved.defaultArgumentOwner.flatMap {
                sema.symbols.functionSignature(for: $0)
            } ?? signature
            let suppliedParameterIndices = Set(resolved.parameterMapping.values)
            let hasOmittedDefaultArgument = defaultSignature.valueParameterHasDefaultValues.indices.contains { index in
                defaultSignature.valueParameterHasDefaultValues[index] && !suppliedParameterIndices.contains(index)
            }
            if hasOmittedDefaultArgument {
                let memberName = interner.resolve(calleeName)
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0306",
                    "Super-calls with default arguments are prohibited. Specify all arguments of 'super.\(memberName)' explicitly.",
                    range: range
                )
            }
        }

        if arrayFillHasWriteForbiddenProjection(
            chosenCallee: chosen, receiverType: lookupReceiverType, ctx: ctx
        ) {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-VAR-OUT",
                "A type projection on the receiver prevents calling 'fill' because its element type cannot be written.",
                range: range
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        // Preserve the overload-resolved receivers for member calls. KIR should
        // not have to rediscover them from generic context parameter types.
        let selectedContextReceiverSymbols = contextParameterReceiverSymbols(
            for: chosen,
            substitution: resolved.substitutedTypeArguments,
            ctx: ctx
        )
        let selectedDispatchReceiverSymbol = sema.symbols.memberExtensionOwnerSymbol(for: chosen).flatMap { owner in
            ctx.implicitReceiverMemberLookupEntries().first { entry in
                driver.helpers.allNominalSymbols(
                    of: entry.type,
                    types: sema.types,
                    symbols: sema.symbols,
                    interner: interner
                ).contains { receiverSymbol in
                    receiverSymbol == owner || sema.types.isNominalSubtypeSymbol(receiverSymbol, of: owner)
                }
            }?.symbol
        }
        let projectionReceiverType: TypeID = if interner.resolve(calleeName) == "receive",
                                                let channelBoundReceiverType = ReceiverClassifier(
                                                    sema: sema,
                                                    interner: interner
                                                ).channelUpperBoundType(of: lookupReceiverType) {
            channelBoundReceiverType
        } else {
            lookupReceiverType
        }
        if let signature = sema.symbols.functionSignature(for: chosen),
           let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
               receiverType: projectionReceiverType,
               signature: signature,
               symbols: sema.symbols
           )
        {
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: sema, interner: interner),
               let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols,
                   nullableWriteSymbols: varianceResult.nullableWriteSymbols,
                   argumentTypes: argTypes,
                   parameterMapping: resolved.parameterMapping
               )
            {
                let paramType = sema.types.displayName(
                    of: signature.parameterTypes[violatingParamIndex],
                    symbols: sema.symbols,
                    interner: interner
                )
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(interner.resolve(calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: range
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }

            // For projected types, merge the solver's substitution with the
            // variance projection (projection overrides receiver type params).
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            // An inner constructor captures the projected outer argument in
            // its result type. Replacing that capture with the readable upper
            // bound here would let later calls write through an out projection.
            let mergedSubstitution: [TypeVarID: TypeID] = if sema.symbols.symbol(chosen)?.kind == .constructor {
                resolved.substitutedTypeArguments
            } else {
                resolved.substitutedTypeArguments.merging(
                    varianceResult.covariantSubstitution,
                    uniquingKeysWith: { _, projected in projected }
                )
            }
            let projectedContextReceiverSymbols = contextParameterReceiverSymbols(
                for: chosen,
                substitution: mergedSubstitution,
                ctx: ctx
            )
            sema.bindings.bindCall(
                id,
                binding: CallBinding(
                    chosenCallee: chosen,
                    substitutedTypeArguments: mergedSubstitution
                        .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                        .map(\.value),
                    parameterMapping: resolved.parameterMapping,
                    defaultArgumentOwner: resolved.defaultArgumentOwner,
                    dispatchReceiverSymbol: selectedDispatchReceiverSymbol,
                    contextParameterReceiverSymbols: projectedContextReceiverSymbols
                )
            )
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            if sema.symbols.symbol(chosen)?.fqName == ["kotlin", "reflect", "full", "findAnnotation"].map(interner.intern),
               let searchType = sema.bindings.callBindings[id]?.substitutedTypeArguments.first {
                sema.bindings.bindFindAnnotationSearchType(id, type: searchType)
            }
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
        let returnType = bindCallAndResolveReturnType(
            id,
            chosen: chosen,
            resolved: resolved,
            sema: sema,
            dispatchReceiverSymbol: selectedDispatchReceiverSymbol,
            contextParameterReceiverSymbols: selectedContextReceiverSymbols
        )
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
