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
            // A local nominal declaration binds its classifier symbol into
            // `locals`, so `local.symbol` names the *type*, not a value —
            // `C()` is a constructor call resolved through the ordinary
            // candidate path (companion `invoke`s are collected there too),
            // never the invoke convention on an instance. Routing it through
            // here rewrites `C()` to `C.invoke()` on a class-name receiver,
            // where the instance member can never resolve (KUU-3875). Named
            // local `object`s keep the value path: in expression position
            // their name denotes the singleton instance.
            switch sema.symbols.symbol(local.symbol)?.kind {
            case .class, .interface, .enumClass, .annotationClass:
                return nil
            default:
                break
            }
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
                // Context-bearing `invoke` overloads need the shared callable
                // resolver to filter candidates against the active context
                // receivers before overload ranking.
                if invokeCandidates.contains(where: { candidate in
                    sema.symbols.functionSignature(for: candidate)?.contextParameterTypes.isEmpty == false
                }) {
                    return nil
                }
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
        let localFunctionFallsThroughToProperty: Bool = {
            guard let calleeName,
                  let local = calleeLocals[calleeName],
                  ctx.cachedSymbol(local.symbol)?.flags.contains(.localFunction) == true
            else {
                return false
            }
            return implicitReceiverFunctionProperty(named: calleeName, ctx: ctx) != nil
        }()
        var callableTarget: CallableTarget?
        var callableCalleeType: TypeID?
        if let calleeName,
           let local = calleeLocals[calleeName],
           !localFunctionFallsThroughToProperty
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
            switch localSymbolKind {
            case .function, .class, .interface, .enumClass, .annotationClass:
                // A local nominal declaration binds the classifier symbol,
                // not a callable value — `C()` stays on the constructor
                // candidate path so an inaccessible `<init>` still reports
                // as such instead of materializing `C.invoke()` (KUU-3875).
                break
            default:
                callableTarget = .localValue(local.symbol)
                callableCalleeType = local.type
            }
        } else if let calleeName {
            if localFunctionFallsThroughToProperty {
                calleeLocals[calleeName] = nil
            }
            let scopeCandidates = ctx.cachedScopeLookup(calleeName)
            let implicitProperty = implicitReceiverFunctionProperty(named: calleeName, ctx: ctx)
            let scopeContainsOnlyLocalFunctionsOrImplicitProperty = !scopeCandidates.isEmpty
                && scopeCandidates.allSatisfy { candidate in
                    if candidate == implicitProperty?.symbol {
                        return true
                    }
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .function && symbol.flags.contains(.localFunction)
                }
            if !scopeCandidates.isEmpty, !scopeContainsOnlyLocalFunctionsOrImplicitProperty {
                callableCalleeType = driver.inferExpr(
                    calleeID,
                    ctx: ctx,
                    locals: &calleeLocals,
                    expectedType: nil
                )
                callableTarget = driver.helpers.callableTargetForCalleeExpr(calleeID, sema: sema)
            } else if let property = implicitProperty {
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
            let argumentLabels = args.map(\.label)
            let allInvokeCandidates = implicitInvokeOperatorCandidates(
                for: callableCalleeType,
                ctx: ctx,
                argumentLabels: argumentLabels
            )
            let invokeCandidates = contextApplicableCallCandidates(
                allInvokeCandidates,
                ctx: ctx,
                argumentLabels: argumentLabels
            )
            if invokeCandidates.isEmpty,
               let missingType = firstContextParameterType(
                   in: allInvokeCandidates,
                   ctx: ctx,
                   argumentLabels: argumentLabels
               )
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
        ctx: TypeInferenceContext,
        argumentLabels: [InternedString?] = []
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
        var contextInapplicableCandidates: [SymbolID] = []
        if !invokeCandidates.isEmpty,
           contextApplicableCallCandidates(
               invokeCandidates,
               ctx: ctx,
               argumentLabels: argumentLabels
           ).isEmpty
        {
            contextInapplicableCandidates = invokeCandidates
            invokeCandidates = []
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
            if !invokeCandidates.isEmpty,
               contextApplicableCallCandidates(
                   invokeCandidates,
                   ctx: ctx,
                   argumentLabels: argumentLabels
               ).isEmpty
            {
                if contextInapplicableCandidates.isEmpty {
                    contextInapplicableCandidates = invokeCandidates
                }
                invokeCandidates = []
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
        return invokeCandidates.isEmpty ? contextInapplicableCandidates : invokeCandidates
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
            let isFunctionType: Bool = {
                guard case let .functionType(function) = sema.types.kind(of: property.type) else {
                    return false
                }
                return function.nullability == .nonNull
            }()
            let isNonNullableCallableObject = sema.types.nullability(of: property.type) == .nonNull
                && !implicitInvokeOperatorCandidates(
                    for: sema.types.makeNonNullable(property.type),
                    ctx: ctx
                ).isEmpty
            guard isFunctionType || isNonNullableCallableObject else {
                return nil
            }
            return property
        }
        return nil
    }

    /// Kotlin resolves `name(...)` against a single candidate set that also
    /// includes the implicit `invoke` of every callable value named `name` in
    /// scope — a function-typed property such as `var resume: () -> Unit`, or
    /// an object type carrying an `invoke` operator. When no function
    /// candidate is viable the call can still bind through that value, so the
    /// overload resolver defers to the callable-value path instead of
    /// reporting "no viable overload".
    func callableValueCalleeInScope(
        named calleeName: InternedString,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> Bool {
        let sema = ctx.sema
        func isCallableType(_ type: TypeID) -> Bool {
            let nonNull = sema.types.makeNonNullable(type)
            if case .functionType = sema.types.kind(of: nonNull) {
                return true
            }
            return !implicitInvokeOperatorCandidates(for: nonNull, ctx: ctx).isEmpty
        }
        if let local = locals[calleeName], isCallableType(local.type) {
            return true
        }
        if implicitReceiverFunctionProperty(named: calleeName, ctx: ctx) != nil {
            return true
        }
        return ctx.valueScopeLookup(calleeName).matches.contains { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .property || symbol.kind == .valueParameter || symbol.kind == .local,
                  let type = sema.symbols.propertyType(for: candidate)
            else {
                return false
            }
            return isCallableType(type)
        }
    }

    func shouldFallThroughFromInapplicableLocalFunctionsToImplicitCallableProperty(
        candidates: [SymbolID],
        args: [CallArgument],
        calleeName: InternedString?,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> Bool {
        guard !candidates.isEmpty,
              let calleeName,
              locals[calleeName].map({ ctx.cachedSymbol($0.symbol)?.kind == .function }) ?? true,
              implicitReceiverFunctionProperty(named: calleeName, ctx: ctx) != nil,
              candidates.allSatisfy({ candidate in
                  guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                  return symbol.kind == .function && symbol.flags.contains(.localFunction)
              })
        else {
            return false
        }

        let argumentLabels = args.map(\.label)
        return candidates.allSatisfy { candidate in
            guard let signature = ctx.sema.symbols.functionSignature(for: candidate) else {
                return false
            }
            let receiverIsApplicable = signature.receiverType.map { declaredReceiver in
                ctx.implicitReceiverMemberLookupEntries().contains { receiver in
                    extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: receiver.type,
                        declaredReceiver: declaredReceiver,
                        sema: ctx.sema
                    )
                }
            } ?? true
            let contextIsApplicable = contextApplicableCallCandidates(
                [candidate], ctx: ctx, argumentLabels: argumentLabels
            ).contains(candidate)
            return !receiverIsApplicable || !contextIsApplicable
        }
    }
}
