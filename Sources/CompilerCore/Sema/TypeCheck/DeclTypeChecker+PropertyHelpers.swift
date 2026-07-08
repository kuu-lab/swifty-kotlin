
// Property accessor type-checking helpers extracted from DeclTypeChecker
// to keep the main file within SwiftLint length limits.

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
            driver.emitSubtypeConstraint(
                left: getterType, right: declaredType,
                range: getter.range, solver: solver,
                sema: sema, diagnostics: diagnostics
            )
            return inferredPropertyType
        }
        return getterType
    }

    func typeCheckDelegate(
        _ delegateExpr: ExprID,
        property: PropertyDecl,
        symbol: SymbolID,
        inferredPropertyType: TypeID?,
        ctx: TypeInferenceContext,
        diagnostics: DiagnosticEngine
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        var result = inferredPropertyType
        var delegateLocals: LocalBindings = [:]
        let delegateType = driver.inferExpr(
            delegateExpr, ctx: ctx, locals: &delegateLocals,
            expectedType: nil
        )

        // Record the delegate type for KIR lowering.
        sema.symbols.setPropertyType(
            delegateType,
            for: SymbolID(rawValue: -(symbol.rawValue + 50000))
        )

        // Resolve getValue operator (Kotlin spec J12).
        let getValueName = interner.intern("getValue")
        let getValueCandidates = driver.helpers
            .collectMemberFunctionCandidates(
                named: getValueName,
                receiverType: delegateType,
                sema: sema,
                interner: interner
            ).filter { candidateID in
                guard let sym = sema.symbols.symbol(candidateID)
                else { return false }
                return sym.flags.contains(.operatorFunction)
            }
        // Tracks whether getValue/setValue were actually resolved for the *effective*
        // delegate type (see below: provideDelegate, when present, fully supersedes
        // this direct check). Deliberately not read back from
        // sema.symbols.delegateGetValueSymbol(for:) for the diagnostic below — that
        // symbol table entry is only ever set on success and never cleared, so if a
        // provideDelegate re-resolution later fails, a stale symbol from this direct
        // check would otherwise mask the failure.
        var getValueResolved = false
        var setValueResolved = false

        if let getValueSymbol = getValueCandidates.first,
           let getValueSig = resolvedDelegateMemberSignature(
               for: getValueSymbol,
               receiverType: delegateType,
               sema: sema
           ),
           result == nil
        {
            sema.symbols.setDelegateGetValueSymbol(getValueSymbol, for: symbol)
            result = getValueSig.returnType
            getValueResolved = true
        } else if let getValueSymbol = getValueCandidates.first {
            sema.symbols.setDelegateGetValueSymbol(getValueSymbol, for: symbol)
            getValueResolved = true
        }

        // Check setValue for var properties.
        if property.isVar {
            let setValueName = interner.intern("setValue")
            let setValueCandidates = driver.helpers
                .collectMemberFunctionCandidates(
                    named: setValueName,
                    receiverType: delegateType,
                    sema: sema,
                    interner: interner
                ).filter { candidateID in
                    guard let sym = sema.symbols.symbol(candidateID)
                    else { return false }
                    return sym.flags.contains(.operatorFunction)
                }
            if let setValueSymbol = setValueCandidates.first {
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
                    let allGetValueCandidates = driver.helpers
                        .collectMemberFunctionCandidates(
                            named: getValueName,
                            receiverType: actualDelegateType,
                            sema: sema,
                            interner: interner
                        )
                    // Accept operator functions first; fall back to any non-synthetic override
                    // (Kotlin allows omitting 'operator' on overrides of operator functions).
                    let actualGetValueCandidates = allGetValueCandidates.filter { candidateID in
                        guard let sym = sema.symbols.symbol(candidateID)
                        else { return false }
                        return sym.flags.contains(.operatorFunction)
                    }
                    let actualGetValueSymbol = actualGetValueCandidates.first
                        ?? allGetValueCandidates.first { candidateID in
                            guard let sym = sema.symbols.symbol(candidateID)
                            else { return false }
                            return !sym.flags.contains(.synthetic)
                        }
                    // provideDelegate's return type is the effective delegate, so its
                    // resolution (success or failure) fully supersedes the direct check above.
                    getValueResolved = actualGetValueSymbol != nil
                    if let actualGetValueSymbol {
                        sema.symbols.setDelegateGetValueSymbol(actualGetValueSymbol, for: symbol)
                        // When provideDelegate is present, the property type must be inferred from
                        // the actual delegate's getValue, not the original expression's getValue.
                        // Only override result if no explicit type annotation was provided.
                        if result == nil,
                           let actualGetValueSig = resolvedDelegateMemberSignature(
                               for: actualGetValueSymbol,
                               receiverType: actualDelegateType,
                               sema: sema
                           ) {
                            result = actualGetValueSig.returnType
                        }
                    }

                    if property.isVar {
                        let setValueName = interner.intern("setValue")
                        let allSetValueCandidates = driver.helpers.collectMemberFunctionCandidates(
                            named: setValueName,
                            receiverType: actualDelegateType,
                            sema: sema,
                            interner: interner
                        )
                        let actualSetValueCandidates = allSetValueCandidates.filter { candidateID in
                            guard let sym = sema.symbols.symbol(candidateID)
                            else { return false }
                            return sym.flags.contains(.operatorFunction)
                        }
                        let actualSetValueSymbol = actualSetValueCandidates.first
                            ?? allSetValueCandidates.first { candidateID in
                                guard let sym = sema.symbols.symbol(candidateID)
                                else { return false }
                                return !sym.flags.contains(.synthetic)
                            }
                        // Same rationale as getValueResolved above: provideDelegate's
                        // return type supersedes the direct check.
                        setValueResolved = actualSetValueSymbol != nil
                        if let actualSetValueSymbol {
                            sema.symbols.setDelegateSetValueSymbol(actualSetValueSymbol, for: symbol)
                        }
                    }
                }
            }
        }

        // Kotlin requires a delegate's (effective, post-provideDelegate) type to expose
        // getValue (and setValue for `var`) operators; a type lacking them is a compile
        // error, not a silent fallback to Any?. Skip the small set of stdlib delegate
        // factories (`lazy`, `Delegates.observable/vetoable/notNull`) whose dispatch KIR
        // lowering still hardcodes structurally (StdlibDelegateLoweringPass /
        // KIRLoweringDriver.detectDelegateKind) rather than resolving through the operator
        // convention — that gap is tracked separately (KSP-491/492) and must stay silent
        // until those factories are wired to real operator-based dispatch.
        let isKnownStdlibDelegate = isKnownStdlibDelegateFactory(
            delegateExpr, ast: ctx.ast, interner: interner
        )
        if !getValueResolved, !isKnownStdlibDelegate {
            diagnostics.error(
                "KSWIFTK-SEMA-0103",
                "Property delegate must have a 'getValue' operator function.",
                range: ctx.ast.arena.exprRange(delegateExpr) ?? property.range
            )
        }
        if property.isVar, !setValueResolved, !isKnownStdlibDelegate {
            diagnostics.error(
                "KSWIFTK-SEMA-0104",
                "Mutable property delegate must have a 'setValue' operator function.",
                range: ctx.ast.arena.exprRange(delegateExpr) ?? property.range
            )
        }

        if result == nil {
            result = sema.types.nullableAnyType
        }

        return result
    }

    /// Mirrors `KIRLoweringDriver.detectDelegateKind` + `detectDelegateKindFromCallExpr`
    /// (`Sources/CompilerCore/KIR/KIRLoweringDriver+ModuleLowering+PostProcess.swift`) so
    /// this diagnostic and KIR lowering agree on which delegate expressions are exempt
    /// from the operator-function convention. The name set intentionally differs *per AST
    /// node shape* there (a bare name only ever means the top-level `lazy` function; a
    /// member call only ever means `Delegates.observable/vetoable/notNull`) — keep this
    /// in sync if that logic changes, since a broader match here than in KIR lowering
    /// would silently suppress a real diagnostic for a `.custom` delegate.
    private func isKnownStdlibDelegateFactory(
        _ delegateExpr: ExprID,
        ast: ASTModule,
        interner: StringInterner
    ) -> Bool {
        guard let expr = ast.arena.expr(delegateExpr) else { return false }
        let lazyName = interner.intern("lazy")
        let observableName = interner.intern("observable")
        let vetoableName = interner.intern("vetoable")
        let notNullName = interner.intern("notNull")
        func isObservableFamily(_ name: InternedString) -> Bool {
            name == observableName || name == vetoableName || name == notNullName
        }
        switch expr {
        case let .nameRef(name, _):
            return name == lazyName
        case let .memberCall(_, name, _, _, _):
            return isObservableFamily(name)
        case let .call(callee, _, _, _):
            guard let calleeExpr = ast.arena.expr(callee) else { return false }
            switch calleeExpr {
            case let .nameRef(name, _):
                return isObservableFamily(name) || name == lazyName
            case let .memberCall(_, name, _, _, _):
                return isObservableFamily(name)
            default:
                return false
            }
        default:
            return false
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
