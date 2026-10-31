
// Property accessor type-checking helpers extracted from DeclTypeChecker
// to keep the main file within SwiftLint length limits.

private struct PropertyDelegateFunctionResolution {
    let symbol: SymbolID?
    let substitutedTypeArguments: [TypeVarID: TypeID]
    let diagnostic: Diagnostic?
}

private struct ResolvedPropertyDelegateSignature {
    let returnType: TypeID
}

extension DeclTypeChecker {
    private func bindPropertyContextParameters(
        _ property: PropertyDecl,
        accessorSymbol: SymbolID,
        sema: SemaModule,
        locals: inout LocalBindings
    ) -> [TypeID] {
        guard let signature = sema.symbols.functionSignature(for: accessorSymbol) else {
            return []
        }
        let declarations = property.contextReceivers.filter(\.isContextParameter)
        for index in declarations.indices {
            guard signature.contextParameterSymbols.indices.contains(index),
                  signature.contextParameterTypes.indices.contains(index),
                  let name = declarations[index].name
            else {
                continue
            }
            locals[name] = (
                signature.contextParameterTypes[index],
                signature.contextParameterSymbols[index],
                false,
                true
            )
        }
        return signature.contextReceiverTypes
    }

    /// - Parameter baseLocals: Seeds the accessor body's local-name resolution
    ///   with bindings from an enclosing scope, mirroring
    ///   `typeCheckFunctionDecl`'s parameter of the same name. Empty for
    ///   ordinary member properties (a named class has no enclosing local scope
    ///   to capture). Object-literal member properties pass the enclosing
    ///   function's `locals` so an accessor body can resolve captured outer
    ///   variables the same way that literal's member function bodies do
    ///   (KSP-CAP-001/KSP-CAP-018).
    func typeCheckGetter(
        _ getter: PropertyAccessorDecl,
        property: PropertyDecl,
        symbol: SymbolID,
        inferredPropertyType: TypeID?,
        accessorCtx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) -> TypeID? {
        // A bodyless accessor uses the property's default getter. It does not
        // have a Unit-valued function body to constrain against the property.
        guard getter.body != .unit else { return inferredPropertyType }
        let accessorCtx = driver.helpers.accessorOptInContext(annotations: getter.annotations, ctx: accessorCtx)
        let sema = accessorCtx.sema
        let interner = accessorCtx.interner
        var getterLocals: LocalBindings = baseLocals
        if let receiverType = sema.symbols.extensionPropertyReceiverType(for: symbol) {
            // Match the property-based receiver parameter used by KIR accessors.
            getterLocals[interner.intern("this")] = (
                receiverType, SyntheticSymbolScheme.receiverParameterSymbol(for: symbol), false, true
            )
        }
        let accessorSymbol = sema.symbols.extensionPropertyGetterAccessor(for: symbol)
            ?? SyntheticSymbolScheme.propertyGetterAccessorSymbol(for: symbol)
        let contextTypes = bindPropertyContextParameters(
            property,
            accessorSymbol: accessorSymbol,
            sema: sema,
            locals: &getterLocals
        )
        let getterContext = accessorCtx.with(
            contextReceiverTypes: accessorCtx.contextReceiverTypes + contextTypes
        )
        if let fieldType = inferredPropertyType {
            let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
            getterLocals[interner.intern("field")] = (fieldType, fieldSymbol, property.isVar, true)
        }
        let getterType = inferFunctionBodyType(
            getter.body, ctx: getterContext.copying(
                lambdaLabelStack: [],
                lambdaReturnScopes: [],
                lambdaDepth: 0,
                enclosingFunctionReturnType: inferredPropertyType,
                enclosingFunctionSymbol: accessorSymbol,
                enclosingFunctionProhibitsExpressionBodyReturn: getter.body.isExpressionBody
                    && property.type == nil,
                returnTargetIsInitBlock: false,
                enclosingLambdaExprIDs: []
            ), locals: &getterLocals,
            expectedType: inferredPropertyType
        )
        if let declaredType = inferredPropertyType {
            // Range expressions infer as their scalar element type rather than the
            // source-level range interface, so `val r: IntRange get() = a..b` skips
            // the nominal subtype check like the equivalent expression-bodied
            // function and local declaration do.
            let bodyIsRangeExpr = {
                guard case let .expr(bodyExprID, _) = getter.body else { return false }
                return driver.helpers.rangeExprMatchesDeclaredElementType(
                    bodyExprID: bodyExprID,
                    bodyType: getterType,
                    declaredType: declaredType,
                    sema: sema,
                    interner: interner
                )
            }()
            if !bodyIsRangeExpr {
                driver.emitSubtypeConstraint(
                    left: getterType, right: declaredType,
                    range: getter.range, solver: solver,
                    sema: sema, diagnostics: diagnostics
                )
            }
            return inferredPropertyType
        }
        return getterType
    }

