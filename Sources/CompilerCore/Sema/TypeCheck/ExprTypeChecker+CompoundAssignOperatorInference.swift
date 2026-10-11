
extension ExprTypeChecker {
    private func bindCompoundAssignmentOperatorCall(
        exprID: ExprID,
        op: CompoundAssignOp,
        receiverType: TypeID,
        valueType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        requireUnitReturn: Bool,
        emitDiagnostics: Bool = true,
        bindCall: Bool = true
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        if !requireUnitReturn, !bindCall,
           receiverType == sema.types.charType, valueType == sema.types.intType,
           !hasInvalidBuiltinCharArithmetic(
               op: driver.helpers.compoundAssignToBinaryOp(op), lhs: receiverType, rhs: valueType, sema: sema
           )
        {
            return sema.types.unitType
        }
        // Kotlin resolves `a += b` in two phases: first the dedicated in-place
        // operator (e.g. `plusAssign`, which must return Unit), then the
        // corresponding binary operator (e.g. `plus`) rebinding as `a = a.plus(b)`.
        // Each phase must search its own operator name — otherwise a type that
        // defines only `plus` (no `plusAssign`) is never found here, and the
        // caller silently falls back to the builtin numeric/string compound-assign
        // path even though the receiver isn't numeric/string.
        let operatorNames = requireUnitReturn
            ? operatorFunctionNames(for: op, interner: interner)
            : operatorFunctionNames(for: driver.helpers.compoundAssignToBinaryOp(op), interner: interner)
        var operatorCandidates = collectOperatorCandidates(
            names: operatorNames,
            receiverType: receiverType,
            ctx: ctx
        )
        var usesScopedCharExtensions = false
        if operatorCandidates.isEmpty,
           sema.types.makeNonNullable(receiverType) == sema.types.charType
            || sema.types.makeNonNullable(valueType) == sema.types.charType,
           requireUnitReturn || hasInvalidBuiltinCharArithmetic(
               op: driver.helpers.compoundAssignToBinaryOp(op), lhs: receiverType, rhs: valueType, sema: sema
           )
        {
            operatorCandidates = collectScopedOperatorExtensionCandidates(
                names: operatorNames, receiverType: receiverType, ctx: ctx
            )
            usesScopedCharExtensions = true
        }
        guard !operatorCandidates.isEmpty else {
            return nil
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: operatorCandidates,
            call: CallExpr(
                range: range,
                calleeName: operatorNames[0],
                args: [CallArg(type: valueType)]
            ),
            expectedType: nil,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )

        if usesScopedCharExtensions, resolved.chosenCallee == nil,
           resolved.diagnostic?.code == "KSWIFTK-SEMA-0002"
        {
            return nil
        }
        if let diagnostic = resolved.diagnostic {
            if emitDiagnostics {
                ctx.semaCtx.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            }
            return sema.types.errorType
        }

        guard let chosen = resolved.chosenCallee else {
            return nil
        }

        let returnType: TypeID
        if bindCall {
            returnType = driver.callChecker.bindCallAndResolveReturnType(
                exprID,
                chosen: chosen,
                resolved: resolved,
                sema: sema
            )
        } else if let signature = sema.symbols.functionSignature(for: chosen) {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            returnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        } else {
            returnType = sema.types.anyType
        }

        if requireUnitReturn,
           !sema.types.isSubtype(returnType, sema.types.unitType)
        {
            if emitDiagnostics {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0300",
                    "Operator '\(interner.resolve(operatorNames[0]))' used in compound assignment must return Unit.",
                    range: range
                )
                sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            }
            return sema.types.errorType
        }

