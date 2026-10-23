import Foundation

extension ControlFlowTypeChecker {
    func inferDestructuringDeclExpr(
        _ id: ExprID,
        names: [InternedString?],
        isMutable: Bool,
        initializer: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let rhsType = driver.inferExpr(initializer, ctx: ctx, locals: &locals)
        let layout = ctx.ast.arena.destructuringDeclLayout(for: id)
        let usesNameBasedDestructuring = layout.map { layout in
            layout.syntax == .parentheses
                && (sema.nameBasedDestructuringMode == .complete || layout.properties.contains { $0 != nil })
        } ?? false

        for (index, name) in names.enumerated() {
            let entryMutable = layout.flatMap { layout in
                layout.mutableFlags.indices.contains(index) ? layout.mutableFlags[index] : nil
            } ?? isMutable
            if usesNameBasedDestructuring {
                guard let name else { continue }
                let propertyName = layout?.properties[index] ?? name
                let property: (type: TypeID, binding: DestructuringPropertyBinding?)
                if rhsType == sema.types.errorType {
                    property = (sema.types.errorType, nil)
                } else {
                    property = inferNameBasedForDestructuringProperty(
                        propertyName,
                        loopExpr: id,
                        receiverType: rhsType,
                        range: range,
                        ctx: ctx
                    )
                }
                let symbol = sema.symbols.define(
                    kind: .local,
                    name: name,
                    fqName: [interner.intern("__destructuring_\(id.rawValue)"), name],
                    declSite: range,
                    visibility: .private,
                    flags: entryMutable ? [.mutable] : []
                )
                sema.symbols.setPropertyType(property.type, for: symbol)
                locals[name] = (property.type, symbol, entryMutable, true)
                if let binding = property.binding {
                    sema.bindings.bindDestructuringProperty(id, index: index, binding: binding)
                }
                continue
            }
            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            let allComponentMembers = driver.helpers.collectMemberFunctionCandidates(
                named: componentName,
                receiverType: rhsType,
                sema: sema,
                interner: interner
            )
            let candidates = allComponentMembers.filter {
                ctx.cachedSymbol($0)?.flags.contains(.operatorFunction) == true
            }

            let componentType: TypeID
            if let candidate = candidates.first,
               let signature = sema.symbols.functionSignature(for: candidate)
            {
                // Substitute the receiver's class type arguments into the raw return
                // type so that e.g. Pair<List<T>,List<T>>.component1() yields List<T>
                // rather than the generic parameter A.  Fixes STDLIB-021-BUG-01 where
                // `.size` access on destructured partition() results failed to lower.
                componentType = specializeComponentReturnType(
                    signature.returnType,
                    receiverType: rhsType,
                    signature: signature,
                    sema: sema
                )
                sema.bindings.bindDestructuringComponentCallee(id, index: index, symbol: candidate)
            } else {
                // Fallback: componentN declared as an operator extension rather than
                // a member (e.g. the bundled `MatchResult.Destructured.componentN`).
                let scopeCandidates = componentOperatorExtensionCandidates(
                    named: componentName,
                    receiverType: rhsType,
                    ctx: ctx
                )
                if let candidate = scopeCandidates.first,
                   let signature = sema.symbols.functionSignature(for: candidate)
                {
                    componentType = specializeComponentReturnType(
                        signature.returnType,
                        receiverType: rhsType,
                        signature: signature,
                        sema: sema
                    )
                    sema.bindings.bindDestructuringComponentCallee(id, index: index, symbol: candidate)
                } else if allComponentMembers.contains(where: { driver.helpers.isNonOperatorConventionFunction($0, sema: sema) }) {
                    // A member `componentN` without `operator` cannot serve
                    // destructuring (kotlinc: 'operator' modifier is required).
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0432",
                        "'operator' modifier is required on 'component\(componentIndex)' in '\(driver.helpers.conventionReceiverDisplayName(rhsType, sema: sema, interner: interner))'.",
                        range: range
                    )
                    componentType = sema.types.errorType
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0086",
                        "Type does not have a 'component\(componentIndex)()' operator for destructuring.",
                        range: range
                    )
                    componentType = sema.types.errorType
                }
            }

            guard let name else {
                continue
            }