    func typeCheckDelegate(
        _ delegateExpr: ExprID,
        isVar: Bool,
        fallbackRange: SourceRange,
        symbol: SymbolID,
        inferredPropertyType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        diagnostics: DiagnosticEngine,
        delegateBody: FunctionBody? = nil,
        delegateBodyParams: [InternedString] = []
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        var result = inferredPropertyType
        let thisName = interner.intern("this")
        if locals[thisName] == nil, let receiverType = ctx.implicitReceiverType {
            // Delegate lambdas capture the property's implicit receiver. Keep
            // that receiver in locals so data-flow analysis can key stable
            // member-property facts to the same `this` reference.
            locals[thisName] = (
                receiverType,
                SyntheticSymbolScheme.receiverParameterSymbol(for: symbol),
                false,
                true
            )
        }
        let stdlibDelegateKind = StdlibDelegateKind.detect(
            delegateExpr: delegateExpr, ast: ctx.ast, interner: interner
        )
        // `var name: String by Delegates.notNull()` has nothing to infer the
        // factory's type argument from except the declared property type, so
        // feed it back in as the expected delegate type (`Lazy<String>` /
        // `ReadWriteProperty<Any?, String>`).
        let expectedDelegateType = inferredPropertyType.flatMap { valueType -> TypeID? in
            if let stdlibType = stdlibDelegateInterfaceType(
                of: valueType, kind: stdlibDelegateKind, sema: sema, interner: interner
            ) {
                return stdlibType
            }
            guard stdlibDelegateKind == .custom,
                  customDelegateFactoryReturnsReadWriteProperty(delegateExpr, ctx: ctx)
            else {
                return nil
            }
            return readWritePropertyDelegateInterfaceType(
                of: valueType, sema: sema, interner: interner
            )
        }
        let contextualDelegateType = expectedDelegateType == nil
            ? inferredPropertyType.flatMap {
                inferDelegateFactoryTypeFromConventionContext(
                    delegateExpr,
                    propertySymbol: symbol,
                    valueType: $0,
                    isMutable: isVar,
                    ctx: ctx,
                    locals: locals
                )
            }
            : nil
        // A `fun interface` SAM constructor used directly as the delegate
        // (`val p by ReadOnlyProperty { _, property -> property }`, KT-78073)
        // binds its getValue `thisRef` parameter from the delegate convention —
        // the only inference source an in-position interface parameter has
        // when no explicit type arguments or declared property type exist
        // (KUU-3839). Remaining parameters are inferred from the lambda's
        // return type inside the SAM constructor path.
        let samConstructorDelegateType = (expectedDelegateType == nil && contextualDelegateType == nil)
            ? samConstructorExpectedDelegateType(
                for: delegateExpr,
                propertySymbol: symbol,
                ctx: ctx
            )
            : nil
        let delegateType = driver.inferExpr(
            delegateExpr, ctx: ctx, locals: &locals,
            expectedType: expectedDelegateType ?? contextualDelegateType ?? samConstructorDelegateType
        )

        // Record the delegate type for KIR lowering.
        sema.symbols.setPropertyType(
            delegateType,
            for: SymbolID(rawValue: -(symbol.rawValue + 50000))
        )

        // The delegate expression already has a diagnostic. Avoid reporting
        // follow-on convention errors such as a missing getValue on errorType.
        if delegateType == sema.types.errorType {
            return result ?? sema.types.nullableAnyType
        }

        // Resolve getValue through the property-delegate convention. Unlike a
        // normal member lookup, the convention also admits visible extension
        // functions whose receiver is the delegate type.
        let getValueName = interner.intern("getValue")
        let delegateCallRange = ctx.ast.arena.exprRange(delegateExpr) ?? fallbackRange
        let delegateAccessorArgs = propertyDelegateAccessorArgumentTypes(
            for: symbol,
            valueType: result,
            ctx: ctx
        )
        let getValueExpectedType = result
            ?? mapDelegateValueType(delegateType, sema: sema, interner: interner)
        let getValueResolution = resolvePropertyDelegateFunction(
            named: getValueName,
            receiverType: delegateType,
            argumentTypes: Array(delegateAccessorArgs.prefix(2)),
            expectedType: getValueExpectedType,
            range: delegateCallRange,
            ctx: ctx,
            locals: locals,
            fallbackReceiverType: expectedDelegateType
        )
        // Tracks whether getValue/setValue were actually resolved for the *effective*
        // delegate type (see below: provideDelegate, when present, fully supersedes
        // this direct check). Deliberately not read back from
        // sema.symbols.delegateGetValueSymbol(for:) for the diagnostic below — that
        // symbol table entry is only ever set on success and never cleared, so if a
        // provideDelegate re-resolution later fails, a stale symbol from this direct
        // check would otherwise mask the failure.
        var getValueResolved = false
        var setValueResolved = false
        var getValueDiagnosticReported = getValueResolution?.diagnostic != nil
        var setValueDiagnosticReported = false

        if let getValueResolution,
           let getValueSymbol = getValueResolution.symbol,
           let getValueSig = resolvedDelegateCallSignature(
               for: getValueResolution,
               sema: sema
           )
        {
            sema.symbols.setDelegateGetValueSymbol(getValueSymbol, for: symbol)
            if result == nil {
                // Map's source-backed getValue uses the exact value type
                // from its receiver. The `V1 : V` return type is represented as a
                // separate source type parameter, so recover that bound here when
                // projected receiver lookup cannot substitute it automatically.
                result = mapDelegateValueType(delegateType, sema: sema, interner: interner)
                    ?? getValueSig.returnType
            }
            getValueResolved = true
        }

        if isVar, let valueType = result {
            let setValueName = interner.intern("setValue")
            let setValueResolution = resolvePropertyDelegateFunction(
                named: setValueName,
                receiverType: delegateType,
                argumentTypes: propertyDelegateAccessorArgumentTypes(
                    for: symbol,
                    valueType: valueType,
                    ctx: ctx
                ),
                expectedType: nil,
                range: delegateCallRange,
                ctx: ctx,
                locals: locals,
                fallbackReceiverType: expectedDelegateType
            )
            setValueDiagnosticReported = setValueResolution?.diagnostic != nil
            if let setValueResolution,
               let setValueSymbol = setValueResolution.symbol,
               let setValueSig = resolvedDelegateCallSignature(
                   for: setValueResolution,
                   sema: sema
               ),
               sema.types.isSubtype(setValueSig.returnType, sema.types.unitType)
            {
                sema.symbols.setDelegateSetValueSymbol(setValueSymbol, for: symbol)
                setValueResolved = true
            }
        }

        let provideDelegateName = interner.intern("provideDelegate")
        let expectedProvidedType = isVar ? result.flatMap {
            inferProvidedMutableDelegateType(
                delegateType, propertySymbol: symbol, valueType: $0, ctx: ctx, locals: locals
            )
        } : nil
        let provideDelegateResolution = resolvePropertyDelegateFunction(
            named: provideDelegateName,
            receiverType: delegateType,
            argumentTypes: Array(propertyDelegateProvideDelegateArgumentTypes(
                for: symbol,
                ctx: ctx
            ).prefix(2)),
            expectedType: expectedProvidedType,
            range: delegateCallRange,
            ctx: ctx,
            locals: locals
        )
        if let provideDelegateResolution,
           let provideDelegateSymbol = provideDelegateResolution.symbol
        {
            sema.symbols.setHasProvideDelegate(for: symbol)
            sema.symbols.setDelegateProvideDelegateSymbol(provideDelegateSymbol, for: symbol)

            // When provideDelegate is present, the actual delegate is the return type of
            // provideDelegate. Re-resolve getValue/setValue against the actual delegate type.
            if let sig = resolvedDelegateCallSignature(
                for: provideDelegateResolution,
                sema: sema
            ) {
                let actualDelegateType = sig.returnType
                // provideDelegate's return type is the effective delegate, so its
                // resolution (success or failure) fully supersedes the direct check above.
                let actualAccessorArgs = propertyDelegateAccessorArgumentTypes(
                    for: symbol,
                    valueType: result,
                    ctx: ctx
                )
                let actualGetValueResolution = resolvePropertyDelegateFunction(
                    named: getValueName,
                    receiverType: actualDelegateType,
                    argumentTypes: Array(actualAccessorArgs.prefix(2)),
                    expectedType: result,
                    range: delegateCallRange,
                    ctx: ctx,
                    locals: locals,
                    allowNonOperatorMemberOverride: true
                )
                getValueResolved = actualGetValueResolution?.symbol != nil
                getValueDiagnosticReported = actualGetValueResolution?.diagnostic != nil
                if let actualGetValueResolution,
                   let actualGetValueSymbol = actualGetValueResolution.symbol
                {
                    sema.symbols.setDelegateGetValueSymbol(actualGetValueSymbol, for: symbol)
                    // When provideDelegate is present, the property type must be inferred from
                    // the actual delegate's getValue, not the original expression's getValue.
                    // Only override result if no explicit type annotation was provided.
                    if result == nil,
                       let actualGetValueSig = resolvedDelegateCallSignature(
                           for: actualGetValueResolution,
                           sema: sema
                       ) {
                        result = actualGetValueSig.returnType
                    }
                }

                if isVar, let valueType = result {
                    let setValueName = interner.intern("setValue")
                    let actualSetValueResolution = resolvePropertyDelegateFunction(
                        named: setValueName,
                        receiverType: actualDelegateType,
                        argumentTypes: propertyDelegateAccessorArgumentTypes(
                            for: symbol,
                            valueType: valueType,
                            ctx: ctx
                        ),
                        expectedType: nil,
                        range: delegateCallRange,
                        ctx: ctx,
                        locals: locals,
                        allowNonOperatorMemberOverride: true
                    )
                    // Same rationale as getValueResolved above: provideDelegate's
                    // return type supersedes the direct check.
                    setValueResolved = false
                    setValueDiagnosticReported = actualSetValueResolution?.diagnostic != nil
                    if let actualSetValueResolution,
                       let actualSetValueSymbol = actualSetValueResolution.symbol,
                       let actualSetValueSig = resolvedDelegateCallSignature(
                           for: actualSetValueResolution,
                           sema: sema
                       ),
                       sema.types.isSubtype(actualSetValueSig.returnType, sema.types.unitType)
                    {
                        sema.symbols.setDelegateSetValueSymbol(actualSetValueSymbol, for: symbol)
                        setValueResolved = true
                    }
                }
            }
        }

        // Delegate trailing lambdas are now ordinary call arguments and have
        // already been type-checked by `inferExpr`. Keep the fallback body
        // check only for legacy ASTs whose body is not present in the call;
        // checking an included lambda again would duplicate diagnostics.
        let delegateBodyIsCallArgument = delegateBody != nil
            && delegateExpressionContainsLambdaArgument(delegateExpr, ast: ctx.ast)
        if !delegateBodyIsCallArgument, let delegateBody {
            var bodyLocals = locals
            for (index, name) in delegateBodyParams.enumerated() {
                let paramSymbol = SyntheticSymbolScheme.delegateLambdaParameterSymbol(
                    for: symbol, at: index
                )
                let paramType = index == 0 ? sema.types.anyType : (result ?? sema.types.anyType)
                bodyLocals[name] = (paramType, paramSymbol, false, true)
            }
            // `.observable`'s callback always returns Unit and `.vetoable`'s
            // always returns Boolean (the write proceeds only if true) --
            // BUG-151. Feeding this back as the expected type lets a body
            // returning the wrong type surface as an ordinary diagnostic
            // instead of silently mismatching at the runtime dispatch boundary.
            let expectedBodyType: TypeID? = switch stdlibDelegateKind {
            case .observable: sema.types.unitType
            case .vetoable: sema.types.booleanType
            default: result
            }
            _ = inferFunctionBodyType(
                delegateBody, ctx: ctx, locals: &bodyLocals, expectedType: expectedBodyType
            )
        }

        if !getValueResolved, !getValueDiagnosticReported {
            diagnostics.error(
                "KSWIFTK-SEMA-0103",
                "Property delegate must have a 'getValue' operator function.",
                range: ctx.ast.arena.exprRange(delegateExpr) ?? fallbackRange
            )
        }
        if isVar, !setValueResolved, !setValueDiagnosticReported {
            diagnostics.error(
                "KSWIFTK-SEMA-0104",
                "Mutable property delegate must have a 'setValue' operator function.",
                range: ctx.ast.arena.exprRange(delegateExpr) ?? fallbackRange
            )
        }

        // An explicitly declared delegated-property type is authoritative for
        // the local/property binding. This matters for generic extension
        // operators such as Map<in String, V>.getValue(...): V1, whose V1
        // return type is intentionally inferred from that declaration.
        if let inferredPropertyType {
            return inferredPropertyType
        }
        return result ?? sema.types.nullableAnyType
    }