        if !requireUnitReturn,
           !sema.types.isSubtype(returnType, receiverType)
        {
            if emitDiagnostics {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0301",
                    "Operator '\(interner.resolve(operatorNames[0]))' result type must be assignable to the left-hand side.",
                    range: range
                )
                sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            }
            return sema.types.errorType
        }

        if bindCall {
            sema.bindings.bindExprType(exprID, type: sema.types.unitType)
        }
        return sema.types.unitType
    }

    /// Binds the zero-argument `inc()` / `dec()` call synthesized for `++` / `--`.
    /// A missing overload returns `nil` so primitive targets can continue through
    /// the existing builtin compound-assignment path.
    private func bindIncrementDecrementOperatorCall(
        exprID: ExprID,
        op: CompoundAssignOp,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let operatorName: InternedString? = switch op {
        case .plusAssign:
            interner.intern("inc")
        case .minusAssign:
            interner.intern("dec")
        default:
            nil
        }
        guard let operatorName else { return nil }
        let operatorCandidates = collectOperatorCandidates(
            names: [operatorName],
            receiverType: receiverType,
            ctx: ctx
        )
        guard !operatorCandidates.isEmpty else {
            return nil
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: operatorCandidates,
            call: CallExpr(
                range: range,
                calleeName: operatorName,
                args: []
            ),
            expectedType: nil,
            implicitReceiverType: receiverType,
            ctx: ctx.semaCtx
        )
        if let diagnostic = resolved.diagnostic {
            ctx.semaCtx.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let chosen = resolved.chosenCallee else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                range: range
            )
            sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            return sema.types.errorType
        }

        let returnType = driver.callChecker.bindCallAndResolveReturnType(
            exprID,
            chosen: chosen,
            resolved: resolved,
            sema: sema
        )
        guard sema.types.isSubtype(returnType, receiverType) else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0303",
                "Operator '\(interner.resolve(operatorName))' result type must be assignable to the left-hand side.",
                range: range
            )
            sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            return sema.types.errorType
        }

        sema.bindings.bindExprType(exprID, type: sema.types.unitType)
        return sema.types.unitType
    }

    private func isBuiltinNumericIncrementDecrementTarget(_ type: TypeID, sema: SemaModule) -> Bool {
        if case let .primitive(primitive, .nonNull) = sema.types.kind(of: type) {
            return primitive != .char && primitive != .boolean
        }
        return false
    }

    private func isPrimitiveIncrementDecrementTarget(_ type: TypeID, sema: SemaModule) -> Bool {
        if case .primitive = sema.types.kind(of: type) {
            return true
        }
        return false
    }

    private func reportMissingIncrementDecrementOperator(
        _ op: CompoundAssignOp,
        exprID: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let name = op == .plusAssign ? "inc" : "dec"
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0002",
            "No viable overload found for operator '\(name)'.",
            range: range
        )
        ctx.sema.bindings.bindExprType(exprID, type: ctx.sema.types.errorType)
        return ctx.sema.types.errorType
    }

    private func inferIncrementDecrementIfNeeded(
        exprID: ExprID,
        op: CompoundAssignOp,
        receiverType: TypeID,
        isMutable: Bool,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        guard ctx.ast.arena.isIncrementDecrement(exprID) else {
            return nil
        }
        // Numeric primitives (everything but Char) keep `++` / `--` on the builtin path even
        // though explicit `x.inc()` calls now resolve to the bundled extensions.
        let usesBuiltinIncrement = isBuiltinNumericIncrementDecrementTarget(receiverType, sema: ctx.sema)
        if !usesBuiltinIncrement,
           let resolvedType = bindIncrementDecrementOperatorCall(
            exprID: exprID,
            op: op,
            receiverType: receiverType,
            range: range,
            ctx: ctx
        ) {
            guard resolvedType != ctx.sema.types.errorType else {
                return resolvedType
            }
            guard isMutable else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
                ctx.sema.bindings.bindExprType(exprID, type: ctx.sema.types.errorType)
                return ctx.sema.types.errorType
            }
            return resolvedType
        }
        if !isPrimitiveIncrementDecrementTarget(receiverType, sema: ctx.sema),
           receiverType != ctx.sema.types.errorType
        {
            return reportMissingIncrementDecrementOperator(op, exprID: exprID, range: range, ctx: ctx)
        }
        return nil
    }

    /// Result type of an arithmetic compound assignment whose operator function could
    /// not be resolved: numeric targets keep their own type, everything else falls back
    /// to `Int` (BUG-015).
    private func numericCompoundAssignResultType(_ targetType: TypeID, ctx: TypeInferenceContext) -> TypeID {
        guard case let .primitive(primitive, .nonNull) = ctx.sema.types.kind(of: targetType) else {
            return ctx.sema.types.intType
        }
        switch primitive {
        case .boolean, .char:
            return ctx.sema.types.intType
        case .byte, .short, .int, .long, .float, .double, .uint, .ulong, .ubyte, .ushort:
            return targetType
        }
    }

    func rejectInvalidBuiltinCharCompoundAssignment(
        _ id: ExprID,
        op: CompoundAssignOp,
        lhs: TypeID,
        rhs: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        let binaryOp = driver.helpers.compoundAssignToBinaryOp(op)
        let invalidResult = lhs == sema.types.charType
            && [.add, .subtract].contains(binaryOp)
            && rhs != sema.types.intType
        guard invalidResult || hasInvalidBuiltinCharArithmetic(op: binaryOp, lhs: lhs, rhs: rhs, sema: sema) else {
            return false
        }
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0002",
            "No viable builtin Char operator for compound assignment.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return true
    }

    func inferCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        name: InternedString,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let intType = sema.types.intType
        let charType = sema.types.charType
        let stringType = sema.types.stringType

        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)
        if let local = locals[name] {
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: range
                )
            }
            if let resolvedType = inferIncrementDecrementIfNeeded(
                exprID: id,
                op: op,
                receiverType: local.type,
                isMutable: local.isMutable,
                range: range,
                ctx: ctx
            ) {
                if resolvedType != sema.types.errorType {
                    locals[name] = (local.type, local.symbol, local.isMutable, local.isInitialized)
                }
                return resolvedType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: local.type,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: true
            ) {
                if local.isMutable,
                   let binaryFallback = bindCompoundAssignmentOperatorCall(
                       exprID: id,
                       op: op,
                       receiverType: local.type,
                       valueType: valueType,
                       range: range,
                       ctx: ctx,
                       requireUnitReturn: false,
                       emitDiagnostics: false,
                       bindCall: false
                   ),
                   binaryFallback != sema.types.errorType
                {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0302",
                        "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                return resolvedType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: local.type,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: false
            ) {
                if resolvedType == sema.types.errorType || !local.isMutable {
                    if !local.isMutable, resolvedType != sema.types.errorType {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0014",
                            "Val cannot be reassigned.",
                            range: range
                        )
                    }
                    return resolvedType == sema.types.errorType ? resolvedType : sema.types.errorType
                }
                locals[name] = (local.type, local.symbol, local.isMutable, local.isInitialized)
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
            if !local.isMutable {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            }
            let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
            if rejectInvalidBuiltinCharCompoundAssignment(
                id, op: op, lhs: local.type, rhs: valueType, range: range, ctx: ctx
            ) {
                return sema.types.errorType
            }
            // Arithmetic compound assignment keeps the target's own numeric type
            // (BUG-015): demoting `Long`/`Double`/unsigned locals to `Int` here broke
            // later member resolution such as `longVar and 0xFFL`.
            let arithmeticResultType = numericCompoundAssignResultType(local.type, ctx: ctx)
            let resultType: TypeID = switch underlyingOp {
            case .add:
                if local.type == stringType || valueType == stringType {
                    stringType
                } else if local.type == charType, valueType == intType {
                    charType
                } else {
                    arithmeticResultType
                }
            case .subtract:
                if local.type == charType, valueType == intType {
                    charType
                } else {
                    arithmeticResultType
                }
            case .multiply, .divide, .modulo:
                arithmeticResultType
            default:
                local.type
            }
            locals[name] = (resultType, local.symbol, local.isMutable, local.isInitialized)
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // Members declared on a supertype are never found by
        // `cachedScopeLookup`: a `ClassMemberScope`'s parent is the
        // enclosing *lexical* scope (file/package), not the superclass's
        // scope, so scope lookup never walks the inheritance chain. Plain
        // reads and simple `=` reassignment already resolve inherited
        // properties through the inheritance-aware `lookupMemberProperty`
        // (see resolveImplicitReceiverMember above); reuse it here so that
        // `inheritedField += 1` resolves the same member, taking priority
        // over lexically scope-visible candidates just like
        // inferNameRefExpr does for plain reads.
        var implicitReceiverMember: (symbol: SemanticSymbol, type: TypeID)?
        for receiverType in ctx.implicitReceiverMemberLookupTypes() {
            if let member = driver.helpers.lookupMemberProperty(
                named: name,
                receiverType: sema.types.makeNonNullable(receiverType),
                sema: sema
            ),
               let memberSymbol = ctx.cachedSymbol(member.symbol)
            {
                implicitReceiverMember = (memberSymbol, member.type)
                break
            }
        }

        // Fall back to scope-visible property lookup for compound assignments
        // like `counter += 1` where `counter` is a top-level var or a member
        // property accessed via implicit receiver (inside a class/object
        // member function).
        let allCandidateIDs = ctx.cachedScopeLookup(name)
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, _) = ctx.filterByVisibility(dslFilteredIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        let scopeVisibleProperty = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package || (ctx.implicitReceiverType != nil
                && (parentSym.kind == .class || parentSym.kind == .object || parentSym.kind == .interface))
        })
        if let propSymbol = implicitReceiverMember?.symbol ?? scopeVisibleProperty {
            let (_, invisible) = ctx.filterByVisibility([propSymbol.id])
            if let property = invisible.first {
                driver.helpers.emitVisibilityError(
                    for: property,
                    name: interner.resolve(name),
                    range: range,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            if implicitReceiverMember != nil {
                sema.bindings.markImplicitReceiverMember(id, name: name)
            }
            let propType = implicitReceiverMember?.type ?? sema.symbols.propertyType(for: propSymbol.id) ?? sema.types.errorType
            if let resolvedType = inferIncrementDecrementIfNeeded(
                exprID: id,
                op: op,
                receiverType: propType,
                isMutable: propSymbol.flags.contains(.mutable),
                range: range,
                ctx: ctx
            ) {
                return resolvedType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: propType,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: true
            ) {
                if propSymbol.flags.contains(.mutable),
                   let binaryFallback = bindCompoundAssignmentOperatorCall(
                       exprID: id,
                       op: op,
                       receiverType: propType,
                       valueType: valueType,
                       range: range,
                       ctx: ctx,
                       requireUnitReturn: false,
                       emitDiagnostics: false,
                       bindCall: false
                   ),
                   binaryFallback != sema.types.errorType
                {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0302",
                        "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                return resolvedType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: propType,
                valueType: valueType,
                range: range,
                ctx: ctx,
                requireUnitReturn: false
            ) {
                if resolvedType == sema.types.errorType || !propSymbol.flags.contains(.mutable) {
                    if !propSymbol.flags.contains(.mutable), resolvedType != sema.types.errorType {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-SEMA-0014",
                            "Val cannot be reassigned.",
                            range: range
                        )
                    }
                    return resolvedType == sema.types.errorType ? resolvedType : sema.types.errorType
                }
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
            if !propSymbol.flags.contains(.mutable) {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
            }
            let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
            if rejectInvalidBuiltinCharCompoundAssignment(
                id, op: op, lhs: propType, rhs: valueType, range: range, ctx: ctx
            ) {
                return sema.types.errorType
            }
            let resultType: TypeID = switch underlyingOp {
            case .add:
                if propType == stringType || valueType == stringType {
                    stringType
                } else if propType == charType, valueType == intType {
                    charType
                } else {
                    intType
                }
            case .subtract:
                if propType == charType, valueType == intType {
                    charType
                } else {
                    intType
                }
            case .multiply, .divide, .modulo:
                intType
            default:
                propType
            }
            _ = resultType // top-level property type not updated in locals
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        if !dslBlockedIDs.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-DSLMARKER",
                "'@DslMarker' implicit access to '\(interner.resolve(name))' from outer receiver is restricted. Use explicit receiver.",
                range: range
            )
        } else if name == KnownCompilerNames(interner: interner).field {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-FIELD",
                "'field' can only be used inside a property getter or setter body.",
                range: range
            )
        } else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0013",
                "Unresolved local variable '\(interner.resolve(name))'.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    /// Resolve the property read in a compound assignment through the existing
    /// getter overload rules. Reserve the expression's call binding for its
    /// arithmetic operator; lowering reads and writes the selected property.
    private func resolveExtensionPropertyForCompoundAssignment(
        id: ExprID,
        named calleeName: InternedString,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> (symbol: SymbolID, type: TypeID)? {
        let sema = ctx.sema
        guard let propertyType = driver.callChecker.resolveExtensionPropertyGetter(
            id: id,
            calleeName: calleeName,
            range: range,
            receiverType: receiverType,
            expectedType: nil,
            ctx: ctx,
            bindCall: false
        ), let property = sema.bindings.identifierSymbol(for: id) else {
            return nil
        }
        return (property, propertyType)
    }

    /// Compound assignment through an explicit receiver, e.g. `obj.field += value`
    /// or `this.box.n += value`. Mirrors `inferCompoundAssignExpr`'s operator-overload
    /// resolution (`plusAssign` then binary-operator fallback) but resolves the
    /// left-hand side as a member property on `receiverExpr` instead of a bare name.
    func inferMemberCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        receiverExpr: ExprID,
        calleeName: InternedString,
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner

        let inferredReceiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)
        let receiverType = driver.helpers.retypeClassNameAsCompanionValue(
            receiverExpr,
            currentType: inferredReceiverType,
            ast: ctx.ast,
            sema: sema
        ) ?? inferredReceiverType
        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)

        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        guard let propResult = driver.helpers.lookupMemberProperty(
            named: calleeName,
            receiverType: nonNullReceiver,
            sema: sema
        ) ?? resolveExtensionPropertyForCompoundAssignment(
            id: id,
            named: calleeName,
            receiverType: receiverType,
            range: range,
            ctx: ctx
        ) else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(interner.resolve(calleeName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        sema.bindings.bindIdentifier(id, symbol: propResult.symbol)
        let propType = propResult.type
        let propSymbol = sema.symbols.symbol(propResult.symbol)
        if let propSymbol,
           !ctx.visibilityChecker.isAccessible(
               propSymbol,
               fromFile: ctx.currentFileID,
               enclosingClass: ctx.enclosingClassSymbol
           )
        {
            driver.helpers.emitVisibilityError(
                for: propSymbol,
                name: interner.resolve(calleeName),
                range: range,
                diagnostics: ctx.semaCtx.diagnostics
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        if let cachedValue = ctx.ast.arena.incrementDecrementCachedValue(for: id) {
            _ = driver.inferExpr(cachedValue, ctx: ctx, locals: &locals, expectedType: propType)
        }

        if let resolvedType = inferIncrementDecrementIfNeeded(
            exprID: id,
            op: op,
            receiverType: propType,
            isMutable: propSymbol?.flags.contains(.mutable) == true,
            range: range,
            ctx: ctx
        ) {
            return resolvedType
        }

        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: propType,
            valueType: valueType,
            range: range,
            ctx: ctx,
            requireUnitReturn: true
        ) {
            if propSymbol?.flags.contains(.mutable) == true,
               let binaryFallback = bindCompoundAssignmentOperatorCall(
                   exprID: id,
                   op: op,
                   receiverType: propType,
                   valueType: valueType,
                   range: range,
                   ctx: ctx,
                   requireUnitReturn: false,
                   emitDiagnostics: false,
                   bindCall: false
               ),
               binaryFallback != sema.types.errorType
            {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0302",
                    "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            return resolvedType
        }

        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: propType,
            valueType: valueType,
            range: range,
            ctx: ctx,
            requireUnitReturn: false
        ) {
            if resolvedType == sema.types.errorType || propSymbol?.flags.contains(.mutable) != true {
                if propSymbol?.flags.contains(.mutable) != true, resolvedType != sema.types.errorType {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0014",
                        "Val cannot be reassigned.",
                        range: range
                    )
                }
                return resolvedType == sema.types.errorType ? resolvedType : sema.types.errorType
            }
            sema.bindings.bindExprType(id, type: sema.types.unitType)
            return sema.types.unitType
        }

        // Primitive/builtin fallback (Int/Char/String arithmetic via `kk_op_*` or
        // string concat at KIR-lowering time). Unlike a bare local, a property's
        // declared type doesn't get narrowed per-assignment, so there is nothing
        // to propagate back into `locals` here.
        if rejectInvalidBuiltinCharCompoundAssignment(
            id, op: op, lhs: propType, rhs: valueType, range: range, ctx: ctx
        ) {
            return sema.types.errorType
        }
        if propSymbol?.flags.contains(.mutable) != true {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0014",
                "Val cannot be reassigned.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
