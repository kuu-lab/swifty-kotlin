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

        if let diagnostic = resolved.diagnostic {
            if diagnostic.code == "KSWIFTK-SEMA-BOUND" {
                let callee = request.interner.resolve(request.calleeName)
                if callee == "sorted" || callee == "sortedDescending" {
                    request.ctx.sema.diagnostics.emit(diagnostic)
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
            }
            if isClassNameReceiver,
               request.args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: request.calleeName,
                   sema: request.sema
               ),
               !(receiverQualifierIsTypeAlias(receiverID: request.receiverID, ctx: request.ctx)
                   && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object),
               // An explicit `()` on a nested `object` is a function invocation,
               // not a value read — fall through so `invoke` can dispatch
               // (KUU-3662).
               !(request.ctx.ast.arena.isExplicitCall(request.id)
                   && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object)
            {
                if let memberSymbol = request.sema.symbols.symbol(staticMember.symbol),
                   !request.ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: request.ctx.currentFileID,
                       enclosingClass: request.ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: request.interner.resolve(request.calleeName),
                        range: request.range,
                        diagnostics: request.ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                request.sema.bindings.bindIdentifier(request.id, symbol: staticMember.symbol)
                request.sema.bindings.bindExprType(request.id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: request.calleeName,
                range: request.range,
                sema: request.sema,
                interner: request.interner
            ) {
                request.ctx.sema.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            if let fallbackType = tryRegexMemberFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryKFunctionMemberFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryStringMemberFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryNativePlacementAllocExtensionFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                explicitTypeArgs: request.explicitTypeArgs,
                ctx: request.ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryNativeCInteropReadValueExtensionFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx
            ) {
                return fallbackType
            }
            if let fallbackType = tryFileMemberFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryArrayMemberFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let fallbackType = tryRangeMemberFallback(
                request.id,
                calleeName: request.calleeName,
                isClassNameReceiver: isClassNameReceiver,
                safeCall: request.safeCall,
                receiverID: request.receiverID,
                args: request.args,
                ctx: request.ctx,
                locals: &locals
            ) {
                return fallbackType
            }
            if let retried = retryResolutionReinferringNestedCallArguments(
                candidates: candidates,
                args: request.args,
                argTypes: preparedArgs.argTypes,
                range: request.range,
                calleeName: request.calleeName,
                explicitTypeArgs: request.explicitTypeArgs,
                expectedType: request.expectedType,
                implicitReceiverType: effectiveReceiverType,
                lambdaLiteralIndices: preparedArgs.lambdaLiteralIndices,
                inputOnlyLambdaIndices: preparedArgs.inputOnlyLambdaIndices,
                blockedLambdaRefinement: preparedArgs.blockedLambdaRefinement,
                hasUnresolvableImplicitLambdaParameter: preparedArgs.hasUnresolvableImplicitLambdaParameter,
                ctx: request.ctx,
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
                // When flow typing proves the receiver is `Nothing?` (e.g.
                // `x = null` inside a `?.`-call lambda), kotlinc reports
                // UNSAFE_CALL whenever the same call would resolve against
                // `Nothing`'s non-null counterpart. `Nothing` is a subtype of
                // every declared receiver, so surviving candidates only fail
                // because of the nullability — re-resolve them against the
                // stripped receiver and remap the diagnostic to SEMA-0026
                // (KUU-3957). Plain `T?` receivers encode a rejected smart
                // cast (captured or unstable writes), which KSwiftK reports
                // as SEMA-0002 or SEMA-0022 instead of kotlinc's
                // SMARTCAST_IMPOSSIBLE — a generic receiver otherwise leaks
                // the solver's TYPE-0001 constraint failure where a
                // non-generic receiver reports "no viable overload"
                // (KUU-4062).
                let nullableReceiverProbeResolves: Bool = {
                    let receiverIsNullableNothing = lookupReceiverType == request.sema.types.nullableNothingType
                    guard !request.safeCall,
                          ((diagnostic.code == "KSWIFTK-SEMA-0002"
                              || diagnostic.code == "KSWIFTK-SEMA-0480")
                              && receiverIsNullableNothing)
                              || (diagnostic.code == "KSWIFTK-TYPE-0001"
                                  && request.sema.types.nullability(of: lookupReceiverType) == .nullable)
                    else {
                        return false
                    }
                    let probeArgs = zip(request.args, preparedArgs.argTypes).map { argument, type in
                        let literal = integerArgumentValues(argument.expr, ctx: request.ctx)
                        return CallArg.source(
                            argument, type: type, callRange: request.range, ast: request.ctx.ast,
                            signedIntegerLiteral: literal.signed,
                            unsignedIntegerLiteral: literal.unsigned
                        )
                    }
                    let probe = request.ctx.resolver.resolveCall(
                        candidates: candidates,
                        call: CallExpr(
                            range: request.range,
                            calleeName: request.calleeName,
                            args: probeArgs,
                            explicitTypeArgs: request.explicitTypeArgs,
                            dispatchReceiverTypes: request.ctx.implicitReceiverMemberLookupEntries().map(\.type)
                        ),
                        expectedType: nil,
                        implicitReceiverType: request.sema.types.makeNonNullable(effectiveReceiverType),
                        ctx: request.ctx.sema
                    )
                    if probe.chosenCallee != nil {
                        return true
                    }
                    // A `Nothing` call-site receiver is a subtype of every
                    // declared receiver, so all surviving candidates become
                    // viable at once and resolution reports ambiguity — the
                    // receiver's nullability is still what blocked the call.
                    return probe.diagnostic?.code == "KSWIFTK-SEMA-0003"
                }()
                let nullableReceiverConstraintFailure: Bool = {
                    guard diagnostic.code == "KSWIFTK-TYPE-0001",
                          !request.safeCall,
                          request.sema.types.nullability(of: lookupReceiverType) == .nullable,
                          lookupReceiverType != request.sema.types.nullableNothingType
                    else {
                        return false
                    }
                    let probeArgs = zip(request.args, preparedArgs.argTypes).map { argument, type in
                        let literal = integerArgumentValues(argument.expr, ctx: request.ctx)
                        return CallArg.source(
                            argument, type: type, callRange: request.range, ast: request.ctx.ast,
                            signedIntegerLiteral: literal.signed,
                            unsignedIntegerLiteral: literal.unsigned
                        )
                    }
                    let probe = request.ctx.resolver.resolveCall(
                        candidates: candidates,
                        call: CallExpr(
                            range: request.range,
                            calleeName: request.calleeName,
                            args: probeArgs,
                            explicitTypeArgs: request.explicitTypeArgs,
                            dispatchReceiverTypes: request.ctx.implicitReceiverMemberLookupEntries().map(\.type)
                        ),
                        expectedType: request.expectedType,
                        implicitReceiverType: request.sema.types.makeNonNullable(effectiveReceiverType),
                        ctx: request.ctx.sema
                    )
                    return probe.chosenCallee != nil
                }()
                if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                    candidates: candidates,
                    receiverType: lookupReceiverType,
                    calleeName: request.calleeName,
                    range: request.range,
                    sema: request.sema,
                    interner: request.interner
                ) {
                    request.ctx.sema.diagnostics.emit(projectionDiagnostic)
                } else if nullableReceiverProbeResolves {
                    if lookupReceiverType == request.sema.types.nullableNothingType {
                        request.ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0026",
                            "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                            range: request.range
                        )
                    } else {
                        request.ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0002",
                            "No viable overload found for call.",
                            range: request.range
                        )
                    }
                } else if nullableReceiverConstraintFailure {
                    request.ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for call.",
                        range: request.range
                    )                } else {
                    request.ctx.sema.diagnostics.emit(diagnostic)
                }
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
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

        guard let chosen = resolved.chosenCallee else {
            if isClassNameReceiver,
               request.args.isEmpty,
               let classNameReceiverNominalSymbol,
               let staticMember = resolveClassNameMemberValue(
                   ownerNominalSymbol: classNameReceiverNominalSymbol,
                   memberName: request.calleeName,
                   sema: request.sema
               ),
               !(receiverQualifierIsTypeAlias(receiverID: request.receiverID, ctx: request.ctx)
                   && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object),
               // An explicit `()` on a nested `object` is a function invocation,
               // not a value read — fall through so `invoke` can dispatch
               // (KUU-3662).
               !(request.ctx.ast.arena.isExplicitCall(request.id)
                   && request.sema.symbols.symbol(staticMember.symbol)?.kind == .object)
            {
                if let memberSymbol = request.sema.symbols.symbol(staticMember.symbol),
                   !request.ctx.visibilityChecker.isAccessible(
                       memberSymbol,
                       fromFile: request.ctx.currentFileID,
                       enclosingClass: request.ctx.enclosingClassSymbol
                   )
                {
                    driver.helpers.emitVisibilityError(
                        for: memberSymbol,
                        name: request.interner.resolve(request.calleeName),
                        range: request.range,
                        diagnostics: request.ctx.sema.diagnostics
                    )
                    return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
                }
                request.sema.bindings.bindIdentifier(request.id, symbol: staticMember.symbol)
                request.sema.bindings.bindExprType(request.id, type: staticMember.type)
                return staticMember.type
            }
            if let projectionDiagnostic = makeProjectionViolationDiagnostic(
                candidates: candidates,
                receiverType: lookupReceiverType,
                calleeName: request.calleeName,
                range: request.range,
                sema: request.sema,
                interner: request.interner
            ) {
                request.ctx.sema.diagnostics.emit(projectionDiagnostic)
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
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
            request.ctx.sema.diagnostics.error("KSWIFTK-SEMA-0024", "Unresolved member function '\(request.interner.resolve(request.calleeName))'.", range: request.range)
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }
        // A member-style call that resolved to a local extension function is
        // a lexical reference to that declaration. Record the identifier
        // binding the callable-value path used to keep on `request.id` so
        // capture analysis and identifier lookups see the resolved local.
        if request.sema.symbols.symbol(chosen)?.flags.contains(.localFunction) == true {
            request.sema.bindings.bindIdentifier(request.id, symbol: chosen)
        }
        markRegexReplaceLambdaIfNeeded(chosenCallee: chosen, args: request.args, ctx: request.ctx)
        driver.helpers.checkDeprecation(
            for: chosen,
            sema: request.sema,
            interner: request.interner,
            range: request.range,
            diagnostics: request.ctx.sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: chosen,
            constructorTypeAlias: typeAliasConstructor?.typeAliasSymbol,
            ctx: request.ctx,
            range: request.range,
            diagnostics: request.ctx.sema.diagnostics
        )
        if isSuperCall,
           let chosenSym = request.sema.symbols.symbol(chosen),
           chosenSym.flags.contains(SymbolFlags.abstractType),
           chosenSym.kind == SymbolKind.function || chosenSym.kind == SymbolKind.property
        {
            let memberName = request.interner.resolve(request.calleeName)
            request.ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-ABSTRACT",
                "Cannot call abstract member '\(memberName)' via super.",
                range: request.range
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
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
           let signature = request.sema.symbols.functionSignature(for: chosen)
        {
            let defaultSignature = resolved.defaultArgumentOwner.flatMap {
                request.sema.symbols.functionSignature(for: $0)
            } ?? signature
            let suppliedParameterIndices = Set(resolved.parameterMapping.values)
            let hasOmittedDefaultArgument = defaultSignature.valueParameterHasDefaultValues.indices.contains { index in
                defaultSignature.valueParameterHasDefaultValues[index] && !suppliedParameterIndices.contains(index)
            }
            if hasOmittedDefaultArgument {
                let memberName = request.interner.resolve(request.calleeName)
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0306",
                    "Super-calls with default arguments are prohibited. Specify all arguments of 'super.\(memberName)' explicitly.",
                    range: request.range
                )
            }
        }

        if arrayFillHasWriteForbiddenProjection(
            chosenCallee: chosen, receiverType: lookupReceiverType, ctx: request.ctx
        ) {
            request.ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-VAR-OUT",
                "A type projection on the receiver prevents calling 'fill' because its element type cannot be written.",
                range: request.range
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
        }
        // Preserve the overload-resolved receivers for member calls. KIR should
        // not have to rediscover them from generic context parameter types.
        let selectedContextReceiverSymbols = contextParameterReceiverSymbols(
            for: chosen,
            substitution: resolved.substitutedTypeArguments,
            ctx: request.ctx
        )
        let selectedDispatchReceiverSymbol = request.sema.symbols.memberExtensionOwnerSymbol(for: chosen).flatMap { owner in
            request.ctx.implicitReceiverMemberLookupEntries().first { entry in
                driver.helpers.allNominalSymbols(
                    of: entry.type,
                    types: request.sema.types,
                    symbols: request.sema.symbols,
                    interner: request.interner
                ).contains { receiverSymbol in
                    receiverSymbol == owner || request.sema.types.isNominalSubtypeSymbol(receiverSymbol, of: owner)
                }
            }?.symbol
        }
        let projectionReceiverType: TypeID = if request.calleeName == request.knownNames.receive,
                                                let channelBoundReceiverType = ReceiverClassifier(
                                                    sema: request.sema,
                                                    interner: request.interner
                                                ).channelUpperBoundType(of: lookupReceiverType) {
            channelBoundReceiverType
        } else {
            lookupReceiverType
        }
        if let signature = request.sema.symbols.functionSignature(for: chosen),
           let varianceResult = request.sema.types.buildVarianceProjectionSubstitutions(
               receiverType: projectionReceiverType,
               signature: signature,
               symbols: request.sema.symbols
           )
        {
            if !allowsProjectedReceiverUnsafeVariance(chosen, sema: request.sema, interner: request.interner),
               let violatingParamIndex = request.sema.types.checkVarianceViolationInParameters(
                   signature: signature,
                   writeForbiddenSymbols: varianceResult.writeForbiddenSymbols,
                   nullableWriteSymbols: varianceResult.nullableWriteSymbols,
                   argumentTypes: argTypes,
                   parameterMapping: resolved.parameterMapping
               )
            {
                let paramType = request.sema.types.displayName(
                    of: signature.parameterTypes[violatingParamIndex],
                    symbols: request.sema.symbols,
                    interner: request.interner
                )
                request.ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-VAR-OUT",
                    "A type projection on the receiver prevents calling '\(request.interner.resolve(request.calleeName))' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                    range: request.range
                )
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }

            // For projected types, merge the solver's substitution with the
            // variance projection (projection overrides receiver type params).
            let typeVarBySymbol = request.sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            // An inner constructor captures the projected outer argument in
            // its result type. Replacing that capture with the readable upper
            // bound here would let later calls write through an out projection.
            let mergedSubstitution: [TypeVarID: TypeID] = if request.sema.symbols.symbol(chosen)?.kind == .constructor {
                resolved.substitutedTypeArguments
            } else {
                resolved.substitutedTypeArguments.merging(
                    varianceResult.covariantSubstitution,
                    uniquingKeysWith: { _, projected in projected }
                )
            }
            if !validateReifiedTypeArguments(
                for: chosen,
                substitutedTypeArguments: mergedSubstitution,
                range: request.range,
                sema: request.sema
            ) {
                return driver.helpers.bindAndReturnErrorType(request.id, sema: request.sema)
            }
            let projectedContextReceiverSymbols = contextParameterReceiverSymbols(
                for: chosen,
                substitution: mergedSubstitution,
                ctx: request.ctx
            )
            request.sema.bindings.bindCall(
                request.id,
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
            request.sema.bindings.bindCallableTarget(request.id, target: .symbol(chosen))
            if request.sema.symbols.symbol(chosen)?.fqName == ["kotlin", "reflect", "full", "findAnnotation"].map(request.interner.intern),
               let searchType = request.sema.bindings.callBindings[request.id]?.substitutedTypeArguments.first {
                request.sema.bindings.bindFindAnnotationSearchType(request.id, type: searchType)
            }
            let projectedReturnType = request.sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: mergedSubstitution,
                typeVarBySymbol: typeVarBySymbol
            )
            if isSuperCall { request.sema.bindings.markSuperCall(request.id) }
            let finalType = request.safeCall ? request.sema.types.makeNullable(projectedReturnType) : projectedReturnType
            request.sema.bindings.bindExprType(request.id, type: finalType)
            return finalType
        }

        contextualizeArrayReduceRightLambda(args: request.args, resolved: resolved, ctx: request.ctx, locals: &locals)
        contextualizeResolvedIntegerArguments(args: request.args, resolved: resolved, ctx: request.ctx, locals: &locals)
        let returnType = bindCallAndResolveReturnType(
            request.id,
            chosen: chosen,
            resolved: resolved,
            sema: request.sema,
            dispatchReceiverSymbol: selectedDispatchReceiverSymbol,
            contextParameterReceiverSymbols: selectedContextReceiverSymbols
        )
        // STDLIB-592 definite assignment: `x.let { ... }` / `x.apply { ... }` /
        // `x.also { ... }` / `x.run { ... }` resolve as ordinary member calls
        // through this path, so their `callsInPlace` contracts must be applied
        // here too (not just for the unqualified-call path in CallTypeChecker.swift).
        applyContractEffects(
            id: request.id,
            chosen: chosen,
            args: request.args,
            ctx: request.ctx,
            locals: &locals
        )
        let adjustedReturnType: TypeID = if request.sema.symbols.externalLinkName(for: chosen) == "kk_coroutine_scope_async",
                                          let block = request.args.first(where: { $0.label == request.interner.intern("block") }) ?? request.args.last
        {
            coroutineBuilderNarrowedReturnType(
                id: request.id, launcherName: "async", lambdaArgExpr: block.expr,
                fallback: returnType, ast: request.ast, sema: request.sema
            )
        } else if request.sema.symbols.externalLinkName(for: chosen) == "kk_kxmini_async_await" {
            deferredAwaitResultType(receiverID: request.receiverID, fallback: returnType, ast: request.ast, sema: request.sema)
        } else {
            returnType
        }
        if isSuperCall { request.sema.bindings.markSuperCall(request.id) }
        let finalType = request.safeCall ? request.sema.types.makeNullable(adjustedReturnType) : adjustedReturnType
        request.sema.bindings.bindExprType(request.id, type: finalType)
        return finalType
    }
}
// swiftlint:enable cyclomatic_complexity file_length function_body_length