    private func delegateExpressionContainsLambdaArgument(
        _ delegateExpr: ExprID,
        ast: ASTModule
    ) -> Bool {
        let args: [CallArgument]
        switch ast.arena.expr(delegateExpr) {
        case let .call(_, _, callArgs, _):
            args = callArgs
        case let .memberCall(_, _, _, memberArgs, _):
            args = memberArgs
        default:
            return false
        }
        guard let lastArgument = args.last else { return false }
        guard let expression = ast.arena.expr(lastArgument.expr) else {
            return false
        }
        if case .lambdaLiteral = expression {
            return true
        }
        return false
    }

    /// Member candidates are probed first because a member always wins over an
    /// extension; extensions are then taken from the visible scope and the
    /// existing bundled-stdlib fallback.
    private func resolvePropertyDelegateFunction(
        named name: InternedString,
        receiverType: TypeID,
        argumentTypes: [TypeID],
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings,
        allowNonOperatorMemberOverride: Bool = false,
        fallbackReceiverType: TypeID? = nil
    ) -> PropertyDelegateFunctionResolution? {
        let sema = ctx.sema
        let interner = ctx.interner
        let isMemberConventionCandidate: (SymbolID) -> Bool = { candidate in
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.kind == .function
            else {
                return false
            }
            if symbol.flags.contains(.operatorFunction) {
                return true
            }
            // Kotlin permits an override to omit `operator` when the
            // overridden declaration introduced the operator convention.
            // This exception is limited to member overrides; a same-named
            // non-operator extension is never a delegate convention.
            return allowNonOperatorMemberOverride
                && symbol.flags.contains(.overrideMember)
                && !symbol.flags.contains(.synthetic)
        }
        let memberCandidates = driver.helpers
            .collectMemberFunctionCandidates(
                named: name,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            )
            .filter(isMemberConventionCandidate)

        func resolve(
            _ candidates: [SymbolID],
            dispatchReceiverTypes: [TypeID] = [],
            callReceiverType: TypeID? = nil
        ) -> PropertyDelegateFunctionResolution? {
            guard !candidates.isEmpty else { return nil }
            let callReceiverType = callReceiverType ?? receiverType
            let call = CallExpr(
                range: range,
                calleeName: name,
                args: argumentTypes.map { CallArg(type: $0) },
                dispatchReceiverTypes: dispatchReceiverTypes
            )
            let inputProbe = ctx.resolver.probeCall(
                candidates: candidates,
                call: call,
                expectedType: nil,
                implicitReceiverType: callReceiverType,
                ctx: ctx.sema
            )
            driver.inferFunctionReturnTypesIfNeeded(for: inputProbe.viableCandidates.map(\.symbol))
            let probe = ctx.resolver.probeCall(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: callReceiverType,
                ctx: ctx.sema
            )
            guard !probe.viableCandidates.isEmpty else {
                return nil
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: callReceiverType,
                ctx: ctx.sema
            )
            return PropertyDelegateFunctionResolution(
                symbol: resolved.chosenCallee,
                substitutedTypeArguments: resolved.substitutedTypeArguments,
                diagnostic: resolved.diagnostic
            )
        }

        if let memberResolution = resolve(memberCandidates) {
            if let diagnostic = memberResolution.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
            }
            return memberResolution
        }

