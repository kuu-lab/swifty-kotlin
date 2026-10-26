// swiftlint:disable file_length function_body_length cyclomatic_complexity

extension CallTypeChecker {
    func inferLocalInvokeOperatorCall(
        _ id: ExprID,
        calleeID: ExprID,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner

        if let calleeName,
           let local = locals[calleeName],
           case .classType = sema.types.kind(of: sema.types.makeNonNullable(local.type))
        {
            let invokeName = interner.intern("invoke")
            var invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: invokeName,
                receiverType: local.type,
                sema: sema,
                interner: interner
            ).filter { sema.symbols.symbol($0)?.flags.contains(.operatorFunction) == true }
            if invokeCandidates.isEmpty {
                // `select { clause { } }` — the clause type carries no own
                // `invoke`; the enclosing builder's member extension does.
                invokeCandidates = collectDispatchReceiverMemberExtensionCandidates(
                    named: invokeName,
                    extensionReceiverType: sema.types.makeNonNullable(local.type),
                    ctx: ctx
                ).filter { sema.symbols.symbol($0)?.flags.contains(.operatorFunction) == true }
            }
            if !invokeCandidates.isEmpty {
                let returnType = inferMemberCallExpr(
                    id, receiverID: calleeID, calleeName: invokeName,
                    args: args, range: range, ctx: ctx, locals: &locals,
                    expectedType: expectedType, explicitTypeArgs: explicitTypeArgs
                )
                sema.bindings.markInvokeOperatorCall(id)
                return returnType
            }
        }
        return nil
    }

    func inferCallableValueCall(
        _ id: ExprID,
        calleeID: ExprID,
        preInferredCalleeType: TypeID?,
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        argTypes: [TypeID],
        calleeScopeLocals: LocalBindings? = nil
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let calleeExpr = ast.arena.expr(calleeID)
        // Arguments are checked before this function runs, so `locals` can
        // carry narrowings they introduced (`a(a as String)`). Kotlin
        // evaluates the callee first, though: its declared/pre-argument flow
        // state decides which `invoke` overload applies.
        var calleeLocals = calleeScopeLocals ?? locals
        var callableTarget: CallableTarget?
        var callableCalleeType: TypeID?
        if let calleeName,
           let local = calleeLocals[calleeName]
        {
            if !local.isInitialized,
               ctx.cachedSymbol(local.symbol)?.flags.contains(.lateinitProperty) != true
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(calleeName))' must be initialized before use.",
                    range: range
                )
            }
            sema.bindings.bindIdentifier(calleeID, symbol: local.symbol)
            sema.bindings.bindExprType(calleeID, type: local.type)
            let localSymbolKind = ctx.cachedSymbol(local.symbol)?.kind
            if localSymbolKind != .function {
                callableTarget = .localValue(local.symbol)
                callableCalleeType = local.type
            }
        } else if let calleeName {
            if !ctx.cachedScopeLookup(calleeName).isEmpty {
                callableCalleeType = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &calleeLocals,
                    expectedType: nil
                )
                callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
            } else if let property = implicitReceiverFunctionProperty(named: calleeName, ctx: ctx) {
                guard let propertySymbol = sema.symbols.symbol(property.symbol) else {
                    return nil
                }
                guard ctx.visibilityChecker.isAccessible(
                    propertySymbol,
                    fromFile: ctx.currentFileID,
                    enclosingClass: ctx.enclosingClassSymbol
                ) else {
                    driver.helpers.emitVisibilityError(
                        for: propertySymbol,
                        name: interner.resolve(calleeName),
                        range: range,
                        diagnostics: sema.diagnostics
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                callableCalleeType = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &calleeLocals,
                    expectedType: nil
                )
                callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
            }
        } else if calleeName == nil {
            let contextualCalleeType: TypeID?
            if let calleeExpr {
                switch calleeExpr {
                case .lambdaLiteral:
                    // A directly-invoked lambda literal gets no parameter types
                    // from the call's argument list — kotlinc requires an
                    // explicit annotation there (`{ x -> ... }(4)` is rejected,
                    // `{ x: Int -> ... }(4)` is accepted) — so only the optional
                    // caller expected *return* type is propagated here.
                    sema.bindings.markDirectlyInvokedLambdaExpr(calleeID)
                    contextualCalleeType = sema.types.make(.functionType(FunctionType(
                        params: [],
                        returnType: expectedType ?? sema.types.anyType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                case .callableRef:
                    let contextualReturnType = expectedType ?? sema.types.anyType
                    contextualCalleeType = sema.types.make(.functionType(FunctionType(
                        params: argTypes,
                        returnType: contextualReturnType,
                        isSuspend: false,
                        nullability: .nonNull
                    )))
                default:
                    contextualCalleeType = nil
                }
            } else {
                contextualCalleeType = nil
            }
            if let preInferredCalleeType {
                callableCalleeType = preInferredCalleeType
            } else {
                callableCalleeType = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &locals,
                    expectedType: contextualCalleeType
                )
            }
            callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
        }

        if callableCalleeType == sema.types.errorType {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        if let callableCalleeType,
           let result = inferCallableValueInvocation(
               id, calleeType: callableCalleeType, callableTarget: callableTarget,
               args: args, argTypes: argTypes, range: range, ctx: ctx, locals: &locals, expectedType: expectedType,
               arityPolicy: ast.arena.isReceiverExpressionArgsCall(id)
                   ? .receiverMustBePresent : .receiverOptionallyExplicit
           )
        {
            return result
        }

        if ast.arena.isReceiverExpressionArgsCall(id) {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        if let callableCalleeType {
            let allInvokeCandidates = implicitInvokeOperatorCandidates(for: callableCalleeType, ctx: ctx)
            let invokeCandidates = contextApplicableCallCandidates(allInvokeCandidates, ctx: ctx)
            if invokeCandidates.isEmpty,
               let missingType = firstContextParameterType(in: allInvokeCandidates, ctx: ctx)
            {
                sema.diagnostics.error(
                    "KSWIFTK-SEMA-CTX-002",
                    "No context value is available for parameter type '\(sema.types.renderType(missingType))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if !invokeCandidates.isEmpty {
                let resolvedArgs = zip(args, argTypes).map { argument, type in
                    CallArg.source(argument, type: type, callRange: range, ast: ctx.ast)
                }
                let resolved = ctx.resolver.resolveCall(
                    candidates: invokeCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: interner.intern("invoke"),
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs,
                        dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: callableCalleeType,
                    ctx: ctx.sema
                )
                if let diagnostic = resolved.diagnostic {
                    ctx.sema.diagnostics.emit(diagnostic)
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if let chosen = resolved.chosenCallee {
                    let contextReceiverSymbols = contextParameterReceiverSymbols(
                        for: chosen,
                        substitution: resolved.substitutedTypeArguments,
                        ctx: ctx
                    )
                    let returnType = bindCallAndResolveReturnType(
                        id,
                        chosen: chosen,
                        resolved: resolved,
                        sema: sema,
                        contextParameterReceiverSymbols: contextReceiverSymbols
                    )
                    applyContractEffects(
                        id: id,
                        chosen: chosen,
                        args: args,
                        ctx: ctx,
                        locals: &locals
                    )
                    sema.bindings.markInvokeOperatorCall(id)
                    sema.bindings.bindExprType(id, type: returnType)
                    return returnType
                }
            }
        }

        return nil
    }

    /// Collects the same implicit `invoke` candidates used both to type a
    /// call-chain lambda and to bind the completed callable-value call.
    func implicitInvokeOperatorCandidates(
        for calleeType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let interner = ctx.interner
        let invokeName = interner.intern("invoke")
        var invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: invokeName,
            receiverType: calleeType,
            sema: sema,
            interner: interner
        ).filter { candidateID in
            sema.symbols.symbol(candidateID)?.flags.contains(.operatorFunction) == true
        }
        // A clause value may rely on an enclosing builder's member extension.
        // It outranks top-level `invoke` extensions in scope.
        if invokeCandidates.isEmpty {
            invokeCandidates = collectDispatchReceiverMemberExtensionCandidates(
                named: invokeName,
                extensionReceiverType: sema.types.makeNonNullable(calleeType),
                ctx: ctx
            ).filter { candidateID in
                sema.symbols.symbol(candidateID)?.flags.contains(.operatorFunction) == true
            }
        }
        // Nominal lookup does not see a user-declared extension such as
        // `operator fun String.invoke(n: Int)`, so use a scope fallback only
        // when neither members nor dispatch-receiver extensions were found.
        if invokeCandidates.isEmpty {
            let nonNullCalleeType = sema.types.makeNonNullable(calleeType)
            invokeCandidates = ctx.cachedScopeLookup(invokeName).filter { candidateID in
                guard let symbol = ctx.cachedSymbol(candidateID),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      let signature = sema.symbols.functionSignature(for: candidateID),
                      let declaredReceiver = signature.receiverType
                else { return false }
                return extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullCalleeType,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            }
        }
        return invokeCandidates
    }

    /// The caller only uses the result after ordinary call candidates and
    /// scoped values have had their existing resolution priority.
    func implicitReceiverFunctionProperty(
        named name: InternedString,
        ctx: TypeInferenceContext
    ) -> (symbol: SymbolID, type: TypeID)? {
        let sema = ctx.sema
        for receiver in ctx.implicitReceiverMemberLookupEntries() {
            guard let property = driver.helpers.lookupMemberProperty(
                named: name,
                receiverType: sema.types.makeNonNullable(receiver.type),
                sema: sema
            ) else {
                continue
            }
            guard case let .functionType(function) = sema.types.kind(of: property.type),
                  function.nullability == .nonNull else {
                return nil
            }
            return property
        }
        return nil
    }
}
