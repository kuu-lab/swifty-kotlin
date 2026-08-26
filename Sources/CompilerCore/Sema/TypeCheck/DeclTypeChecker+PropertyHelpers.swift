
// Property accessor type-checking helpers extracted from DeclTypeChecker
// to keep the main file within SwiftLint length limits.

private struct PropertyDelegateFunctionResolution {
    let symbol: SymbolID?
    let substitutedTypeArguments: [TypeVarID: TypeID]
    let diagnostic: Diagnostic?
}

private struct ResolvedPropertyDelegateSignature {
    let parameterTypes: [TypeID]
    let returnType: TypeID
}

extension DeclTypeChecker {
    func typeCheckGetter(
        _ getter: PropertyAccessorDecl,
        symbol: SymbolID,
        inferredPropertyType: TypeID?,
        accessorCtx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) -> TypeID? {
        let sema = accessorCtx.sema
        let interner = accessorCtx.interner
        var getterLocals: LocalBindings = [:]
        if let fieldType = inferredPropertyType {
            let fieldSymbol = sema.symbols.backingFieldSymbol(for: symbol) ?? symbol
            getterLocals[interner.intern("field")] = (fieldType, fieldSymbol, true, true)
        }
        let getterType = inferFunctionBodyType(
            getter.body, ctx: accessorCtx, locals: &getterLocals,
            expectedType: inferredPropertyType
        )
        if let declaredType = inferredPropertyType {
            // Range expressions infer as their scalar element type rather than the
            // source-level range interface, so `val r: IntRange get() = a..b` skips
            // the nominal subtype check like the equivalent expression-bodied
            // function and local declaration do.
            let bodyIsRangeExpr = {
                guard case let .expr(bodyExprID, _) = getter.body else { return false }
                return sema.bindings.isRangeExpr(bodyExprID)
                    && driver.helpers.isRangeLikeType(declaredType, sema: sema, interner: interner)
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
        let stdlibDelegateKind = StdlibDelegateKind.detect(
            delegateExpr: delegateExpr, ast: ctx.ast, interner: interner
        )
        // `var name: String by Delegates.notNull()` has nothing to infer the
        // factory's type argument from except the declared property type, so
        // feed it back in as the expected delegate type (`Lazy<String>` /
        // `ReadWriteProperty<Any?, String>`).
        let expectedDelegateType = inferredPropertyType.flatMap { valueType in
            stdlibDelegateInterfaceType(
                of: valueType, kind: stdlibDelegateKind, sema: sema, interner: interner
            )
        }
        let delegateType = driver.inferExpr(
            delegateExpr, ctx: ctx, locals: &locals,
            expectedType: expectedDelegateType
        )

        // Record the delegate type for KIR lowering.
        sema.symbols.setPropertyType(
            delegateType,
            for: SymbolID(rawValue: -(symbol.rawValue + 50000))
        )

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
        let getValueResolution = resolvePropertyDelegateFunction(
            named: getValueName,
            receiverType: delegateType,
            argumentTypes: Array(delegateAccessorArgs.prefix(2)),
            expectedType: result,
            range: delegateCallRange,
            ctx: ctx
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
                result = getValueSig.returnType
            }
            getValueResolved = true
        }

        // Check setValue for var properties.
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
                ctx: ctx
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

        // Check provideDelegate operator.
        let provideDelegateName = interner.intern("provideDelegate")
        let provideDelegateCandidates = driver.helpers
            .collectMemberFunctionCandidates(
                named: provideDelegateName,
                receiverType: delegateType,
                sema: sema,
                interner: interner
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID)
                else { return false }
                return sym.flags.contains(.operatorFunction)
            }
        if !provideDelegateCandidates.isEmpty {
            sema.symbols.setHasProvideDelegate(for: symbol)
            if let provideDelegateSymbol = provideDelegateCandidates.first {
                sema.symbols.setDelegateProvideDelegateSymbol(provideDelegateSymbol, for: symbol)

                // When provideDelegate is present, the actual delegate is the return type of
                // provideDelegate. Re-resolve getValue/setValue against the actual delegate type.
                if let sig = resolvedDelegateMemberSignature(
                    for: provideDelegateSymbol,
                    receiverType: delegateType,
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
        }

        // Kotlin requires a delegate's (effective, post-provideDelegate) type to expose
        // getValue (and setValue for `var`) operators; a type lacking them is a compile
        // error, not a silent fallback to Any?. Skip the small set of stdlib delegate
        // factories (`lazy`, `Delegates.observable/vetoable/notNull`) whose dispatch KIR
        // lowering still hardcodes structurally (StdlibDelegateLoweringPass) rather than
        // resolving through the operator convention — that gap is tracked separately
        // (KSP-491/492) and must stay silent until those factories are wired to real
        // operator-based dispatch.
        let isKnownStdlibDelegate = stdlibDelegateKind != .custom
        if result == nil, isKnownStdlibDelegate {
            // These factories are dispatched structurally rather than through the
            // getValue operator, so the property type has to be read off the
            // factory's return type (`Lazy<T>` / `ReadWriteProperty<Any?, T>`)
            // instead of a resolved getValue signature.
            result = stdlibDelegateValueType(
                delegateType: delegateType,
                kind: stdlibDelegateKind,
                sema: sema,
                interner: interner
            )
        }

        // A stdlib delegate factory's trailing lambda is usually parsed into
        // `delegateBody` separately from `delegateExpr` -- see
        // `BuildASTPhase+DeclBuilders.swift` -- specifically so KIR lowering can
        // repackage it into a standalone synthetic function
        // (`lowerDelegateLambdaBody`). Because it's not part of `delegateExpr`,
        // the ordinary call-argument inference above would otherwise skip its
        // identifiers (BUG-170). `lazy` is the exception: its required
        // initializer lambda is included in `delegateExpr` so overload
        // resolution sees the real call signature, and inference above already
        // type-checks its body. Checking `delegateBody` again would duplicate
        // every diagnostic from that initializer.
        if isKnownStdlibDelegate, stdlibDelegateKind != .lazy, let delegateBody {
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

        if !getValueResolved, !getValueDiagnosticReported, !isKnownStdlibDelegate {
            diagnostics.error(
                "KSWIFTK-SEMA-0103",
                "Property delegate must have a 'getValue' operator function.",
                range: ctx.ast.arena.exprRange(delegateExpr) ?? fallbackRange
            )
        }
        if isVar, !setValueResolved, !setValueDiagnosticReported, !isKnownStdlibDelegate {
            diagnostics.error(
                "KSWIFTK-SEMA-0104",
                "Mutable property delegate must have a 'setValue' operator function.",
                range: ctx.ast.arena.exprRange(delegateExpr) ?? fallbackRange
            )
        }

        if result == nil {
            result = sema.types.nullableAnyType
        }

        return result
    }

    /// Resolve one property-delegate convention function with the same
    /// receiver/argument/generic rules used by ordinary calls. Member
    /// candidates are probed first because a member always wins over an
    /// extension; extensions are then taken from the visible scope and the
    /// existing bundled-stdlib fallback.
    private func resolvePropertyDelegateFunction(
        named name: InternedString,
        receiverType: TypeID,
        argumentTypes: [TypeID],
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        allowNonOperatorMemberOverride: Bool = false
    ) -> PropertyDelegateFunctionResolution? {
        let sema = ctx.sema
        let interner = ctx.interner
        let call = CallExpr(
            range: range,
            calleeName: name,
            args: argumentTypes.map { CallArg(type: $0) }
        )

        let memberCandidates = driver.helpers
            .collectMemberFunctionCandidates(
                named: name,
                receiverType: receiverType,
                sema: sema,
                interner: interner
            )
            .filter { candidate in
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

        func resolve(_ candidates: [SymbolID]) -> PropertyDelegateFunctionResolution? {
            guard !candidates.isEmpty else { return nil }
            let probe = ctx.resolver.probeCall(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: receiverType,
                ctx: ctx.semaCtx
            )
            guard !probe.viableCandidates.isEmpty else {
                return nil
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: candidates,
                call: call,
                expectedType: expectedType,
                implicitReceiverType: receiverType,
                ctx: ctx.semaCtx
            )
            return PropertyDelegateFunctionResolution(
                symbol: resolved.chosenCallee,
                substitutedTypeArguments: resolved.substitutedTypeArguments,
                diagnostic: resolved.diagnostic
            )
        }

        if let memberResolution = resolve(memberCandidates) {
            if let diagnostic = memberResolution.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
            }
            return memberResolution
        }

        let scopeCandidates = ctx.filterByVisibility(ctx.cachedScopeLookup(name)).visible
            .filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: receiverType,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            }
        let bundledCandidates = driver.callChecker.collectBundledStdlibExtensionCandidates(
            named: name,
            receiverType: receiverType,
            requireOperator: true,
            sema: sema,
            interner: interner
        )
        var extensionCandidates: [SymbolID] = []
        var seen: Set<SymbolID> = []
        for candidate in scopeCandidates + bundledCandidates where seen.insert(candidate).inserted {
            extensionCandidates.append(candidate)
        }
        if let extensionResolution = resolve(extensionCandidates) {
            if let diagnostic = extensionResolution.diagnostic {
                ctx.semaCtx.diagnostics.emit(diagnostic)
            }
            return extensionResolution
        }
        return nil
    }

    private func propertyDelegateAccessorArgumentTypes(
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
            parameterTypes: signature.parameterTypes.map(substitute),
            returnType: substitute(signature.returnType)
        )
    }

    /// The interface a stdlib delegate factory's result conforms to for a given
    /// value type: `Lazy<T>` for `lazy`, `ReadWriteProperty<Any?, T>` for the
    /// `Delegates` factories. Nil for `.custom` delegates.
    private func stdlibDelegateInterfaceType(
        of valueType: TypeID,
        kind: StdlibDelegateKind,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard kind != .custom,
              let ownerSymbol = sema.symbols.lookup(
                  fqName: stdlibDelegateInterfaceFQName(for: kind).map { interner.intern($0) }
              )
        else {
            return nil
        }
        let args: [TypeArg] = kind == .lazy
            ? [.out(valueType)]
            : [.in(sema.types.makeNullable(sema.types.anyType)), .invariant(valueType)]
        return sema.types.make(.classType(ClassType(
            classSymbol: ownerSymbol, args: args, nullability: .nonNull
        )))
    }

    private func stdlibDelegateInterfaceFQName(for kind: StdlibDelegateKind) -> [String] {
        kind == .lazy ? ["kotlin", "Lazy"] : ["kotlin", "properties", "ReadWriteProperty"]
    }

    /// The value type a stdlib delegate factory's result exposes:
    /// `Lazy<T>` → `T`, `ReadWriteProperty<Any?, T>` → `T`. Returns nil when the
    /// delegate type is not (a subtype of) the expected interface, e.g. because
    /// the factory call itself failed to resolve.
    private func stdlibDelegateValueType(
        delegateType: TypeID,
        kind: StdlibDelegateKind,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let ownerFQName = stdlibDelegateInterfaceFQName(for: kind)
        let valueArgIndex = kind == .lazy ? 0 : 1
        guard let ownerSymbol = sema.symbols.lookup(fqName: ownerFQName.map { interner.intern($0) }),
              let delegateClass = resolveClassType(delegateType, sema: sema)
        else {
            return nil
        }
        let args: [TypeArg]
        if delegateClass.classSymbol == ownerSymbol {
            args = delegateClass.args
        } else if let lifted = sema.types.liftedNominalSupertypeArgs(
            from: delegateClass.classSymbol,
            childArgs: delegateClass.args,
            to: ownerSymbol
        ) {
            args = lifted
        } else {
            return nil
        }
        guard valueArgIndex < args.count else { return nil }
        return switch args[valueArgIndex] {
        case let .invariant(type), let .out(type), let .in(type): type
        case .star: nil
        }
    }

    private func resolvedDelegateMemberSignature(
        for memberSymbol: SymbolID,
        receiverType: TypeID,
        sema: SemaModule
    ) -> FunctionSignature? {
        guard let signature = sema.symbols.functionSignature(for: memberSymbol) else {
            return nil
        }
        guard let ownerSymbol = sema.symbols.parentSymbol(for: memberSymbol),
              let receiverClass = resolveClassType(receiverType, sema: sema)
        else {
            return signature
        }

        let ownerArgs: [TypeArg]
        if receiverClass.classSymbol == ownerSymbol {
            ownerArgs = receiverClass.args
        } else if let liftedArgs = sema.types.liftedNominalSupertypeArgs(
            from: receiverClass.classSymbol,
            childArgs: receiverClass.args,
            to: ownerSymbol
        ) {
            ownerArgs = liftedArgs
        } else {
            return signature
        }

        let ownerTypeParameters = sema.types.nominalTypeParameterSymbols(for: ownerSymbol)
        guard !ownerTypeParameters.isEmpty, !ownerArgs.isEmpty else {
            return signature
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        var substitution: [TypeVarID: TypeID] = [:]
        for (index, typeParameterSymbol) in ownerTypeParameters.enumerated() {
            guard index < ownerArgs.count,
                  let typeVar = typeVarBySymbol[typeParameterSymbol]
            else {
                continue
            }
            switch ownerArgs[index] {
            case let .invariant(type), let .out(type), let .in(type):
                substitution[typeVar] = type
            case .star:
                substitution[typeVar] = sema.types.nullableAnyType
            }
        }
        guard !substitution.isEmpty else {
            return signature
        }

        let substitute = { (type: TypeID) in
            sema.types.substituteTypeParameters(
                in: type,
                substitution: substitution,
                typeVarBySymbol: typeVarBySymbol
            )
        }
        return FunctionSignature(
            receiverType: signature.receiverType.map(substitute),
            parameterTypes: signature.parameterTypes.map(substitute),
            returnType: substitute(signature.returnType),
            isSuspend: signature.isSuspend,
            canThrow: signature.canThrow,
            valueParameterSymbols: signature.valueParameterSymbols,
            valueParameterHasDefaultValues: signature.valueParameterHasDefaultValues,
            valueParameterIsVararg: signature.valueParameterIsVararg,
            valueParameterAllowsNonLocalReturn: signature.valueParameterAllowsNonLocalReturn,
            typeParameterSymbols: signature.typeParameterSymbols,
            reifiedTypeParameterIndices: signature.reifiedTypeParameterIndices,
            typeParameterUpperBounds: signature.typeParameterUpperBounds,
            typeParameterUpperBoundsList: signature.typeParameterUpperBoundsList,
            classTypeParameterCount: signature.classTypeParameterCount
        )
    }

    func typeCheckSetter(
        _ setter: PropertyAccessorDecl,
        property: PropertyDecl,
        symbol: SymbolID,
        finalPropertyType: TypeID,
        accessorCtx: TypeInferenceContext,
        solver: ConstraintSolver,
        diagnostics: DiagnosticEngine
    ) {
        let sema = accessorCtx.sema
        let interner = accessorCtx.interner
        if !property.isVar {
            diagnostics.error(
                "KSWIFTK-SEMA-0005",
                "Setter is not allowed for read-only property.",
                range: setter.range
            )
        }
        var setterLocals: LocalBindings = [:]
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
            setter.body, ctx: accessorCtx, locals: &setterLocals,
            expectedType: sema.types.unitType
        )
        driver.emitSubtypeConstraint(
            left: setterType, right: sema.types.unitType,
            range: setter.range, solver: solver,
            sema: sema, diagnostics: diagnostics
        )
    }
}