        // A generic factory returning an anonymous implementation can infer
        // its type argument from the property type, while the anonymous
        // class's recorded supertype still mentions the factory's source type
        // parameter. Resolve an interface member against the contextual
        // interface instantiation as a fallback so that type argument reaches
        // getValue/setValue substitution. KIR dispatches this abstract symbol
        // through the delegate's runtime interface table.
        if let fallbackReceiverType,
           fallbackReceiverType != receiverType,
           let fallbackMemberResolution = resolve(
               driver.helpers.collectMemberFunctionCandidates(
                   named: name,
                   receiverType: fallbackReceiverType,
                   sema: sema,
                   interner: interner
               ).filter(isMemberConventionCandidate),
               callReceiverType: fallbackReceiverType
           )
        {
            if let diagnostic = fallbackMemberResolution.diagnostic {
                sema.diagnostics.emit(diagnostic)
            }
            return fallbackMemberResolution
        }

        // Local functions live in LocalBindings rather than the lexical symbol
        // scopes. Applicable local operator extensions precede outer extensions,
        // but delegate members retain priority over every extension.
        if let local = locals[name],
           let symbol = ctx.cachedSymbol(local.symbol),
           symbol.kind == .function,
           symbol.flags.contains(.operatorFunction),
           let declaredReceiver = sema.symbols.functionSignature(for: local.symbol)?.receiverType,
           driver.callChecker.extensionSyntheticFallbackReceiverMatches(
               callSiteReceiver: receiverType,
               declaredReceiver: declaredReceiver,
               sema: sema
           ),
           let localResolution = resolve([local.symbol])
        {
            if let diagnostic = localResolution.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
            }
            return localResolution
        }

        // Member extensions are declared on the dispatch receiver's class,
        // while their receiver is the delegate value. Search the lexical
        // receiver tower for those declarations and keep the two receiver
        // roles separate during overload resolution.
        let dispatchReceiverEntries = ctx.implicitReceiverMemberLookupEntries()
        let dispatchReceiverTypes = dispatchReceiverEntries.map(\.type)
        var seenMemberExtensionCandidates: Set<SymbolID> = []
        for dispatchReceiver in dispatchReceiverEntries {
            let memberExtensionCandidates = driver.helpers
                .collectMemberFunctionCandidates(
                    named: name,
                    receiverType: dispatchReceiver.type,
                    sema: sema,
                    interner: interner
                )
                .filter { candidate in
                    guard let symbol = sema.symbols.symbol(candidate) else {
                        return false
                    }
                    return symbol.kind == .function
                        && symbol.flags.contains(.operatorFunction)
                        && sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil
                }
            let visibleCandidates = ctx.filterByVisibility(memberExtensionCandidates).visible
                .filter { seenMemberExtensionCandidates.insert($0).inserted }
            if let memberExtensionResolution = resolve(
                visibleCandidates,
                dispatchReceiverTypes: dispatchReceiverTypes
            ) {
                if let diagnostic = memberExtensionResolution.diagnostic {
                    ctx.sema.diagnostics.emit(diagnostic)
                }
                return memberExtensionResolution
            }
        }

        // A same-named extension only shadows outer scopes when it can
        // satisfy this convention call. Check the complete signature before
        // choosing a lexical tier, including thisRef and generic bounds.
        let scopeCandidates = ctx.scope.lookup(name, matching: { candidate in
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  symbol.flags.contains(.operatorFunction),
                  !(symbol.flags.contains(.expectDeclaration)
                    && sema.symbols.actualSymbol(for: candidate) != nil),
                  sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil,
                  !ctx.filterByVisibility([candidate]).visible.isEmpty,
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }
            guard driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: receiverType,
                declaredReceiver: declaredReceiver,
                sema: sema
            ) else { return false }
            // An expression-bodied extension's return stays the `Any`
            // placeholder until its body is checked; the expected-type probe
            // below would wrongly reject it when the property type is declared
            // (KUU-3206). Resolve the inferred return type first so the probe
            // sees the real signature, mirroring `resolve` above.
            driver.inferFunctionReturnTypesIfNeeded(for: [candidate])
            let call = CallExpr(
                range: range,
                calleeName: name,
                args: argumentTypes.map { CallArg(type: $0) }
            )
            return !ctx.resolver.probeCall(
                candidates: [candidate],
                call: call,
                expectedType: expectedType,
                implicitReceiverType: receiverType,
                ctx: sema
            ).viableCandidates.isEmpty
        })

        func resolveExtensions(_ extensionCandidates: [SymbolID]) -> PropertyDelegateFunctionResolution? {
            // A MutableMap delegate has both the Map and MutableMap getValue
            // extensions in an imported stdlib artifact. Prefer the more specific
            // MutableMap receiver before overload resolution, otherwise the two
            // projected signatures are reported as ambiguous.
            var preferredExtensionCandidates = extensionCandidates
            if name == interner.intern("getValue"),
               argumentTypes.count == 2,
               isMutableMapDelegateType(receiverType, sema: sema, interner: interner)
            {
                let mutableMapFQName = [
                    interner.intern("kotlin"),
                    interner.intern("collections"),
                    interner.intern("MutableMap"),
                ]
                let mutableMapCandidates = extensionCandidates.filter { candidate in
                    guard let signature = sema.symbols.functionSignature(for: candidate),
                          let declaredReceiver = signature.receiverType,
                          let receiverSymbol = driver.helpers.nominalSymbol(of: declaredReceiver, types: sema.types),
                          let receiverInfo = sema.symbols.symbol(receiverSymbol)
                    else {
                        return false
                    }
                    return receiverInfo.fqName == mutableMapFQName
                }
                if !mutableMapCandidates.isEmpty {
                    preferredExtensionCandidates = mutableMapCandidates
                }
            }
            if let extensionResolution = resolve(preferredExtensionCandidates) {
                if let diagnostic = extensionResolution.diagnostic {
                    ctx.sema.diagnostics.emit(diagnostic)
                }
                return extensionResolution
            }

            return nil
        }

        if let scopeResolution = resolveExtensions(ctx.filterByVisibility(scopeCandidates).visible) {
            return scopeResolution
        }

        let bundledCandidates = driver.callChecker.collectBundledStdlibExtensionCandidates(
            named: name,
            receiverType: receiverType,
            requireOperator: true,
            sourceFile: ctx.currentASTFile,
            sema: sema,
            interner: interner
        )
        // Default-imported collection delegate operators are not covered by
        // the atomic-only bundled extension fallback.
        let mapCandidates = bundledMapDelegateCandidates(
            named: name,
            sema: sema,
            interner: interner
        )
        var seen: Set<SymbolID> = []
        let fallbackCandidates = (bundledCandidates + mapCandidates).filter { seen.insert($0).inserted }
        return resolveExtensions(fallbackCandidates)
    }

    func isMutableMapDelegateType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        return symbol.fqName == [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("MutableMap"),
        ]
    }

    private func mapDelegateValueType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              classType.args.count == 2,
              let symbol = sema.symbols.symbol(classType.classSymbol),
              symbol.fqName == [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Map")]
                || symbol.fqName == [interner.intern("kotlin"), interner.intern("collections"), interner.intern("MutableMap")]
        else {
            return nil
        }
        return switch classType.args[1] {
        case let .invariant(value), let .out(value), let .in(value): value
        case .star: nil
        }
    }

    func bundledMapDelegateCandidates(
        named: InternedString,
        sema: SemaModule,
        interner: StringInterner
    ) -> [SymbolID] {
        sema.symbols.lookupByShortName(named).filter { candidateID in
            guard let symbol = sema.symbols.symbol(candidateID),
                  symbol.kind == .function,
                  symbol.flags.contains(.operatorFunction),
                  Array(symbol.fqName.dropLast()) == [interner.intern("kotlin"), interner.intern("collections")],
                  sema.symbols.isSourceBackedSymbol(candidateID),
                  let signature = sema.symbols.functionSignature(for: candidateID),
                  let receiverType = signature.receiverType,
                  case let .classType(receiverClass) = sema.types.kind(of:
                      sema.types.makeNonNullable(receiverType)
                  ),
                  let receiverSymbol = sema.symbols.symbol(receiverClass.classSymbol)
            else {
                return false
            }
            return receiverSymbol.fqName == [interner.intern("kotlin"), interner.intern("collections"), interner.intern("Map")]
                || receiverSymbol.fqName == [interner.intern("kotlin"), interner.intern("collections"), interner.intern("MutableMap")]
        }
    }

    func propertyDelegateAccessorArgumentTypes(
        for propertySymbol: SymbolID,
        valueType: TypeID?,
        ctx: TypeInferenceContext
    ) -> [TypeID] {
        let sema = ctx.sema
        let thisRefType = propertyDelegateThisRefType(
            for: propertySymbol,
            ctx: ctx
        )
        let kPropertyType: TypeID = if let kPropertySymbol = sema.symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("reflect"),
            ctx.interner.intern("KProperty"),
        ]) {
            sema.types.make(.classType(ClassType(
                classSymbol: kPropertySymbol,
                args: [.star],
                nullability: .nonNull
            )))
        } else {
            sema.types.anyType
        }
        var result = [thisRefType, kPropertyType]
        if let valueType {
            result.append(valueType)
        }
        return result
    }

    /// `provideDelegate` receives the containing dispatch receiver for a
    /// member extension property; its accessors receive the extension
    /// receiver. Top-level extension properties keep their extension receiver.
    func propertyDelegateProvideDelegateArgumentTypes(
        for propertySymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> [TypeID] {
        let sema = ctx.sema
        let thisRefType: TypeID
        if sema.symbols.symbol(propertySymbol)?.kind == .local {
            thisRefType = sema.types.nullableAnyType
        } else if let owner = sema.symbols.parentSymbol(for: propertySymbol),
                  let ownerSymbol = sema.symbols.symbol(owner),
                  [.class, .interface, .object, .enumClass].contains(ownerSymbol.kind)
        {
            let dispatchReceiver = ctx.implicitReceiverMemberLookupEntries().first { entry in
                guard case let .classType(receiverClass) = sema.types.kind(
                    of: sema.types.makeNonNullable(entry.type)
                ) else {
                    return false
                }
                return sema.types.isNominalSubtypeSymbol(receiverClass.classSymbol, of: owner)
            }?.type
            let ownerTypeArgs = sema.types.nominalTypeParameterSymbols(for: owner).map {
                TypeArg.invariant(sema.types.make(.typeParam(TypeParamType(symbol: $0))))
            }
            thisRefType = dispatchReceiver ?? sema.types.make(.classType(ClassType(
                classSymbol: owner,
                args: ownerTypeArgs,
                nullability: .nonNull
            )))
        } else {
            thisRefType = propertyDelegateThisRefType(for: propertySymbol, ctx: ctx)
        }
        let kPropertyType: TypeID = if let kPropertySymbol = sema.symbols.lookup(fqName: [
            ctx.interner.intern("kotlin"),
            ctx.interner.intern("reflect"),
            ctx.interner.intern("KProperty"),
        ]) {
            sema.types.make(.classType(ClassType(
                classSymbol: kPropertySymbol,
                args: [.star],
                nullability: .nonNull
            )))
        } else {
            sema.types.anyType
        }
        return [thisRefType, kPropertyType]
    }

    /// Expected type for a `by` delegate written as a bare SAM constructor
    /// (`InterfaceName { ... }` without explicit type arguments). The delegate
    /// convention's `getValue` `thisRef` argument is passed back as the
    /// interface argument for whichever type parameter occupies the SAM
    /// method's first parameter; the rest stay star-projected so the lambda's
    /// return type can infer them (KUU-3839).
    private func samConstructorExpectedDelegateType(
        for delegateExpr: ExprID,
        propertySymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard let interfaceSymbol = driver.callChecker.inferableSamConstructorSymbol(
            delegateExpr, ctx: ctx
        ),
            let samMethod = driver.helpers.effectiveSamAbstractMethod(
                for: interfaceSymbol, symbols: sema.symbols
            ),
            let methodSymbol = sema.symbols.symbol(samMethod),
            methodSymbol.name == interner.intern("getValue"),
            methodSymbol.flags.contains(.operatorFunction),
            let signature = sema.symbols.functionSignature(for: samMethod),
            let declaredThisRef = signature.parameterTypes.first,
            case let .typeParam(thisRefParam) = sema.types.kind(of: declaredThisRef)
        else {
            return nil
        }
        let typeParameters = sema.types.nominalTypeParameterSymbols(for: interfaceSymbol)
        guard !typeParameters.isEmpty,
              typeParameters.contains(thisRefParam.symbol)
        else {
            return nil
        }
        let thisRefType = propertyDelegateThisRefType(for: propertySymbol, ctx: ctx)
        let args: [TypeArg] = typeParameters.map { parameter in
            parameter == thisRefParam.symbol ? .invariant(thisRefType) : .star
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: args,
            nullability: .nonNull
        )))
    }

    private func propertyDelegateThisRefType(
        for propertySymbol: SymbolID,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        if sema.symbols.symbol(propertySymbol)?.kind == .local {
            return sema.types.nullableAnyType
        }
        if let extensionReceiver = sema.symbols.extensionPropertyReceiverType(for: propertySymbol) {
            return extensionReceiver
        }
        if let owner = sema.symbols.parentSymbol(for: propertySymbol),
           let ownerSymbol = sema.symbols.symbol(owner),
           [.class, .interface, .object, .enumClass].contains(ownerSymbol.kind)
        {
            if let implicitReceiver = ctx.implicitReceiverType {
                return implicitReceiver
            }
            return sema.types.make(.classType(ClassType(
                classSymbol: owner,
                args: [],
                nullability: .nonNull
            )))
        }
        return sema.types.nullableAnyType
    }

    private func resolvedDelegateCallSignature(
        for resolution: PropertyDelegateFunctionResolution,
        sema: SemaModule
    ) -> ResolvedPropertyDelegateSignature? {
        guard let symbol = resolution.symbol,
              let signature = sema.symbols.functionSignature(for: symbol)
        else {
            return nil
        }
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        let substitute = { (type: TypeID) in
            sema.types.substituteTypeParameters(
                in: type,
                substitution: resolution.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        }
        return ResolvedPropertyDelegateSignature(
            returnType: substitute(signature.returnType)
        )
    }

    private func stdlibDelegateInterfaceType(
        of valueType: TypeID,
        kind: StdlibDelegateKind,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard kind != .custom else {
            return nil
        }
        if kind != .lazy {
            return readWritePropertyDelegateInterfaceType(
                of: valueType, sema: sema, interner: interner
            )
        }
        guard let ownerSymbol = sema.symbols.lookup(
            fqName: stdlibDelegateInterfaceFQName(for: kind).map { interner.intern($0) }
        ) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: ownerSymbol, args: [.out(valueType)], nullability: .nonNull
        )))
    }

    /// A custom factory can use the property's declared type to infer its
    /// generic arguments when its result implements `ReadWriteProperty`. Keep
    /// this contextual type away from other custom delegates, whose convention
    /// methods need not implement the marker interface.
    private func customDelegateFactoryReturnsReadWriteProperty(
        _ delegateExpr: ExprID?,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        guard let delegateExpr,
              case let .call(callee, _, arguments, _) = ctx.ast.arena.expr(delegateExpr),
              arguments.isEmpty,
              case let .nameRef(name, _) = ctx.ast.arena.expr(callee),
              let readWriteProperty = sema.symbols.lookup(
                  fqName: ["kotlin", "properties", "ReadWriteProperty"].map(ctx.interner.intern)
              )
        else {
            return false
        }
        let candidates = ctx.cachedScopeLookup(name).filter { candidate in
            ctx.cachedSymbol(candidate)?.kind == .function
        }
        let zeroArgumentCandidates = ctx.filterByVisibility(candidates).visible.filter { candidate in
            sema.symbols.functionSignature(for: candidate)?.parameterTypes.isEmpty == true
        }
        if zeroArgumentCandidates.count == 1 {
            driver.inferFunctionReturnTypesIfNeeded(for: zeroArgumentCandidates)
        }
        return zeroArgumentCandidates.contains { candidate in
            guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
            let nominalReturns = driver.helpers.allNominalSymbols(
                of: signature.returnType,
                types: sema.types,
                symbols: sema.symbols,
                interner: ctx.interner
            )
            return nominalReturns.contains {
                sema.types.isNominalSubtypeSymbol($0, of: readWriteProperty)
            }
        }
    }

    private func readWritePropertyDelegateInterfaceType(
        of valueType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let ownerSymbol = sema.symbols.lookup(
            fqName: ["kotlin", "properties", "ReadWriteProperty"].map(interner.intern)
        ) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: ownerSymbol,
            args: [.in(sema.types.makeNullable(sema.types.anyType)), .invariant(valueType)],
            nullability: .nonNull
        )))
    }

    private func stdlibDelegateInterfaceFQName(for kind: StdlibDelegateKind) -> [String] {
        kind == .lazy ? ["kotlin", "Lazy"] : ["kotlin", "properties", "ReadWriteProperty"]
    }

    /// - Parameter baseLocals: see `typeCheckGetter`.
    func typeCheckSetter(
        _ setter: PropertyAccessorDecl,
        property: PropertyDecl,
        symbol: SymbolID,
        finalPropertyType: TypeID,
        accessorCtx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine,
        baseLocals: LocalBindings = [:]
    ) {
        let accessorCtx = driver.helpers.accessorOptInContext(annotations: setter.annotations, ctx: accessorCtx)
        let sema = accessorCtx.sema
        let interner = accessorCtx.interner
        if !property.isVar {
            diagnostics.error(
                "KSWIFTK-SEMA-0005",
                "Setter is not allowed for read-only property.",
                range: setter.range
            )
        }
        var setterLocals: LocalBindings = baseLocals
        if let receiverType = sema.symbols.extensionPropertyReceiverType(for: symbol) {
            setterLocals[interner.intern("this")] = (
                receiverType, SyntheticSymbolScheme.receiverParameterSymbol(for: symbol), false, true
            )
        }
        let accessorSymbol = sema.symbols.extensionPropertySetterAccessor(for: symbol)
            ?? SyntheticSymbolScheme.propertySetterAccessorSymbol(for: symbol)
        let contextTypes = bindPropertyContextParameters(
            property,
            accessorSymbol: accessorSymbol,
            sema: sema,
            locals: &setterLocals
        )
        let setterContext = accessorCtx.with(
            contextReceiverTypes: accessorCtx.contextReceiverTypes + contextTypes
        )
        let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol)
            ?? symbol
        setterLocals[interner.intern("field")] = (
            finalPropertyType, fieldSymbol, true, true
        )
        let parameterName = setter.parameterName
            ?? interner.intern("value")
        let setterValueSymbol = SyntheticSymbolScheme
            .semaSetterValueSymbol(for: symbol)
        setterLocals[parameterName] = (
            finalPropertyType, setterValueSymbol, true, true
        )
        let setterType = inferFunctionBodyType(
            setter.body, ctx: setterContext.copying(
                lambdaLabelStack: [],
                lambdaReturnScopes: [],
                lambdaDepth: 0,
                enclosingFunctionReturnType: sema.types.unitType,
                enclosingFunctionSymbol: accessorSymbol,
                // Setters cannot declare a return type, so an expression
                // body always prohibits `return`.
                enclosingFunctionProhibitsExpressionBodyReturn: setter.body.isExpressionBody,
                returnTargetIsInitBlock: false,
                enclosingLambdaExprIDs: []
            ), locals: &setterLocals,
            expectedType: sema.types.unitType
        )
        driver.emitSubtypeConstraint(
            left: setterType, right: sema.types.unitType,
            range: setter.range, solver: solver,
            sema: sema, diagnostics: diagnostics
        )
    }
}