            let flags: SymbolFlags = entryMutable ? [.mutable] : []
            let symbol = sema.symbols.define(
                kind: .local,
                name: name,
                fqName: [
                    interner.intern("__destructuring_\(id.rawValue)"),
                    name,
                ],
                declSite: range,
                visibility: .private,
                flags: flags
            )
            sema.symbols.setPropertyType(componentType, for: symbol)
            locals[name] = (componentType, symbol, entryMutable, true)
        }

        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferForDestructuringExpr(
        _ id: ExprID,
        names: [InternedString?],
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        syntax: ForDestructuringSyntax,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let iterableType = driver.inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        invalidateNullableControlFlowAssignments(id, ctx: ctx, locals: &locals)
        let elementType = inferLoopElementType(
            exprID: id,
            iterableExpr: iterableExpr,
            iterableType: iterableType,
            range: range,
            locals: locals,
            ctx: ctx
        )
        let layout = ctx.ast.arena.destructuringDeclLayout(for: id)
        let usesNameBasedDestructuring = syntax == .parentheses
            && (sema.nameBasedDestructuringMode == .complete || layout?.properties.contains { $0 != nil } == true)

        var bodyLocals = locals

        for (index, name) in names.enumerated() {
            if usesNameBasedDestructuring {
                guard let name else { continue }
                let property: (type: TypeID, binding: DestructuringPropertyBinding?)
                if elementType == sema.types.errorType {
                    property = (sema.types.errorType, nil)
                } else {
                    property = inferNameBasedForDestructuringProperty(
                        layout.flatMap { layout in
                            layout.properties.indices.contains(index) ? layout.properties[index] : nil
                        } ?? name,
                        loopExpr: id,
                        receiverType: elementType,
                        range: range,
                        ctx: ctx
                    )
                }
                let symbol = sema.symbols.define(
                    kind: .local,
                    name: name,
                    fqName: [
                        interner.intern("__for_destructuring_\(id.rawValue)"),
                        name,
                    ],
                    declSite: range,
                    visibility: .private,
                    flags: []
                )
                sema.symbols.setPropertyType(property.type, for: symbol)
                bodyLocals[name] = (property.type, symbol, false, true)
                if let binding = property.binding {
                    sema.bindings.bindDestructuringProperty(id, index: index, binding: binding)
                }
                continue
            }

            let componentIndex = index + 1
            let componentName = interner.intern("component\(componentIndex)")

            let allComponentMembers = driver.helpers.collectMemberFunctionCandidates(
                named: componentName,
                receiverType: elementType,
                sema: sema,
                interner: interner
            )
            let candidates = allComponentMembers.filter {
                ctx.cachedSymbol($0)?.flags.contains(.operatorFunction) == true
            } + componentOperatorExtensionCandidates(
                named: componentName,
                receiverType: elementType,
                ctx: ctx
            )

            let componentType: TypeID
            if elementType == sema.types.errorType {
                componentType = sema.types.errorType
            } else if let candidate = candidates.first,
               let signature = sema.symbols.functionSignature(for: candidate)
            {
                componentType = specializeComponentReturnType(
                    signature.returnType,
                    receiverType: elementType,
                    signature: signature,
                    sema: sema
                )
                sema.bindings.bindDestructuringComponentCallee(id, index: index, symbol: candidate)
            } else if allComponentMembers.contains(where: { driver.helpers.isNonOperatorConventionFunction($0, sema: sema) }) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0432",
                    "'operator' modifier is required on 'component\(componentIndex)' in '\(driver.helpers.conventionReceiverDisplayName(elementType, sema: sema, interner: interner))'.",
                    range: range
                )
                componentType = sema.types.errorType
            } else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0087",
                    "Iterable element type does not have a 'component\(componentIndex)()' operator for destructuring.",
                    range: range
                )
                componentType = sema.types.errorType
            }

            guard let name else {
                continue
            }

            let symbol = sema.symbols.define(
                kind: .local,
                name: name,
                fqName: [
                    interner.intern("__for_destructuring_\(id.rawValue)"),
                    name,
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            sema.symbols.setPropertyType(componentType, for: symbol)
            bodyLocals[name] = (componentType, symbol, false, true)
        }

        var newLabelStack = ctx.loopLabelStack
        if let label = ctx.ast.arena.loopLabel(for: id) {
            newLabelStack.append(label)
        }
        let loopFlowScope = LoopControlFlowInferenceScope(label: ctx.ast.arena.loopLabel(for: id))
        var loopFlowScopes = ctx.loopFlowScopes
        loopFlowScopes.append(loopFlowScope)
        _ = driver.inferExpr(
            bodyExpr,
            ctx: ctx.copying(
                loopDepth: ctx.loopDepth + 1,
                loopLabelStack: newLabelStack,
                loopFlowScopes: loopFlowScopes
            ),
            locals: &bodyLocals,
            expectedType: nil,
            isStatementContext: true
        )
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    private func inferNameBasedForDestructuringProperty(
        _ name: InternedString,
        loopExpr: ExprID,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> (type: TypeID, binding: DestructuringPropertyBinding?) {
        let sema = ctx.sema
        guard sema.types.nullability(of: receiverType) != .nullable else {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0026",
                "Only safe (?.) or non-null asserted (!!.) calls are allowed on a nullable receiver.",
                range: range
            )
            return (sema.types.errorType, nil)
        }
        if let member = driver.helpers.lookupMemberProperty(
            named: name,
            receiverType: receiverType,
            sema: sema
        ) {
            guard let symbol = sema.symbols.symbol(member.symbol),
                  ctx.visibilityChecker.isAccessible(
                      symbol,
                      fromFile: ctx.currentFileID,
                      enclosingClass: ctx.enclosingClassSymbol
                  )
            else {
                if let symbol = sema.symbols.symbol(member.symbol) {
                    driver.helpers.emitVisibilityError(
                        for: symbol,
                        name: ctx.interner.resolve(name),
                        range: range,
                        diagnostics: sema.diagnostics
                    )
                }
                return (sema.types.errorType, nil)
            }
            driver.helpers.checkDeprecation(
                for: member.symbol,
                sema: sema,
                interner: ctx.interner,
                range: range,
                diagnostics: sema.diagnostics
            )
            driver.helpers.checkOptIn(
                for: member.symbol,
                ctx: ctx,
                range: range,
                diagnostics: sema.diagnostics
            )
            return (
                member.type,
                DestructuringPropertyBinding(propertySymbol: member.symbol, type: member.type, getterCall: nil)
            )
        }

        var extensionBinding: (property: SymbolID, getterCall: CallBinding)?
        let errorsBeforeResolution = sema.diagnostics.errorCount
        let extensionType = driver.callChecker.resolveExtensionPropertyGetter(
            id: loopExpr,
            calleeName: name,
            range: range,
            receiverType: receiverType,
            expectedType: nil,
            ctx: ctx,
            bindCall: false,
            bindExpression: false,
            onResolved: { propertySymbol, getterCall in
                extensionBinding = (propertySymbol, getterCall)
            }
        )
        if let extensionType, let resolved = extensionBinding {
            return (
                extensionType,
                DestructuringPropertyBinding(
                    propertySymbol: resolved.property,
                    type: extensionType,
                    getterCall: resolved.getterCall
                )
            )
        }

        if sema.diagnostics.errorCount == errorsBeforeResolution {
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(ctx.interner.resolve(name))'.",
                range: range
            )
        }
        return (sema.types.errorType, nil)
    }

    static func isRangeExpression(_ exprID: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(exprID) else { return false }
        switch expr {
        case let .binary(op, _, _, _):
            switch op {
            case .rangeTo, .rangeUntil, .downTo, .step:
                return true
            default:
                return false
            }
        default:
            return false
        }
    }

    /// `componentN` functions declared as extensions on `receiverType` (member
    /// lookup only finds them when they are declared inside the class). Scope
    /// lookup goes first so imported operator extensions win; the short-name
    /// sweep then recovers extensions that are visible without an import, such
    /// as the bundled `MatchResult.Destructured.componentN`.
    func componentOperatorExtensionCandidates(
        named componentName: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> [SymbolID] {
        let sema = ctx.sema
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)

        func matchesReceiver(_ candidate: SymbolID, requireOperator: Bool) -> Bool {
            guard let symbol = ctx.cachedSymbol(candidate),
                  symbol.kind == .function,
                  !requireOperator || symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  let declaredReceiver = signature.receiverType
            else {
                return false
            }
            return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                callSiteReceiver: nonNullReceiver,
                declaredReceiver: declaredReceiver,
                sema: sema
            )
        }

        let scoped = ctx.filterByVisibility(ctx.cachedScopeLookup(componentName)).visible
            .filter { matchesReceiver($0, requireOperator: true) }
        if !scoped.isEmpty {
            return scoped
        }
        return sema.symbols.lookupByShortName(componentName)
            .filter { matchesReceiver($0, requireOperator: true) }
            .sorted { $0.rawValue < $1.rawValue }
    }

    private func effectiveUpperBound(for symbol: SymbolID, sema: SemaModule) -> TypeID {
        let bounds = sema.symbols.typeParameterUpperBounds(for: symbol)
        if bounds.isEmpty { return sema.types.nullableAnyType }
        if bounds.count == 1 { return bounds[0] }
        return sema.types.make(.intersection(bounds))
    }

    /// Needed so that member accesses on the destructured variables (e.g. `.size`)
    /// resolve to the correct concrete type rather than to the raw type parameter.
    /// Fixes STDLIB-021-BUG-01.
    private func specializeComponentReturnType(
        _ rawReturn: TypeID,
        receiverType: TypeID,
        signature: FunctionSignature,
        sema: SemaModule
    ) -> TypeID {
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        guard case let .classType(classType) = sema.types.kind(of: nonNullReceiver),
              !classType.args.isEmpty,
              !signature.typeParameterSymbols.isEmpty
        else {
            return rawReturn
        }

        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)

        // A bare type-parameter type argument (e.g. the `K` in `Map.Entry<K, V>`)
        // names the symbol the return type is actually parameterized over. This is
        // the receiver class's own nominal K/V when componentN is declared as a
        // genuine member reusing those symbols (the historical synthetic Map.Entry
        // stubs), but is a distinct, freshly-declared K/V when componentN is a
        // standalone generic extension such as the bundled
        // `operator fun <K, V> Map.Entry<K, V>.component1(): K`. Reading the symbol
        // straight out of the declared receiver's own type argument — rather than
        // assuming it matches the receiver class's nominal parameters — keeps both
        // shapes working.
        func typeParamSymbol(in arg: TypeArg) -> SymbolID? {
            let typeID: TypeID
            switch arg {
            case let .invariant(t): typeID = t
            case let .out(t): typeID = t
            case let .in(t): typeID = t
            case .star: return nil
            }
            guard case let .typeParam(typeParam) = sema.types.kind(of: typeID) else { return nil }
            return typeParam.symbol
        }

        // Inherited members such as Map.Entry.key are declared on a supertype, so
        // lift the concrete receiver arguments through the nominal inheritance edge
        // before building the substitution.
        let declaredReceiver: (args: [TypeArg], paramSymbols: [SymbolID?])? = {
            guard let receiverType = signature.receiverType,
                  case let .classType(receiverClassType) = sema.types.kind(of: sema.types.makeNonNullable(receiverType))
            else {
                return nil
            }
            let liftedArgs = sema.types.liftedNominalSupertypeArgs(
                from: classType.classSymbol,
                childArgs: classType.args,
                to: receiverClassType.classSymbol
            ) ?? classType.args
            return (liftedArgs, receiverClassType.args.map(typeParamSymbol))
        }()
        let receiverArgs = declaredReceiver?.args ?? classType.args
        let declaredParamSymbols = declaredReceiver?.paramSymbols ?? []
        // Fallback for the rare shape where the declared receiver's type argument
        // isn't a bare type-parameter reference (so `typeParamSymbol` found
        // nothing): fall back to the receiver class's own nominal parameters,
        // which is what this substitution relied on before extension componentN
        // declarations existed.
        let classOwnParamSymbols = sema.types.nominalTypeParameterSymbols(for: classType.classSymbol)

        var substitution: [TypeVarID: TypeID] = [:]
        for (index, arg) in receiverArgs.enumerated() {
            let tpSymbol: SymbolID
            if index < declaredParamSymbols.count,
               let symbol = declaredParamSymbols[index],
               typeVarBySymbol[symbol] != nil
            {
                tpSymbol = symbol
            } else if index < classOwnParamSymbols.count,
                      typeVarBySymbol[classOwnParamSymbols[index]] != nil
            {
                tpSymbol = classOwnParamSymbols[index]
            } else if index < signature.classTypeParameterCount,
                      index < signature.typeParameterSymbols.count
            {
                tpSymbol = signature.typeParameterSymbols[index]
            } else {
                continue
            }
            guard let typeVar = typeVarBySymbol[tpSymbol] else { continue }
            switch arg {
            case let .invariant(t): substitution[typeVar] = t
            case let .out(t):       substitution[typeVar] = t
            case .in:               substitution[typeVar] = effectiveUpperBound(for: tpSymbol, sema: sema)
            case .star:             substitution[typeVar] = effectiveUpperBound(for: tpSymbol, sema: sema)
            }
        }

        guard !substitution.isEmpty else { return rawReturn }
        return sema.types.substituteTypeParameters(
            in: rawReturn,
            substitution: substitution,
            typeVarBySymbol: typeVarBySymbol
        )
    }
}
