// swiftlint:disable file_length function_body_length cyclomatic_complexity

/// Callable-value invocation paths from `inferCallExpr`: invoking a local
/// `invoke` operator member, and inferring calls whose callee is a value of
/// function type (local value, parameter, or arbitrary expression).
/// Extracted from `CallTypeChecker+CallExprInference.swift`.
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
        args: [CallArgument],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        explicitTypeArgs: [TypeID],
        calleeName: InternedString?,
        argTypes: [TypeID]
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let calleeExpr = ast.arena.expr(calleeID)
        var callableTarget: CallableTarget?
        var callableCalleeType: TypeID?
        if let calleeName,
           let local = locals[calleeName]
        {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
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
                    locals: &locals,
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
            callableCalleeType = driver.inferExpr(
                calleeID,
                ctx: ctx,
                locals: &locals,
                expectedType: contextualCalleeType
            )
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
               arityPolicy: .receiverOptionallyExplicit
           )
        {
            return result
        }

        // Invoke operator fallback: if callee is not a function type, check if
        // its type has an `operator fun invoke(...)` member and resolve through
        // the overload resolver as a member call.
        if let callableCalleeType {
            let invokeName = interner.intern("invoke")
            var invokeCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: invokeName,
                receiverType: callableCalleeType,
                sema: sema,
                interner: interner
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID) else { return false }
                return sym.flags.contains(.operatorFunction)
            }
            // `select { channel.onReceive { } }` — a clause value carries no
            // own `invoke`; the enclosing builder's member extension does.
            // It outranks top-level `invoke` extensions in scope.
            if invokeCandidates.isEmpty {
                invokeCandidates = collectDispatchReceiverMemberExtensionCandidates(
                    named: invokeName,
                    extensionReceiverType: sema.types.makeNonNullable(callableCalleeType),
                    ctx: ctx
                ).filter { candidateID in
                    sema.symbols.symbol(candidateID)?.flags.contains(.operatorFunction) == true
                }
            }
            // `collectMemberFunctionCandidates` only walks the callee type's
            // nominal member/supertype surface, so a user-declared extension
            // (e.g. `operator fun String.invoke(n: Int)`) is invisible to it.
            // Only when no member `invoke` applies, fall back to a scope-based
            // extension lookup so the callable-value call syntax also finds
            // extension `operator fun invoke`, mirroring the member-wins
            // ordering ordinary dotted extension calls use.
            if invokeCandidates.isEmpty {
                let nonNullCalleeType = sema.types.makeNonNullable(callableCalleeType)
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
            if !invokeCandidates.isEmpty {
                let resolvedArgs = zip(args, argTypes).map { argument, type in
                    CallArg(label: argument.label, isSpread: argument.isSpread, type: type)
                }
                let resolved = ctx.resolver.resolveCall(
                    candidates: invokeCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: invokeName,
                        args: resolvedArgs,
                        explicitTypeArgs: explicitTypeArgs,
                        dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type)
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: callableCalleeType,
                    ctx: ctx.semaCtx
                )
                if let diagnostic = resolved.diagnostic {
                    ctx.semaCtx.diagnostics.emit(diagnostic)
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                if let chosen = resolved.chosenCallee {
                    let returnType = bindCallAndResolveReturnType(id, chosen: chosen, resolved: resolved, sema: sema)
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
}
