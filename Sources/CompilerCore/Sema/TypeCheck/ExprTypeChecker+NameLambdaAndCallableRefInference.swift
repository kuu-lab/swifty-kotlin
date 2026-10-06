
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
            receiverType: nonNullReceiver,
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

    func inferNameRefExpr(
        _ id: ExprID,
        name: InternedString,
        nameRange: SourceRange?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        isQualifier: Bool = false
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let knownNames = KnownCompilerNames(interner: interner)

        if name == knownNames.thisName,
           let receiverType = ctx.implicitReceiverType
        {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        if let local = locals[name],
           !isQualifier || sema.symbols.symbol(local.symbol)?.kind != .function
        {
            if !local.isInitialized {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: nameRange
                )
            }
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            // Propagate collection marks through variable references (P5-84).
            if sema.bindings.isCollectionSymbol(local.symbol) {
                sema.bindings.markCollectionExpr(id)
            }
            if sema.bindings.isRangeSymbol(local.symbol) {
                sema.bindings.markRangeExpr(id)
            }
            if sema.bindings.isCharRangeSymbol(local.symbol) {
                sema.bindings.markCharRangeExpr(id)
            }
            if sema.bindings.isUIntRangeSymbol(local.symbol) {
                sema.bindings.markUIntRangeExpr(id)
            }
            if sema.bindings.isULongRangeSymbol(local.symbol) {
                sema.bindings.markULongRangeExpr(id)
            }
            if sema.bindings.isFloatingPointRangeSymbol(local.symbol) {
                sema.bindings.markFloatingPointRangeExpr(id)
                if let elementType = sema.bindings.floatingPointRangeElementType(forSymbol: local.symbol) {
                    sema.bindings.bindFloatingPointRangeElementType(
                        elementType, forExpr: id,
                        endExclusive: sema.bindings.isOpenFloatingPointRangeSymbol(local.symbol)
                    )
                }
            }
            if sema.bindings.isFlowSymbol(local.symbol) {
                sema.bindings.markFlowExpr(id)
                if let flowElementType = sema.bindings.flowElementType(forSymbol: local.symbol) {
                    sema.bindings.bindFlowElementType(flowElementType, forExpr: id)
                }
            }
            sema.bindings.bindExprType(id, type: local.type)
            return local.type
        }
        // An uninvoked function is not a qualified receiver. Keep values in
        // the lookup so properties still shadow imported classifiers.
        let allCandidateIDs: [SymbolID] = if isQualifier {
            ctx.scope.lookup(name, matching: { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else { return false }
                return symbol.kind != .function && symbol.kind != .constructor
            })
        } else {
            ctx.cachedScopeLookup(name)
        }
        // @DslMarker restriction: filter out candidates from outer receivers
        // that share a DslMarker annotation with the current implicit receiver.
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, initialInvisibleSyms) = ctx.filterByVisibility(dslFilteredIDs)
        var invisibleSyms = initialInvisibleSyms
        var candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        if candidates.isEmpty {
            let nominalFallbackIDs = sema.symbols.lookupByShortName(name).filter { symbolID in
                guard let symbol = sema.symbols.symbol(symbolID) else {
                    return false
                }
                switch symbol.kind {
                case .object, .class, .interface, .enumClass, .annotationClass, .typeAlias:
                    return true
                default:
                    return false
                }
            }
            let (visibleFallbackIDs, invisibleFallbackSyms) = ctx.filterByVisibility(nominalFallbackIDs)
            if !visibleFallbackIDs.isEmpty {
                candidates = visibleFallbackIDs.compactMap { ctx.cachedSymbol($0) }
            } else if invisibleSyms.isEmpty, !invisibleFallbackSyms.isEmpty {
                invisibleSyms = invisibleFallbackSyms
            }
        }

        // Implicit receiver member lookup walks the whole receiver tower
        // (extension receiver, enclosing lambda receivers, `this@Owner`
        // dispatch receivers, enclosing class) — a member extension body's
        // `this` is the extension receiver, but the dispatch owner's members,
        // inherited ones included, still resolve unqualified.
        let implicitReceiverLookupTypes = ctx.implicitReceiverMemberLookupTypes()
        if !implicitReceiverLookupTypes.isEmpty {
            var memberType: TypeID?
            for (index, receiverType) in implicitReceiverLookupTypes.enumerated() {
                memberType = resolveImplicitReceiverMember(
                    id: id,
                    name: name,
                    receiverType: receiverType,
                    ctx: ctx,
                    sema: sema,
                    interner: interner,
                    nameRange: nameRange,
                    emitDiagnosticOnFailure: index == implicitReceiverLookupTypes.count - 1
                        && candidates.isEmpty && invisibleSyms.isEmpty && dslBlockedIDs.isEmpty
                )
                if memberType != nil {
                    break
                }
            }
            if let memberType, memberType != sema.types.errorType {
                return memberType
            }
            if candidates.isEmpty, memberType == sema.types.errorType {
                return sema.types.errorType
            }
        }
        if candidates.isEmpty, !dslBlockedIDs.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-DSLMARKER",
                "'@DslMarker' implicit access to '\(interner.resolve(name))' from outer receiver is restricted. Use explicit receiver.",
                range: nameRange
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let receiverType = ctx.implicitReceiverType {
            candidates.removeAll { candidate in
                guard let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: candidate.id) else {
                    return false
                }
                return !sema.types.isSubtype(
                    sema.types.makeNonNullable(receiverType),
                    sema.types.makeNonNullable(declaredReceiver)
                )
            }
        }
        if candidates.isEmpty {
            var implicitMemberResult: (symbol: SymbolID, type: TypeID)?
            for receiverType in implicitReceiverLookupTypes {
                if let result = driver.helpers.lookupMemberProperty(
                    named: name,
                    receiverType: sema.types.makeNonNullable(receiverType),
                    sema: sema
                ) {
                    implicitMemberResult = result
                    break
                }
            }
            if let result = implicitMemberResult {
                sema.bindings.markImplicitReceiverMember(id, name: name)
                sema.bindings.bindIdentifier(id, symbol: result.symbol)
                driver.helpers.checkDeprecation(
                    for: result.symbol,
                    sema: sema,
                    interner: interner,
                    range: nameRange,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                driver.helpers.checkOptIn(
                    for: result.symbol,
                    ctx: ctx,
                    range: nameRange,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                sema.bindings.bindExprType(id, type: result.type)
                return result.type
            } else if let firstInvisible = invisibleSyms.first {
                driver.helpers.emitVisibilityError(for: firstInvisible, name: interner.resolve(name), range: nameRange, diagnostics: ctx.semaCtx.diagnostics)
            } else if name == knownNames.field {
                // Kotlin's `field` identifier is only valid inside property
                // getter/setter bodies where it refers to the backing field.
                // Emit a targeted diagnostic instead of the generic
                // "Unresolved reference" error.
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-FIELD",
                    "'field' can only be used inside a property getter or setter body.",
                    range: nameRange
                )
            } else {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0022",
                    "Unresolved reference '\(interner.resolve(name))'.",
                    range: nameRange
                )
            }
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let preferredCandidate = candidates.first(where: { symbol in
            switch symbol.kind {
            case .property, .field, .backingField, .object, .class, .interface, .enumClass:
                true
            default:
                false
            }
        }) ?? candidates.first
        if let preferredCandidate {
            sema.bindings.bindIdentifier(id, symbol: preferredCandidate.id)
            if ctx.implicitReceiverType != nil,
               sema.symbols.extensionPropertyReceiverType(for: preferredCandidate.id) != nil
            {
                sema.bindings.markImplicitReceiverMember(id, name: name)
            }
            // ANNO-001: Check for @Deprecated annotation on the resolved symbol.
            driver.helpers.checkDeprecation(
                for: preferredCandidate.id,
                sema: sema,
                interner: interner,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: preferredCandidate.id,
                ctx: ctx,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            // DEBT-SEMA-003: a property's initializer referencing the property's
            // own symbol reads it before it has ever been assigned a value.
            if let initializingPropertySymbol = ctx.initializingPropertySymbol,
               preferredCandidate.id == initializingPropertySymbol
            {
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: nameRange
                )
            }
        }
        let resolvedType = preferredCandidate.flatMap {
            resolveTypeForCandidate($0, sema: sema)
        } ?? sema.types.anyType
        // Propagate compile-time constant value for `const val` references
        // so downstream passes can fold without re-querying the symbol table.
        if let preferredCandidate, preferredCandidate.flags.contains(.constValue),
           let constKind = sema.symbols.constValueExprKind(for: preferredCandidate.id)
        {
            sema.bindings.bindConstExprValue(id, value: constKind)
        }
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    private func resolveImplicitReceiverMember(
        id: ExprID,
        name: InternedString,
        receiverType: TypeID,
        ctx: TypeInferenceContext,
        sema: SemaModule,
        interner: StringInterner,
        nameRange: SourceRange?,
        emitDiagnosticOnFailure: Bool = true
    ) -> TypeID? {
        // STDLIB-004: Inside receiver lambdas (run/apply/with), bare name
        // references resolve as properties on the implicit receiver (this).
        let knownNames = KnownCompilerNames(interner: interner)
        let resolvedName = interner.resolve(name)
        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        var implicitMemberType: TypeID?
        if sema.types.isSubtype(nonNullReceiver, sema.types.stringType), resolvedName == "length" {
            implicitMemberType = sema.types.intType
        }
        if nonNullReceiver == sema.types.charType, resolvedName == "code" {
            implicitMemberType = sema.types.intType
        }
        if implicitMemberType == nil, name == knownNames.size || name == knownNames.isEmpty,
           let (_, symbol) = resolveClassTypeSymbol(nonNullReceiver, sema: sema),
           knownNames.collectionKind(of: symbol) != nil
        {
            implicitMemberType = name == knownNames.size
                ? sema.types.intType
                : sema.types.make(.primitive(.boolean, .nonNull))
        }
        if implicitMemberType == nil,
           let result = driver.helpers.lookupMemberProperty(named: name, receiverType: nonNullReceiver, sema: sema)
        {
            sema.bindings.markImplicitReceiverMember(id, name: name)
            sema.bindings.bindIdentifier(id, symbol: result.symbol)
            driver.helpers.checkDeprecation(
                for: result.symbol, sema: sema, interner: interner,
                range: nameRange, diagnostics: ctx.semaCtx.diagnostics
            )
            driver.helpers.checkOptIn(
                for: result.symbol,
                ctx: ctx,
                range: nameRange,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.bindExprType(id, type: result.type)
            return result.type
        }
        if let memberType = implicitMemberType {
            sema.bindings.markImplicitReceiverMember(id, name: name)
            sema.bindings.bindExprType(id, type: memberType)
            return memberType
        }
        if emitDiagnosticOnFailure {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(resolvedName)'.",
                range: nameRange
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        return nil
    }

    private func resolveTypeForCandidate(_ symbol: SemanticSymbol, sema: SemaModule) -> TypeID? {
        if let signature = sema.symbols.functionSignature(for: symbol.id) {
            return signature.returnType
        }
        if symbol.kind == .property || symbol.kind == .field {
            return sema.symbols.propertyType(for: symbol.id)
        }
        // Objects are singletons – always resolve to their nominal type so
        // that `ObjectName.member()` works.
        if symbol.kind == .object {
            // Unit keeps its builtin value representation while retaining a
            // source-backed object symbol for member dispatch.
            if symbol.id == sema.types.unitClassSymbol {
                return sema.types.unitType
            }
            if let objectType = sema.symbols.propertyType(for: symbol.id) {
                return objectType
            }
            return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
        }
        // For class/interface/enum symbols, only resolve to nominal type when
        // they have a companion object so that `ClassName.companionMember()`
        // can resolve.  Without a companion, keep the previous anyType
        // fallback so that `ClassName.instanceMethod()` correctly errors.
        if symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass,
           sema.symbols.companionObjectSymbol(for: symbol.id) != nil
        {
            return sema.types.make(.classType(ClassType(classSymbol: symbol.id, args: [], nullability: .nonNull)))
        }
        return nil
    }

    private func describe(_ type: TypeID, ctx: TypeInferenceContext) -> String {
        ctx.sema.types.displayName(of: type, symbols: ctx.sema.symbols, interner: ctx.interner)
    }

    /// Whether an explicit lambda parameter annotation agrees with the parameter
    /// type the expected type declares. Type parameters the expected type leaves
    /// unsubstituted carry no information, so annotations always win there.
    /// Otherwise only widening is allowed (function types are contravariant in
    /// their parameters): `(String) -> Int = { s: Any -> ... }` is fine, while
    /// `(Any) -> Int = { s: String -> ... }` is a mismatch.
    ///
    /// `expectedTypeIsSourceDeclared` tells the two kinds of `Any` apart: an
    /// `Any` written in source constrains the annotation, while an `Any` the
    /// compiler synthesized for a call whose type variable stayed unsolved
    /// (`Grouping<K, E>`'s accumulator) carries no information.
    func lambdaAnnotationIsCompatible(
        annotated: TypeID,
        declared: TypeID,
        expectedTypeIsSourceDeclared: Bool,
        sema: SemaModule
    ) -> Bool {
        if annotated == declared || declared == sema.types.errorType || annotated == sema.types.errorType {
            return true
        }
        if typeMentionsTypeParameter(declared, sema: sema) {
            return true
        }
        if !expectedTypeIsSourceDeclared, case .any = sema.types.kind(of: declared) {
            return true
        }
        return sema.types.isSubtype(declared, annotated)
    }

    private func typeMentionsTypeParameter(_ type: TypeID, sema: SemaModule) -> Bool {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case .typeParam:
            return true
        case let .classType(classType):
            return classType.args.contains { arg in
                switch arg {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    return typeMentionsTypeParameter(inner, sema: sema)
                case .star:
                    return false
                }
            }
        case let .functionType(functionType):
            return functionType.params.contains { typeMentionsTypeParameter($0, sema: sema) }
                || typeMentionsTypeParameter(functionType.returnType, sema: sema)
                || (functionType.receiver.map { typeMentionsTypeParameter($0, sema: sema) } ?? false)
        case let .intersection(members):
            return members.contains { typeMentionsTypeParameter($0, sema: sema) }
        default:
            return false
        }
    }

    private func typeParameterSymbols(in type: TypeID, sema: SemaModule) -> Set<SymbolID> {
        switch sema.types.kind(of: sema.types.makeNonNullable(type)) {
        case let .typeParam(typeParam):
            return [typeParam.symbol]
        case let .classType(classType):
            return classType.args.reduce(into: Set<SymbolID>()) { symbols, argument in
                switch argument {
                case let .invariant(inner), let .out(inner), let .in(inner):
                    symbols.formUnion(typeParameterSymbols(in: inner, sema: sema))
                case .star:
                    break
                }
            }
        case let .functionType(functionType):
            var symbols = Set<SymbolID>()
            for receiver in functionType.contextReceivers {
                symbols.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            if let receiver = functionType.receiver {
                symbols.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            for parameter in functionType.params {
                symbols.formUnion(typeParameterSymbols(in: parameter, sema: sema))
            }
            symbols.formUnion(typeParameterSymbols(in: functionType.returnType, sema: sema))
            return symbols
        case let .kClassType(kClassType):
            return typeParameterSymbols(in: kClassType.argument, sema: sema)
        case let .intersection(members):
            return members.reduce(into: Set<SymbolID>()) { symbols, member in
                symbols.formUnion(typeParameterSymbols(in: member, sema: sema))
            }
        default:
            return []
        }
    }

    /// Resolves the explicit parameter type annotations recorded for a lambda
    /// literal (`{ a: Int, b: String -> ... }`). Returns nil when the lambda has
    /// no annotations or the recorded arity does not match the parameter list.
    func resolveLambdaParamAnnotations(
        _ id: ExprID,
        ctx: TypeInferenceContext,
        paramCount: Int
    ) -> [TypeID?]? {
        let sema = ctx.sema
        guard let typeRefs = ctx.ast.arena.lambdaParamTypeRefs(for: id),
              typeRefs.count == paramCount
        else {
            return nil
        }
        var resolved: [TypeID?] = []
        resolved.reserveCapacity(typeRefs.count)
        for typeRef in typeRefs {
            guard let typeRef else {
                resolved.append(nil)
                continue
            }
            let type = driver.helpers.resolveTypeRef(
                typeRef,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope,
                inferenceContext: ctx
            )
            resolved.append(type == sema.types.errorType ? nil : type)
        }
        return resolved.contains(where: { $0 != nil }) ? resolved : nil
    }

    func inferLambdaLiteralExpr(
        _ id: ExprID,
        params: [InternedString],
        body: ExprID,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema

        let label: InternedString? = if case let .lambdaLiteral(_, _, lbl, _) = ast.arena.expr(id) { lbl } else { nil }
        // SAM conversion: when the expected type is a functional interface,
        // extract the SAM method's function type so the lambda's parameters
        // and return type can be inferred from it.
        let samConversion: Bool
        let expectedFunctionType: FunctionType?
        if let expectedType, case let .functionType(functionType) = sema.types.kind(of: expectedType) {
            expectedFunctionType = functionType
            samConversion = false
        } else if let expectedType, let functionType = sema.types.nominalFunctionType(for: expectedType) {
            expectedFunctionType = functionType
            samConversion = false
            sema.bindings.bindNominalFunctionExpectedType(id, type: expectedType)
        } else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
            expectedFunctionType = samFT
            samConversion = true
        } else {
            expectedFunctionType = nil
            samConversion = false
        }

        var lambdaLocals = locals
        // Outer receiver `this` symbols are reachable inside the lambda even
        // though the enclosing member's `this` shadows them in `locals` — the
        // enclosing context (e.g. an object literal) captured them, so the
        // lambda can capture them through the same chain.
        let outerSymbols = Set(locals.values.map(\.symbol) + ctx.implicitReceiverStack.map(\.symbol))
            .union(ctx.outerReceiverTypes.compactMap(\.symbol))
        let inferredImplicitItType = params.isEmpty
            ? inferItParameterType(ctx: ctx, id: id, sema: sema)
            : nil

        // Implicit `it` parameter for no-arrow lambdas with single expected param.
        // Enhanced to support complex type inference contexts and generic types.
        let effectiveParams: [InternedString] = if params.isEmpty {
            // Check for expected function type first
            if let expectedFunctionType, expectedFunctionType.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            // Check for SAM conversion with single parameter method
            else if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
                    samFT.params.count == 1 {
                [ctx.interner.intern("it")]
            }
            // Check for common HOF patterns (map, filter, etc.) through context
            else if inferredImplicitItType != nil {
                [ctx.interner.intern("it")]
            } else {
                params
            }
        } else {
            params
        }

        // Parameter types the expected type actually declares, as opposed to the
        // `Any` fallback below; only these can contradict an explicit annotation.
        let declaredParameterTypes: [TypeID]? = {
            if let expectedFunctionType, expectedFunctionType.params.count == effectiveParams.count {
                return expectedFunctionType.params
            }
            if let expectedType, let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema),
               samFT.params.count == effectiveParams.count
            {
                return samFT.params
            }
            return nil
        }()
        let expectedParameterTypes: [TypeID] = if let declaredParameterTypes {
            declaredParameterTypes
        } else if effectiveParams.count == 1 && effectiveParams.contains(ctx.interner.intern("it")) {
            // For implicit `it` parameter, try to infer type from context
            inferredImplicitItType.map { [$0] }
                ?? Array(repeating: sema.types.anyType, count: effectiveParams.count)
        } else {
            Array(repeating: sema.types.anyType, count: effectiveParams.count)
        }
        // Explicit `{ a: Int -> ... }` annotations win over the expected type's
        // parameter types, which may be unsubstituted type parameters when the
        // expected type is a raw functional interface (BUG-046). An annotation
        // that contradicts a concrete expected parameter type is an error.
        let annotatedParameterTypes = resolveLambdaParamAnnotations(id, ctx: ctx, paramCount: effectiveParams.count)
        let expectedTypeIsSourceDeclared = sema.bindings.hasSourceDeclaredExpectedType(id)
        let parameterTypes: [TypeID] = effectiveParams.indices.map { offset in
            let fallback = offset < expectedParameterTypes.count ? expectedParameterTypes[offset] : sema.types.anyType
            guard let annotated = annotatedParameterTypes?[offset] else {
                return fallback
            }
            guard let declared = declaredParameterTypes?[offset] else {
                return annotated
            }
            if lambdaAnnotationIsCompatible(
                annotated: annotated,
                declared: declared,
                expectedTypeIsSourceDeclared: expectedTypeIsSourceDeclared,
                sema: sema
            ) {
                return annotated
            }
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0025",
                "Lambda parameter '\(ctx.interner.resolve(effectiveParams[offset]))' is declared as "
                    + "'\(describe(annotated, ctx: ctx))' but '\(describe(declared, ctx: ctx))' is expected.",
                range: ast.arena.exprRange(id)
            )
            return declared
        }
        for (offset, param) in effectiveParams.enumerated() {
            let syntheticSymbol = SymbolID(rawValue: Int32(clamping: Int64(-1_000_000) - Int64(id.rawValue) * 256 - Int64(offset)))
            let parameterType = parameterTypes[offset]
            // Preserve the declaration type for checks that must ignore smart casts,
            // just as for local function parameters.
            sema.symbols.setPropertyType(parameterType, for: syntheticSymbol)
            lambdaLocals[param] = (
                type: parameterType,
                symbol: syntheticSymbol,
                isMutable: false,
                isInitialized: true
            )
        }

        var bodyCtx: TypeInferenceContext = if let label {
            ctx.withLambdaLabel(label)
        } else {
            ctx
        }
        bodyCtx = bodyCtx.enteringLambdaBody(id)
        if let receiverType = ctx.implicitReceiverType,
           let receiverSymbol = locals[ctx.interner.intern("this")]?.symbol,
           bodyCtx.implicitReceiverStack.last?.symbol != receiverSymbol
        {
            bodyCtx.implicitReceiverStack.append((receiverType, receiverSymbol))
        }
        // When the expected function type has a receiver (e.g. StringBuilder.() -> Unit),
        // set the implicit receiver so that unqualified member calls resolve correctly.
        if let receiverType = expectedFunctionType?.receiver
            ?? sema.bindings.coroutineScopeLambdaReceiverTypes[id]
        {
            bodyCtx = bodyCtx.with(implicitReceiverType: receiverType)
            // The lambda's own receiver is its `this`: shadow the enclosing
            // function's receiver in `locals` (which `inferThisRefExpr` reads
            // first) and address it through a per-lambda symbol so that
            // `this@callee` from a nested lambda can capture it.
            let receiverSymbol = SyntheticSymbolScheme.lambdaReceiverSymbol(for: id)
            bodyCtx.implicitReceiverStack.append((receiverType, receiverSymbol))
            lambdaLocals[ctx.interner.intern("this")] = (
                type: receiverType,
                symbol: receiverSymbol,
                isMutable: false,
                isInitialized: true
            )
            if let label {
                bodyCtx = bodyCtx.withOuterReceiver(label: label, type: receiverType, symbol: receiverSymbol)
            }
        }
        if let expectedFunctionType, !expectedFunctionType.contextReceivers.isEmpty {
            bodyCtx = bodyCtx.with(
                contextReceiverTypes: ctx.contextReceiverTypes + expectedFunctionType.contextReceivers
            )
        }
        let expectedReturnHasUnresolvedOutputTypeParameter: Bool = {
            guard let expectedFunctionType else {
                return false
            }
            let returnTypeParameters = typeParameterSymbols(in: expectedFunctionType.returnType, sema: sema)
            guard !returnTypeParameters.isEmpty else {
                return false
            }
            var inputTypeParameters = Set<SymbolID>()
            for receiver in expectedFunctionType.contextReceivers {
                inputTypeParameters.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            if let receiver = expectedFunctionType.receiver {
                inputTypeParameters.formUnion(typeParameterSymbols(in: receiver, sema: sema))
            }
            for parameter in expectedFunctionType.params {
                inputTypeParameters.formUnion(typeParameterSymbols(in: parameter, sema: sema))
            }
            return !returnTypeParameters.subtracting(inputTypeParameters).isEmpty
        }()
        // Kotlin discards a Unit-expected lambda body's value rather than requiring
        // it to actually type as Unit (e.g. `repeat(3) { i -> someIntCall(i) }`).
        // Passing Unit down as the body's expectedType would incorrectly propagate
        // into the body's own call resolution -- e.g. rejecting `addOne(i): Int` as
        // "no viable overload" because Int isn't a subtype of the pushed-down Unit.
        // Only push the expected return type down when it isn't Unit. An unresolved
        // type parameter (the `T` of `fun <T> f(action: () -> T): T`) is treated the
        // same way: it cannot constrain the body's own resolution, and pushing it
        // down makes a Unit-valued body (e.g. `{ println() }`) fail to type-check.
        // The same applies when the unresolved output parameter is nested inside
        // a contextual return type such as `List<R>`. It is free at this call site
        // when it does not occur in the lambda's receiver or input parameters;
        // the concrete body result must infer it instead of being checked against
        // an outer placeholder.
        // Leaving it out lets the body infer its natural type so the caller can solve
        // the type variable from it.
        let bodyExpectedType: TypeID? = {
            guard let expectedReturnType = expectedFunctionType?.returnType,
                  expectedReturnType != sema.types.unitType else {
                return nil
            }
            if case .typeParam = sema.types.kind(of: expectedReturnType) {
                return nil
            }
            if expectedReturnHasUnresolvedOutputTypeParameter {
                return nil
            }
            return expectedReturnType
        }()
        let returnScope = LambdaReturnInferenceScope(
            exprID: id,
            label: label,
            expectedReturnType: expectedFunctionType?.returnType == sema.types.unitType
                ? sema.types.unitType : bodyExpectedType
        )
        bodyCtx.lambdaReturnScopes.append(returnScope)
        let fallthroughType = driver.inferExpr(
            body,
            ctx: bodyCtx,
            locals: &lambdaLocals,
            expectedType: bodyExpectedType,
            isStatementContext: expectedFunctionType?.returnType == sema.types.unitType
        )
        let inferredBodyType = sema.types.lub(
            [fallthroughType] + returnScope.returnValueTypes.sorted { $0.key.rawValue < $1.key.rawValue }.map(\.value)
        )
        // STDLIB-592 definite assignment: record which outer-scope locals this
        // lambda body unconditionally initializes, mirroring the blockExpr merge
        // in ExprTypeChecker.swift. `locals` itself is never mutated here -- the
        // lambda isn't known to run at this point -- but a caller whose contract
        // guarantees EXACTLY_ONCE/AT_LEAST_ONCE invocation (applyContractEffects)
        // can later fold this back into its own definite-assignment state.
        var callsInPlaceInitializedSymbols: [SymbolID] = []
        for (name, outerLocal) in locals where !outerLocal.isInitialized {
            if let lambdaLocal = lambdaLocals[name],
               lambdaLocal.symbol == outerLocal.symbol,
               lambdaLocal.isInitialized
            {
                callsInPlaceInitializedSymbols.append(outerLocal.symbol)
            }
        }
        if !callsInPlaceInitializedSymbols.isEmpty {
            sema.bindings.bindContractCallsInPlaceInitializedSymbols(id, symbols: callsInPlaceInitializedSymbols)
        }
        let captures = driver.captureAnalyzer.collectCapturedOuterSymbols(
            in: body,
            ast: ast,
            sema: sema,
            outerSymbols: outerSymbols
        )
        sema.bindings.bindCaptureSymbols(id, symbols: captures)

        // SAM conversion: bind the lambda to the interface type, but also
        // store the underlying function type so KIR lowering can generate
        // the correct callable.
        if samConversion, let expectedType, let expectedFunctionType {
            driver.emitSubtypeConstraint(
                left: inferredBodyType,
                right: expectedFunctionType.returnType,
                range: ast.arena.exprRange(body),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
            sema.bindings.markSamConversion(id)
            let underlyingFuncType = sema.types.make(.functionType(expectedFunctionType))
            sema.bindings.bindSamUnderlyingFunctionType(id, type: underlyingFuncType)
            sema.bindings.bindExprType(id, type: expectedType)
            return expectedType
        }

        if let expectedFunctionType {
            if let session = ctx.builderInference,
               expectedFunctionType.returnType != sema.types.unitType,
               session.mentionsVariable(expectedFunctionType.returnType, types: sema.types)
            {
                session.constraints.append(contentsOf: ctx.resolver.decomposeSubtypeConstraint(
                    subtype: inferredBodyType,
                    supertype: expectedFunctionType.returnType,
                    typeVarBySymbol: session.typeVarBySymbol,
                    typeSystem: sema.types,
                    blameRange: ast.arena.exprRange(body)
                ))
                let functionType = sema.types.make(.functionType(expectedFunctionType))
                sema.bindings.bindExprType(id, type: functionType)
                return functionType
            }
            // Enhanced return type inference with Unit optimization
            let optimizedReturnType = inferOptimizedReturnType(
                inferredBodyType: inferredBodyType,
                expectedReturnType: expectedFunctionType.returnType,
                sema: sema
            )

            // Skip the local subtype constraint when the expected return is Unit
            // (Kotlin allows any body type) or when it is a generic type variable.
            // For Unit there is nothing to constrain. For a type variable the
            // local solver cannot bind it; the concrete inferred function type
            // returned below lets the call resolver infer it instead.
            let expectedReturnIsTypeParam: Bool = {
                guard case .typeParam = sema.types.kind(of: expectedFunctionType.returnType) else {
                    return false
                }
                return true
            }()
            // A bounded type parameter (`fun <R : Any> f(g: () -> R)`) cannot be
            // constrained locally either — `Int <: R` is never satisfiable while
            // `R` is still a placeholder, and the upper bound is verified by the
            // overload resolver once `R` is inferred (`checkTypeParameterBounds`).
            let shouldSkipSubtypeConstraint =
                expectedFunctionType.returnType == sema.types.unitType
                || expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
            if !shouldSkipSubtypeConstraint {
                driver.emitSubtypeConstraint(
                    left: optimizedReturnType,
                    right: expectedFunctionType.returnType,
                    range: ast.arena.exprRange(body),
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
            }
            // When the expected return type is an unresolved type parameter,
            // returning `expectedType` verbatim leaks that type variable back
            // out as the lambda's own type. The overload resolver then
            // decomposes it against the same signature's parameter type and
            // produces a self-referential `T <: T` bound instead of a real
            // constraint derived from the body's actual type (e.g. `lazy { 1 }`
            // or `box.run2 { myValue }` fails to infer `R`). Substitute the
            // concrete, inferred return type in those cases so the caller can
            // solve the type parameter from it.
            let shouldReturnResolvedFunctionType = expectedReturnIsTypeParam
                || expectedReturnHasUnresolvedOutputTypeParameter
            let resultType: TypeID = if shouldReturnResolvedFunctionType {
                sema.types.make(.functionType(FunctionType(
                    contextReceivers: expectedFunctionType.contextReceivers,
                    receiver: expectedFunctionType.receiver,
                    params: parameterTypes,
                    returnType: optimizedReturnType,
                    isSuspend: expectedFunctionType.isSuspend,
                    nullability: expectedFunctionType.nullability,
                    throws: expectedFunctionType.throws
                )))
            } else {
                sema.types.make(.functionType(expectedFunctionType))
            }
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        let inferredFunctionType = sema.types.make(.functionType(FunctionType(
            params: parameterTypes,
            returnType: inferredBodyType,
            isSuspend: false,
            nullability: .nonNull
        )))
        sema.bindings.bindExprType(id, type: inferredFunctionType)
        return inferredFunctionType
    }

    /// Visible `<init>` symbols of a concrete class, or `nil` for an abstract
    /// class or one without constructors. Constructors live under the class's
    /// own FQ name with the reserved `<init>` short name (HeaderHelpers.swift).
    private func visibleConstructorCandidates(
        of classSymbol: SemanticSymbol,
        ctx: TypeInferenceContext
    ) -> [SymbolID]? {
        guard !classSymbol.flags.contains(.abstractType) else {
            return nil
        }
        let ctorSymbols = ctx.sema.symbols.lookupAll(
            fqName: classSymbol.fqName + [ctx.interner.intern("<init>")]
        )
        guard !ctorSymbols.isEmpty else {
            return nil
        }
        return ctx.filterByVisibility(ctorSymbols).0
    }

    func inferCallableRefExpr(
        _ id: ExprID,
        receiver: ExprID?,
        member: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let outerSymbols = Set(locals.values.map(\.symbol))

        if let expectedType, sema.types.nominalFunctionType(for: expectedType) != nil {
            sema.bindings.bindNominalFunctionExpectedType(id, type: expectedType)
        }

        // ── T::class  — reified type-parameter class reference ──────────
        if member == KnownCompilerNames(interner: interner).className,
           let receiverTypeRef = ast.arena.callableRefReceiverTypeRef(for: id)
        {
            return inferExplicitArrayClassRef(
                id, receiverTypeRef: receiverTypeRef, range: range, ctx: ctx
            )
        }

        if member == KnownCompilerNames(interner: interner).className,
           let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           locals[receiverName] == nil
        {
            if let result = inferClassRefExpr(
                id, receiver: receiver, receiverName: receiverName,
                range: range, ctx: ctx, locals: &locals
            ) {
                return result
            }
        }

        if member == KnownCompilerNames(interner: interner).className,
           let receiver
        {
            return inferExprReceiverClassRef(
                id, receiver: receiver, range: range, ctx: ctx, locals: &locals
            )
        }

        // ── REFL-PRIMOP: Int::plus / Int::times — primitive operator with
        // no backing symbol ───────────────────────────────────────────────
        // `plus`/`times` on a primitive numeric receiver are a table-driven
        // type-inference special case (tryInferRegularMemberCallPrimitiveSpecials),
        // not a real member declaration -- ordinary candidate lookup below
        // (`.function || .constructor` on `member`) always comes up empty for
        // them. Handled first and unconditionally: unlike `Type::member`, a
        // primitive receiver name never introduces real function/constructor
        // candidates that this could shadow.
        if let receiver,
           ast.arena.callableRefReceiverTypeRef(for: id) == nil,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           locals[receiverName] == nil,
           let result = inferPrimitiveOperatorCallableRefExpr(
               id, receiverName: receiverName, member: member,
               expectedType: expectedType, range: range, ctx: ctx
           )
        {
            return result
        }

        // ── REFL-003: Type::member — unbound callable reference ─────────
        // When the receiver is a name that refers to a class/interface/enum
        // (not an instance variable), treat it as an unbound member reference.
        // The resulting function type includes the receiver type as the
        // first parameter: `Type::method` becomes `(Type) -> ReturnType`.
        var unboundClassType: TypeID?
        if let receiverTypeRef = ast.arena.callableRefReceiverTypeRef(for: id) {
            unboundClassType = driver.helpers.resolveTypeRef(
                receiverTypeRef,
                ast: ast,
                sema: sema,
                interner: interner,
                scope: ctx.scope,
                diagnostics: ctx.semaCtx.diagnostics,
                inferenceContext: ctx,
                usageRange: range
            )
            if let unboundClassType {
                let argumentCounts: (expected: Int, actual: Int)?
                if case let .classType(owner) = sema.types.kind(of: unboundClassType) {
                    argumentCounts = (sema.types.nominalTypeParameterSymbols(for: owner.classSymbol).count, owner.args.count)
                } else if case let .named(path, arguments, _) = ast.arena.typeRef(receiverTypeRef),
                          let name = path.last,
                          driver.helpers.resolveBuiltinTypeName(name, types: sema.types, interner: interner) != nil
                {
                    argumentCounts = (0, arguments.count)
                } else {
                    argumentCounts = nil
                }
                if let argumentCounts, argumentCounts.expected != argumentCounts.actual {
                    ctx.semaCtx.diagnostics.error(
                        "KSWIFTK-SEMA-0062",
                        "Type argument count mismatch: expected \(argumentCounts.expected) but got \(argumentCounts.actual).",
                        range: range
                    )
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
            }
        } else if let receiver,
           case let .nameRef(receiverName, _) = ast.arena.expr(receiver),
           locals[receiverName] == nil
        {
            // A local with this name is a bound receiver, so only unresolved
            // names can introduce an unbound type reference.
            let allCandidateIDs = ctx.cachedScopeLookup(receiverName)
            for candidateID in allCandidateIDs {
                guard let sym = ctx.cachedSymbol(candidateID),
                      sym.kind == .class || sym.kind == .interface
                      || sym.kind == .enumClass
                else { continue }
                // Primitive class names are represented by dedicated primitive
                // TypeIDs at expression sites. Keep that representation here so
                // member lookup also probes package-level extensions such as
                // `Char::titlecase` in kotlin.text.
                if let primitive = driver.builtinTypeNamesCache.primitiveType(for: sym.name) {
                    unboundClassType = sema.types.make(.primitive(primitive, .nonNull))
                } else {
                    unboundClassType = sema.types.make(
                        .classType(ClassType(classSymbol: sym.id, args: [], nullability: .nonNull))
                    )
                }
                break
            }

            if unboundClassType == nil,
               let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName)
            {
                // Builtin primitive classes may not be present in the lexical scope,
                // but their callable references still use the primitive receiver path.
                unboundClassType = sema.types.make(.primitive(primitive, .nonNull))
            }
        }

        let receiverType: TypeID?
        if let receiver, let unboundClassType {
            sema.bindings.bindExprType(receiver, type: unboundClassType)
            if let (_, symbol) = resolveClassTypeSymbol(unboundClassType, sema: sema) {
                sema.bindings.bindIdentifier(receiver, symbol: symbol.id)
            }
            receiverType = unboundClassType
        } else if let receiver {
            receiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        } else {
            receiverType = nil
        }

        // For unbound type references, use the resolved class type for
        // member lookup instead of the expression-inferred type (which
        // may degrade to Any for classes without companion objects).
        let effectiveReceiverType = unboundClassType ?? receiverType

        var candidates: [SymbolID] = []
        // Resolve receiver members before the bare-property shortcut below:
        // a package `val flush` must not hide `Writer.flush` for `::flush` in
        // implicit-receiver scope. Local declarations retain lexical priority.
        let hasLocalDeclaration = locals[member] != nil
        var implicitBoundReceiver: (type: TypeID, symbol: SymbolID)?
        var implicitPropertyCandidate: SymbolID?
        let implicitMemberCandidates: [SymbolID] = {
            guard receiver == nil, !hasLocalDeclaration
            else { return [] }
            var receivers = ctx.implicitReceiverStack
            if let type = ctx.implicitReceiverType,
               let symbol = locals[interner.intern("this")]?.symbol,
               receivers.last?.symbol != symbol
            {
                receivers.append((type, symbol))
            }
            var hiddenDslMarkers = Set<String>()
            for implicitReceiver in receivers.reversed() {
                let markers = ctx.collectDslMarkerAnnotations(for: implicitReceiver.type)
                let isHidden = !hiddenDslMarkers.isDisjoint(with: markers)
                hiddenDslMarkers.formUnion(markers)
                if isHidden { continue }
                let nonNullImplicitReceiver = sema.types.makeNonNullable(implicitReceiver.type)
                let members = driver.helpers.collectMemberFunctionCandidates(
                    named: member,
                    receiverType: nonNullImplicitReceiver,
                    sema: sema,
                    interner: interner
                ).filter { candidate in
                    // Kotlin rejects every `::` form for member-extensions
                    // ("member and an extension at the same time"), including
                    // the implicitly-bound `::name` form inside the owner.
                    !driver.helpers.declaresExtensionReceiver(
                        candidate,
                        sema: sema,
                        interner: interner
                    )
                }
                // A bare `::ext` inside a receiver scope is a *bound* reference
                // (`with("s") { ::ext }` means `this::ext`), so package-level
                // extensions whose declared receiver accepts the implicit
                // receiver are bound `() -> R` candidates as well — kotlinc
                // resolves `with("42") { ::toInt }` to `() -> Int`.
                let implicitExtensionCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    let owner = sema.symbols.parentSymbol(for: symbolID).flatMap { ctx.cachedSymbol($0) }
                    guard let symbol = ctx.cachedSymbol(symbolID),
                          symbol.kind == .function,
                          owner == nil || owner?.kind == .package
                              || Array(symbol.fqName.dropLast()) != owner?.fqName,
                          let signature = sema.symbols.functionSignature(for: symbolID),
                          let declaredReceiver = signature.receiverType,
                          driver.helpers.declaresExtensionReceiver(
                              symbolID,
                              sema: sema,
                              interner: interner
                          )
                    else { return false }
                    return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: nonNullImplicitReceiver,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                }
                // Members of the implicit receiver outrank same-named package
                // extensions, mirroring member-call resolution in Kotlin.
                let visibleMembers = ctx.filterByVisibility(members).0
                if !visibleMembers.isEmpty {
                    implicitBoundReceiver = implicitReceiver
                    return visibleMembers
                }
                let memberProperties: [SymbolID] = if let (_, owner) = resolveClassTypeSymbol(nonNullImplicitReceiver, sema: sema) {
                    sema.symbols.lookupAll(fqName: owner.fqName + [member]).filter { symbolID in
                        let kind = ctx.cachedSymbol(symbolID)?.kind
                        return (kind == .property || kind == .field)
                            && sema.symbols.extensionPropertyReceiverType(for: symbolID) == nil
                    }
                } else { [] }
                let extensionProperties = ctx.cachedScopeLookup(member).filter { symbolID in
                    let ownerKind = sema.symbols.parentSymbol(for: symbolID).flatMap { ctx.cachedSymbol($0)?.kind }
                    guard ctx.cachedSymbol(symbolID)?.kind == .property,
                          let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: symbolID),
                          ownerKind == nil || ownerKind == .package
                    else { return false }
                    return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                        callSiteReceiver: nonNullImplicitReceiver,
                        declaredReceiver: declaredReceiver,
                        sema: sema
                    )
                }
                if let property = ctx.filterByVisibility(memberProperties).0.first {
                    implicitBoundReceiver = implicitReceiver
                    implicitPropertyCandidate = property
                    return []
                }
                let visibleExtensions = ctx.filterByVisibility(implicitExtensionCandidates).0
                if !visibleExtensions.isEmpty {
                    implicitBoundReceiver = implicitReceiver
                    return visibleExtensions
                }
                if let property = ctx.filterByVisibility(extensionProperties).0.first {
                    implicitBoundReceiver = implicitReceiver
                    implicitPropertyCandidate = property
                    return []
                }
            }
            return []
        }()
        if let property = implicitPropertyCandidate, let implicitBoundReceiver {
            sema.bindings.markImplicitReceiverMember(id, name: member)
            sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: implicitBoundReceiver.symbol)
            return bindPropertyCallableRef(
                id,
                propertySymbol: property,
                ownerType: nil,
                isUnbound: false,
                expectedType: expectedType,
                sema: sema,
                interner: interner
            )
        }
        // REFL-CTOR: set when `candidates` were filled with constructor
        // symbols for a bare `::Foo` reference below. A constructor
        // signature's `receiverType` field carries the class type for the
        // constructor body's own implicit `this` (MemberHeaderCollection.swift),
        // not a real extension-style receiver -- `callableFunctionType` must
        // therefore treat it as already "bound" (excluded from the resulting
        // function type's parameter list) the same way a bound `obj::method`
        // reference is, or `(Int) -> Foo` would gain a spurious leading `Foo`
        // parameter.
        var isConstructorReference = false
        var isImplicitlyBoundMember = false
        if let effectiveReceiverType {
            let nonNullReceiver = sema.types.makeNonNullable(effectiveReceiverType)
            let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
                named: member,
                receiverType: nonNullReceiver,
                sema: sema,
                includeUnattachedPackageExtensions: true,
                interner: interner
            ).filter { candidate in
                // Member-extensions are never valid callable-reference
                // targets — `C::ext`, `c::ext`, and `this::ext` are all
                // rejected by kotlinc — while package-level extensions on
                // the receiver stay legal (`String::toInt`, `s::toInt`).
                !driver.helpers.declaresExtensionReceiver(
                    candidate,
                    sema: sema,
                    interner: interner
                )
            }
            if !memberCandidates.isEmpty {
                candidates = memberCandidates
            } else {
                // Property references use the same inheritance-aware lookup as
                // ordinary member reads (for example MutableList<Int>::size).
                if let property = driver.helpers.lookupMemberProperty(
                    named: member,
                    receiverType: nonNullReceiver,
                    sema: sema
                ), sema.symbols.extensionPropertyReceiverType(for: property.symbol) == nil {
                    return bindPropertyCallableRef(
                        id,
                        propertySymbol: property.symbol,
                        ownerType: unboundClassType != nil ? nonNullReceiver : nil,
                        isUnbound: unboundClassType != nil,
                        expectedType: expectedType,
                        sema: sema,
                        interner: interner
                    )
                }
                // REFL-EXTPROP: a package-level extension property (e.g. `val
                // String.length: Int` in Stdlib/kotlin/String.kt) is registered
                // under its *declaring package's* FQ name, not under its
                // receiver class's FQ name the way an extension *function*
                // gets an alias for (HeaderCollection.swift's `.propertyDecl`
                // branch never creates the member-FQ alias its `.funDecl`
                // sibling does at KSP-443) -- so the FQ-based lookup above
                // never finds `String::length`. Match it the same way
                // `resolveExtensionPropertyGetter` resolves a plain
                // `receiver.length` read: scan scope-visible `.property`
                // symbols for one whose recorded extension receiver type
                // accepts `nonNullReceiver`.
                if candidates.isEmpty {
                    let extensionPropertyCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                        guard let symbol = ctx.cachedSymbol(symbolID),
                              symbol.kind == .property,
                              let declaredReceiver = sema.symbols.extensionPropertyReceiverType(for: symbolID)
                        else {
                            return false
                        }
                        return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                            callSiteReceiver: nonNullReceiver,
                            declaredReceiver: declaredReceiver,
                            sema: sema
                        )
                    }
                    if let propertySymbol = extensionPropertyCandidates.first {
                        return bindPropertyCallableRef(
                            id,
                            propertySymbol: propertySymbol,
                            ownerType: unboundClassType != nil ? nonNullReceiver : nil,
                            isUnbound: unboundClassType != nil,
                            expectedType: expectedType,
                            sema: sema,
                            interner: interner
                        )
                    }
                }
                candidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    guard let symbol = ctx.cachedSymbol(symbolID),
                          symbol.kind == .function,
                          let signature = sema.symbols.functionSignature(for: symbolID),
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
                // `Outer::Nested` where `Nested` is a nested (non-inner) class
                // is a constructor reference `(Args...) -> Outer.Nested`. It
                // has no receiver parameter, so it is folded into the bound
                // side like the bare `::Foo` form. `inner` classes are left
                // out: their reference takes the outer instance as a
                // leading parameter, which this path does not model.
                if candidates.isEmpty,
                   unboundClassType != nil,
                   let (_, owner) = resolveClassTypeSymbol(nonNullReceiver, sema: sema)
                {
                    let nestedClass = sema.symbols.lookupAll(fqName: owner.fqName + [member])
                        .compactMap { ctx.cachedSymbol($0) }
                        .first { ($0.kind == .class || $0.kind == .enumClass) && !$0.flags.contains(.innerClass) }
                    if let nestedClass,
                       let ctorCandidates = visibleConstructorCandidates(of: nestedClass, ctx: ctx)
                    {
                        candidates = ctorCandidates
                        isConstructorReference = true
                    }
                }
            }
        } else {
            let propertyCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else {
                    return false
                }
                // A bare `::name` cannot reference an extension property —
                // kotlinc reports `unresolved reference`; only `Type::prop`
                // and `obj::prop` reach extension properties.
                return symbol.kind == .property
                    && sema.symbols.extensionPropertyReceiverType(for: symbolID) == nil
            }
            let packagePropertyShadowedByMember = propertyCandidates.first.map { propertySymbol in
                let ownerKind = sema.symbols.parentSymbol(for: propertySymbol)
                    .flatMap { sema.symbols.symbol($0)?.kind }
                return !implicitMemberCandidates.isEmpty && (ownerKind == .package || ownerKind == nil)
            } ?? false
            if let propertySymbol = propertyCandidates.first, !packagePropertyShadowedByMember {
                let propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.errorType
                let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
                // KSP-496/KSP-505: a bare `::member` reference to a member
                // property of the enclosing class or singleton is implicitly
                // bound to `this`. For `.class` owners the receiver is a
                // genuine instance captured by KIR lowering
                // (LambdaLowerer.isCaptureEligibleInstanceContainerSymbol).
                // For `.object` owners (companion objects, plain `object`s)
                // there is exactly one instance ever, stored in a
                // module-level global slot rather than a captured
                // per-instance field — so KIR lowering (see
                // LambdaLowerer+PropertyReferenceLowering.swift's
                // `ensurePropertyReferenceAccessor`) reads/writes that slot
                // directly and never needs a captured receiver at all.
                //
                // `.enumClass` stays excluded (kept on the pre-existing, safe
                // fallback), even though an *enum entry* is also a singleton:
                // a property declared directly in the enum class's own body
                // (e.g. a constructor-promoted `val`) is a genuine per-entry
                // *instance* field — each entry has its own value — not
                // shared global storage the way `.object` is. Confirmed by
                // testing: treating `.enumClass` the same as `.object` here
                // made `enum class E(val v: Int) { A(1), B(2) }`'s `::v`
                // read back `0` for every entry instead of each entry's own
                // value. A property declared inside one specific *entry's*
                // own body (`A { val x = 5 }`) might be a distinct, safely
                // includable case — its owner could plausibly be that
                // entry's own synthesized subclass rather than `.enumClass`
                // itself — but this could not be verified: referencing an
                // entry with a body at all (`EnumClass.ENTRY`) hits a
                // separate, pre-existing, unrelated bug (see
                // docs/diff-skip-inventory.md's `enum_edge_cases.kt` entry).
                // `.interface` stays excluded here too: interface-owned
                // properties have no storage of their own (always dispatched
                // through whichever class implements them), which this
                // bare-reference path does not handle yet.
                let ownerKind = sema.symbols.parentSymbol(for: propertySymbol)
                    .flatMap { sema.symbols.symbol($0)?.kind }
                let resultType: TypeID
                if let ownerKind, ownerKind != .class, ownerKind != .object {
                    resultType = propertyType
                } else {
                    let inferredType = kPropertyReferenceType(
                        ownerType: nil,
                        valueType: propertyType,
                        isMutable: isMutable,
                        sema: sema,
                        interner: interner
                    ) ?? propertyType
                    resultType = resolvedPropertyReferenceResultType(
                        expectedType: expectedType,
                        inferredType: inferredType,
                        sema: sema,
                        interner: interner
                    )
                }
                sema.bindings.bindIdentifier(id, symbol: propertySymbol)
                sema.bindings.bindCallableRefKind(id, kind: .propertyRef)
                markPropertyReferenceSamConversionIfNeeded(
                    id,
                    expectedType: expectedType,
                    resultType: resultType,
                    sema: sema
                )
                sema.bindings.bindExprType(id, type: resultType)
                return resultType
            }
            candidates = ctx.cachedScopeLookup(member).filter { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID) else {
                    return false
                }
                // A bare `::name` cannot reference an extension function —
                // kotlinc reports `unresolved reference`; only `Type::ext`,
                // `obj::ext`, and the implicit-receiver bound form (handled
                // via `implicitMemberCandidates`) reach extensions.
                return symbol.kind == .constructor
                    || (symbol.kind == .function
                        && !driver.helpers.declaresExtensionReceiver(
                            symbolID,
                            sema: sema,
                            interner: interner
                        ))
            }
            if candidates.isEmpty,
               let local = locals[member],
               let localSymbol = ctx.cachedSymbol(local.symbol),
               localSymbol.kind == .function,
               sema.symbols.functionSignature(for: local.symbol)?.receiverType == nil
            {
                candidates = [local.symbol]
            }
            // REFL-CTOR: a bare `::Foo` where `Foo` names a class/enum class
            // is a constructor reference `(Args...) -> Foo`. Constructors are
            // stored under the class's own FQ name with the reserved `<init>`
            // short name (HeaderHelpers.swift), not under `Foo` itself, so the
            // `.function || .constructor` scope lookup above never finds them
            // -- mirrors the KSP-CAP-006 class+ctor lookup CallTypeChecker.swift
            // uses for a direct call `Foo(...)`.
            if candidates.isEmpty {
                let classCandidates = ctx.cachedScopeLookup(member).filter { symbolID in
                    guard let symbol = ctx.cachedSymbol(symbolID) else { return false }
                    return symbol.kind == .class || symbol.kind == .enumClass
                }
                if let classSym = classCandidates.first,
                   let classSymbol = ctx.cachedSymbol(classSym),
                   let ctorCandidates = visibleConstructorCandidates(of: classSymbol, ctx: ctx)
                {
                    candidates = ctorCandidates
                    isConstructorReference = true
                }
            }
        }

        // Within a class or extension body, `::member` uses the active
        // implicit receiver before a same-named package function. Lexical
        // scope lookup does not walk inherited member scopes. A local
        // function still shadows the receiver's member.
        if !implicitMemberCandidates.isEmpty {
            candidates = implicitMemberCandidates
            isImplicitlyBoundMember = true
        }

        // A nested class constructor (`Outer::Nested`) is stored under
        // `Outer.Nested.<init>`, just as bare `::Nested` is under
        // `Nested.<init>`. Ordinary member lookup by the short name misses it.
        // Only a type receiver may introduce this fallback.
        if candidates.isEmpty,
           let unboundClassType,
           let (_, owner) = resolveClassTypeSymbol(unboundClassType, sema: sema)
        {
            let nestedClasses = sema.symbols.lookupAll(fqName: owner.fqName + [member])
            for nestedID in nestedClasses {
                let (visibleNested, _) = ctx.filterByVisibility([nestedID])
                guard let nested = ctx.cachedSymbol(nestedID),
                      (nested.kind == .class || nested.kind == .enumClass),
                      !nested.flags.contains(.abstractType),
                      !nested.flags.contains(.innerClass),
                      !visibleNested.isEmpty
                else { continue }
                let constructors = sema.symbols.lookupAll(
                    fqName: nested.fqName + [interner.intern("<init>")]
                )
                let (visible, _) = ctx.filterByVisibility(constructors)
                if !visible.isEmpty {
                    candidates = visible
                    isConstructorReference = true
                    break
                }
            }
        }

        // For unbound type references (Type::member), the receiver is not
        // bound — it becomes a parameter of the function type.  For bound
        // references (obj::member), the receiver is captured. A constructor
        // reference has no receiver at all; see `isConstructorReference`'s
        // declaration above for why it is folded into the "bound" side here.
        let isBoundReceiver = (receiver != nil && unboundClassType == nil)
            || isConstructorReference || isImplicitlyBoundMember

        // BUG-164: callable references must also support SAM-conversion to a
        // functional interface expected type, the same way lambda literals do.
        let expectedFunctionType: TypeID?
        let expectedSamInterfaceType: TypeID?
        if let expectedType {
            if case .functionType = sema.types.kind(of: expectedType) {
                expectedFunctionType = expectedType
                expectedSamInterfaceType = nil
            } else if let functionType = sema.types.nominalFunctionType(for: expectedType) {
                expectedFunctionType = sema.types.make(.functionType(functionType))
                expectedSamInterfaceType = nil
            } else if let samFT = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
                expectedFunctionType = sema.types.make(.functionType(samFT))
                expectedSamInterfaceType = expectedType
            } else {
                expectedFunctionType = nil
                expectedSamInterfaceType = nil
            }
        } else {
            expectedFunctionType = nil
            expectedSamInterfaceType = nil
        }

        // `Type::toString` as a `(Type) -> String` value: the zero-argument
        // `toString()` has no member symbol (only the `toString(radix)`
        // overload is declared), so every candidate is an arity mismatch.
        // kotlinc picks the overload matching the expected function type;
        // synthesize the missing one.
        if let unboundClassType,
           interner.resolve(member) == "toString",
           let expectedFunctionType,
           case let .functionType(expectedFT) = sema.types.kind(of: expectedFunctionType),
           expectedFT.params.count == 1,
           !candidates.contains(where: { candidate in
               guard let signature = sema.symbols.functionSignature(for: candidate) else { return false }
               return signature.parameterTypes.count == 0 && signature.receiverType != nil
           })
        {
            let receiverParam = sema.types.makeNonNullable(unboundClassType)
            let inferredType = sema.types.make(.functionType(FunctionType(
                params: [receiverParam],
                returnType: sema.types.stringType,
                isSuspend: false,
                isCallableReference: true,
                nullability: .nonNull
            )))
            let resultType: TypeID
            if sema.types.typeContainsAnyTypeParam(expectedType ?? expectedFunctionType) {
                resultType = inferredType
            } else {
                driver.emitSubtypeConstraint(
                    left: inferredType,
                    right: expectedFunctionType,
                    range: range,
                    solver: ConstraintSolver(),
                    sema: sema,
                    diagnostics: ctx.semaCtx.diagnostics
                )
                resultType = expectedSamInterfaceType ?? expectedFunctionType
            }
            sema.bindings.bindAnyToStringCallableRef(id)
            sema.bindings.bindCallableRefKind(id, kind: .functionRef)
            sema.bindings.markUnboundCallableRef(id)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        // Concrete value and type receivers specialize the owner's type parameters.
        let boundReceiverType: TypeID? = if isImplicitlyBoundMember {
            implicitBoundReceiver?.type
        } else if receiver != nil && !isConstructorReference {
            effectiveReceiverType.map { sema.types.makeNonNullable($0) }
        } else {
            nil
        }
        let chosen = driver.helpers.chooseCallableReferenceTarget(
            from: candidates,
            expectedType: expectedFunctionType,
            bindReceiver: isBoundReceiver,
            boundReceiverType: boundReceiverType,
            sema: sema
        )

        if let chosen,
           let signature = sema.symbols.functionSignature(for: chosen)
        {
            var inferredType = driver.helpers.callableFunctionType(
                for: signature,
                bindReceiver: isBoundReceiver,
                boundReceiver: boundReceiverType.map { (chosen, $0) },
                sema: sema
            )
            let resultType: TypeID
            // An expected type that still mentions type parameters belongs to a
            // generic signature whose type arguments are inferred from this very
            // argument (`fun <T> runCatching(block: () -> T)`). Checking against
            // it would fail, and adopting it would hide the concrete type the
            // caller needs for inference, so report the reference's own type.
            if let expectedFunctionType {
                let concreteResult = expectedSamInterfaceType ?? expectedFunctionType
                if !sema.types.typeContainsAnyTypeParam(concreteResult) {
                    if let specializedType = driver.helpers.contextualCallableFunctionType(
                        for: signature,
                        bindReceiver: isBoundReceiver,
                        boundReceiver: boundReceiverType.map { (chosen, $0) },
                        expectedFunctionType: expectedFunctionType,
                        sema: sema
                    ) {
                        inferredType = specializedType
                    } else {
                        ctx.semaCtx.diagnostics.error(
                            "KSWIFTK-TYPE-0001",
                            "Type constraint could not be satisfied.",
                            range: range
                        )
                    }
                    resultType = concreteResult
                } else {
                    resultType = inferredType
                }

            } else {
                resultType = inferredType
            }
            // BUG-164: A callable reference passed to a fun-interface parameter
            // must be SAM-converted and bound to the interface type, not left as a
            // bare function type.  `lowerCallableRefExpr` checks `isSamConversion`
            // and emits the wrapper object that makes interface dispatch work.
            // Only perform the conversion when the resolved result is the concrete
            // interface type; if the expected type still contains type parameters,
            // leave the reference as a function value so generic inference can
            // substitute a concrete instantiation later.
            if let expectedSamInterfaceType,
               resultType == expectedSamInterfaceType
            {
                sema.bindings.markSamConversion(id)
                sema.bindings.bindSamInterfaceType(id, type: expectedSamInterfaceType)
                sema.bindings.bindSamUnderlyingFunctionType(id, type: expectedFunctionType ?? inferredType)
            }
            sema.bindings.bindIdentifier(id, symbol: chosen)
            sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
            // REFL-003: Tag the callable reference as KFunction so KIR
            // lowering can emit type identity metadata.
            sema.bindings.bindCallableRefKind(id, kind: .functionRef)
            if isImplicitlyBoundMember {
                sema.bindings.markImplicitReceiverMember(id, name: member)
                if let implicitBoundReceiver {
                    sema.bindings.markImplicitReceiverOuterReceiver(id, symbol: implicitBoundReceiver.symbol)
                }
            }
            if unboundClassType != nil && !isConstructorReference {
                sema.bindings.markUnboundCallableRef(id)
            }
            let captures = receiver.map { recv in
                driver.captureAnalyzer.collectCapturedOuterSymbols(
                    in: recv,
                    ast: ast,
                    sema: sema,
                    outerSymbols: outerSymbols
                )
            } ?? []
            sema.bindings.bindCaptureSymbols(id, symbols: captures)
            sema.bindings.bindExprType(id, type: resultType)
            return resultType
        }

        if candidates.isEmpty {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '::\(interner.resolve(member))'.",
                range: range
            )
        }
        let fallbackType: TypeID = if let expectedType,
                                      case .functionType = sema.types.kind(of: expectedType)
        {
            expectedType
        } else if candidates.isEmpty {
            sema.types.errorType
        } else {
            sema.types.anyType
        }
        let fallbackCaptures = receiver.map { recv in
            driver.captureAnalyzer.collectCapturedOuterSymbols(
                in: recv,
                ast: ast,
                sema: sema,
                outerSymbols: outerSymbols
            )
        } ?? []
        sema.bindings.bindCaptureSymbols(id, symbols: fallbackCaptures)
        sema.bindings.bindExprType(id, type: fallbackType)
        return fallbackType
    }

    /// REFL-PRIMOP: `Int::plus` / `Int::times` (and the other primitive
    /// numeric types where an expected function type selects the
    /// homogeneous `(T, T) -> T` overload -- Byte/Short/Char are excluded
    /// because their real stdlib `plus`/`times` overloads promote the result to `Int`, unlike
    /// Int/Long/UInt/ULong/Float/Double's own-type result) have no real
    /// `plus`/`times` member symbol to resolve: arithmetic on primitives is
    /// a table-driven type-inference special case
    /// (`tryInferRegularMemberCallPrimitiveSpecials`), not a function
    /// declaration. Synthesizes the reference's function type directly and
    /// records the raw binary operator on `sema.bindings` for KIR lowering
    /// (`LambdaLowerer.lowerPrimitiveOperatorCallableRef`) to build a
    /// wrapper around, since there is no symbol for it to call either.
    ///
    /// Returns `nil` when `receiverName`/`member` don't name a supported
    /// primitive-operator pair, so the caller falls through to ordinary
    /// candidate resolution.
    private func inferPrimitiveOperatorCallableRefExpr(
        _ id: ExprID,
        receiverName: InternedString,
        member: InternedString,
        expectedType: TypeID?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        guard let primitive = driver.builtinTypeNamesCache.primitiveType(for: receiverName) else {
            return nil
        }
        let op: BinaryOp
        switch interner.resolve(member) {
        case "plus": op = .add
        case "times": op = .multiply
        default: return nil
        }
        switch primitive {
        case .int, .long, .uint, .ulong, .float, .double:
            break
        default:
            return nil
        }
        let contextualType = expectedType.map { type in
            sema.types.nominalFunctionType(for: type).map {
                sema.types.make(.functionType($0))
            } ?? type
        }
        guard let expectedType = contextualType, case .functionType = sema.types.kind(of: expectedType) else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0003",
                "Ambiguous overload resolution for '\(interner.resolve(receiverName))::\(interner.resolve(member))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let operandType = sema.types.make(.primitive(primitive, .nonNull))
        let functionType = sema.types.make(.functionType(FunctionType(
            params: [operandType, operandType],
            returnType: operandType,
            isSuspend: false,
            isCallableReference: true,
            nullability: .nonNull
        )))
        driver.emitSubtypeConstraint(
            left: functionType,
            right: expectedType,
            range: range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.semaCtx.diagnostics
        )
        sema.bindings.bindPrimitiveOperatorCallableRef(id, op: op)
        sema.bindings.bindCallableRefKind(id, kind: .functionRef)
        sema.bindings.bindExprType(id, type: expectedType)
        return expectedType
    }

    /// Binds an unbound `Type::property` (or, when `ownerType` is `nil`, a
    /// bound `instance::property`) callable reference to `propertySymbol` and
    /// returns its result type. Shared by the FQ-based owner-member lookup
    /// and the package-level extension-property fallback in
    /// `inferCallableRefExpr`, which differ only in how they find
    /// `propertySymbol`.
    private func bindPropertyCallableRef(
        _ id: ExprID,
        propertySymbol: SymbolID,
        ownerType: TypeID?,
        isUnbound: Bool,
        expectedType: TypeID?,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        var propertyType = sema.symbols.propertyType(for: propertySymbol) ?? sema.types.errorType
        if let ownerType, let owner = sema.symbols.parentSymbol(for: propertySymbol) {
            propertyType = driver.helpers.resolveMemberPropertyType(
                propertyType,
                receiverType: ownerType,
                ownerSymbol: owner,
                sema: sema
            )
        }
        let isMutable = sema.symbols.symbol(propertySymbol)?.flags.contains(.mutable) == true
        let inferredType = kPropertyReferenceType(
            ownerType: ownerType,
            valueType: propertyType,
            isMutable: isMutable,
            sema: sema,
            interner: interner
        ) ?? propertyType
        let resultType = resolvedPropertyReferenceResultType(
            expectedType: expectedType,
            inferredType: inferredType,
            sema: sema,
            interner: interner
        )
        sema.bindings.bindIdentifier(id, symbol: propertySymbol)
        sema.bindings.bindCallableTarget(id, target: .symbol(propertySymbol))
        sema.bindings.bindCallableRefKind(id, kind: .propertyRef)
        if isUnbound {
            sema.bindings.markUnboundCallableRef(id)
        }
        markPropertyReferenceSamConversionIfNeeded(
            id,
            expectedType: expectedType,
            resultType: resultType,
            sema: sema
        )
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    /// Builds the concrete `KProperty0<V>` / `KMutableProperty0<V>` /
    /// `KProperty1<Owner, V>` / `KMutableProperty1<Owner, V>` type for a plain
    /// property callable reference (`Type::property`, `instance::property`, or
    /// bare `::property`), so a reference used without an expected type (e.g.
    /// `val ref = C::v`, or as an argument whose parameter type is itself
    /// inferred, like `listOf(C::v)`) still gets a real KProperty-conforming
    /// type instead of degrading to the property's own value type.
    ///
    /// `ownerType` is `nil` for a bound (`instance::property`) or top-level
    /// (bare `::property`) reference (arity 0: `KProperty0`/`KMutableProperty0`),
    /// and the receiver's class type for an unbound (`Type::property`)
    /// reference (arity 1: `KProperty1`/`KMutableProperty1`).
    ///
    /// Returns `nil` when the interface symbol isn't registered (e.g.
    /// `kotlin.reflect` wasn't injected), in which case callers should keep
    /// their previous fallback behavior.
    private func kPropertyReferenceType(
        ownerType: TypeID?,
        valueType: TypeID,
        isMutable: Bool,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        let reflectPkg = [interner.intern("kotlin"), interner.intern("reflect")]
        let interfaceName: String
        let typeArgs: [TypeArg]
        if let ownerType {
            interfaceName = isMutable ? "KMutableProperty1" : "KProperty1"
            typeArgs = [.invariant(ownerType), .invariant(valueType)]
        } else {
            interfaceName = isMutable ? "KMutableProperty0" : "KProperty0"
            typeArgs = [.invariant(valueType)]
        }
        guard let interfaceSymbol = sema.symbols.lookup(fqName: reflectPkg + [interner.intern(interfaceName)]) else {
            return nil
        }
        return sema.types.make(.classType(ClassType(
            classSymbol: interfaceSymbol,
            args: typeArgs,
            nullability: .nonNull
        )))
    }

    /// KSP-496: a *property* callable reference used in a fun-interface
    /// position (`fun interface IntFromC { fun apply(c: C): Int }` +
    /// `useSam(C::v)`) needs the same SAM-conversion bookkeeping BUG-164 added
    /// for function references. `resolvedPropertyReferenceResultType` already
    /// adopts the interface as the reference's type, but `lowerCallableRefExpr`
    /// only builds the wrapper object that makes interface dispatch work when
    /// `isSamConversion` is set — without it the raw tagged callable value was
    /// handed to the interface parameter and the call panicked at runtime
    /// ("Virtual dispatch failed: method not found in vtable/itable").
    private func markPropertyReferenceSamConversionIfNeeded(
        _ id: ExprID,
        expectedType: TypeID?,
        resultType: TypeID,
        sema: SemaModule
    ) {
        guard let expectedType,
              resultType == expectedType,
              let samFunctionType = driver.helpers.samFunctionType(for: expectedType, sema: sema)
        else {
            return
        }
        sema.bindings.markSamConversion(id)
        sema.bindings.bindSamInterfaceType(id, type: expectedType)
        sema.bindings.bindSamUnderlyingFunctionType(
            id,
            type: sema.types.make(.functionType(samFunctionType))
        )
    }

    /// Decides the expression type for a property callable reference.
    ///
    /// A property reference is also a valid function value — Kotlin allows
    /// `list.map(Person::name)` or `val f: (Person) -> String = Person::name`
    /// — so an `expectedType` that is a function type (or SAM-convertible
    /// interface) is always trusted as-is, exactly like before this fix and
    /// exactly like the sibling function-reference branch above.
    ///
    /// Otherwise, `expectedType` is only trusted when it is itself one of the
    /// four concrete KProperty shapes (`KProperty0`/`KMutableProperty0`/
    /// `KProperty1`/`KMutableProperty1`) — the same set
    /// `propertyReferenceShape` in `LambdaLowerer+PropertyReferenceLowering.swift`
    /// recognizes to build the real KIR wrapper object. A broader or unrelated
    /// expected type (`Any`, `KProperty<*>`, `KCallable<*>`, ...) would
    /// silently defeat that wrapper and fall back to a non-conforming legacy
    /// value, so `inferredType` (the correct concrete shape this reference
    /// actually has) is used instead in that case.
    private func resolvedPropertyReferenceResultType(
        expectedType: TypeID?,
        inferredType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID {
        guard let expectedType else {
            return inferredType
        }
        if case .functionType = sema.types.kind(of: expectedType) {
            // A concrete function-type expectation is only safe to adopt when
            // the reference's own `KPropertyN` type is a subtype of it via the
            // `KPropertyN` → `FunctionN` inheritance path (KUU-1195). The
            // previous unconditional trust accepted signature mismatches
            // (`supply(Box::value)` for a `() -> Int` parameter, receiver or
            // return-type mismatches) whose binaries then crashed at runtime
            // on invoke. On a mismatch keep the real inferred type so the
            // caller's own subtype check reports the failure. Expected types
            // still mentioning type parameters keep the trusted behavior —
            // they belong to a generic signature whose type arguments are
            // bound from this very argument. A non-`KPropertyN` inferred type
            // means `kotlin.reflect` was unavailable; keep trusting then too.
            if !sema.types.typeContainsAnyTypeParam(expectedType),
               isConcreteKPropertyReferenceShape(inferredType, sema: sema, interner: interner),
               !sema.types.isSubtype(inferredType, expectedType)
            {
                return inferredType
            }
            return expectedType
        }
        if let samFunctionType = driver.helpers.samFunctionType(for: expectedType, sema: sema) {
            // Same check against the SAM signature for a fun-interface
            // expected type (`useSam(C::v)`): adopt the interface type only
            // when the reference's function view matches the SAM.
            if !sema.types.typeContainsAnyTypeParam(expectedType),
               isConcreteKPropertyReferenceShape(inferredType, sema: sema, interner: interner),
               !sema.types.isSubtype(inferredType, sema.types.make(.functionType(samFunctionType)))
            {
                return inferredType
            }
            return expectedType
        }
        guard isConcreteKPropertyReferenceShape(expectedType, sema: sema, interner: interner) else {
            return inferredType
        }
        return expectedType
    }

    private func isConcreteKPropertyReferenceShape(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard case let .classType(classType) = sema.types.kind(of: sema.types.makeNonNullable(type)),
              let symbol = sema.symbols.symbol(classType.classSymbol)
        else {
            return false
        }
        switch interner.resolve(symbol.name) {
        case "KProperty0", "KMutableProperty0", "KProperty1", "KMutableProperty1":
            return true
        default:
            return false
        }
    }

    private func inferClassRefExpr(
        _ id: ExprID,
        receiver: ExprID,
        receiverName: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let allCandidateIDs = ctx.cachedScopeLookup(receiverName)
        for candidateID in allCandidateIDs {
            guard let sym = ctx.cachedSymbol(candidateID),
                  sym.kind == .typeParameter else { continue }
            if !sym.flags.contains(.reifiedTypeParameter) {
                let name = interner.resolve(sym.name)
                ctx.semaCtx.diagnostics.error(
                    "KSWIFTK-SEMA-REIFIED",
                    "Cannot use 'T::class' on non-reified type parameter '\(name)'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let resolved = sema.types.make(.typeParam(TypeParamType(symbol: sym.id)))
            sema.bindings.bindClassRefTargetType(id, type: resolved)
            let kClassType = sema.types.makeKClassType(argument: resolved)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        for candidateID in allCandidateIDs {
            guard let sym = ctx.cachedSymbol(candidateID),
                  sym.kind == .class || sym.kind == .interface
                  || sym.kind == .object || sym.kind == .enumClass
                  || sym.kind == .annotationClass
            else { continue }
            let classType = sema.types.make(.classType(ClassType(classSymbol: sym.id)))
            sema.bindings.bindClassRefTargetType(id, type: classType)
            let kClassType = sema.types.makeKClassType(argument: classType)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        // REFL-002: Handle builtin/primitive type names (Int, String, Boolean, etc.)
        // These are not class symbols in the symbol table but still support ::class.
        let builtinNames = driver.builtinTypeNamesCache
        if let builtinType = builtinNames.resolveBuiltinType(receiverName, types: sema.types) {
            sema.bindings.bindClassRefTargetType(id, type: builtinType)
            let kClassType = sema.types.makeKClassType(argument: builtinType)
            sema.bindings.bindExprType(id, type: kClassType)
            _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
            return kClassType
        }
        // KUU-1084: `FunctionN::class`. The synthetic `kotlin.Function.FunctionN`
        // interfaces live outside ordinary scope lookup, but `FunctionN::class`
        // is the classifier of every arity-N function type in Kotlin.
        let receiverNameString = interner.resolve(receiverName)
        if receiverNameString.hasPrefix("Function"),
           let arity = Int(receiverNameString.dropFirst("Function".count)),
           arity >= 0 {
            let functionFQName = [
                interner.intern("kotlin"), interner.intern("Function"), receiverName,
            ]
            if let functionSymbol = sema.symbols.lookupAll(fqName: functionFQName)
                .compactMap({ sema.symbols.symbol($0) })
                .first(where: { $0.kind == .interface })?.id {
                let classType = sema.types.make(.classType(ClassType(classSymbol: functionSymbol)))
                sema.bindings.bindClassRefTargetType(id, type: classType)
                let kClassType = sema.types.makeKClassType(argument: classType)
                sema.bindings.bindExprType(id, type: kClassType)
                _ = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
                return kClassType
            }
        }
        return nil
    }

    private func inferExprReceiverClassRef(
        _ id: ExprID,
        receiver: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let receiverType = driver.inferExpr(receiver, ctx: ctx, locals: &locals, expectedType: nil)
        if receiverType == sema.types.errorType {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        // A qualified classifier such as `Outer.Nested` is a static class
        // literal, even when Outer has a companion value. Do not evaluate it
        // as a bound receiver; constructor calls and properties stay bound.
        if case let .memberCall(_, _, _, args, _) = ctx.ast.arena.expr(receiver),
           args.isEmpty, !ctx.ast.arena.isExplicitCall(receiver),
           let symbolID = sema.bindings.identifierSymbol(for: receiver),
           let symbol = sema.symbols.symbol(symbolID),
           symbol.kind == .class || symbol.kind == .interface || symbol.kind == .enumClass
               || symbol.kind == .annotationClass || symbol.kind == .object
        {
            let targetType = sema.types.makeNonNullable(receiverType)
            sema.bindings.bindClassRefTargetType(id, type: targetType)
            let kClassType = sema.types.makeKClassType(argument: targetType)
            sema.bindings.bindExprType(id, type: kClassType)
            return kClassType
        }
        var visited: Set<TypeID> = []
        let isFlowNonNull: Bool
        if case let .nameRef(name, _) = ctx.ast.arena.expr(receiver),
           let local = locals[name],
           let flow = ctx.flowState.variables[local.symbol] {
            isFlowNonNull = flow.isStable && flow.nullability == .nonNull
        } else {
            isFlowNonNull = false
        }
        if !isFlowNonNull, classRefReceiverCanBeNull(receiverType, sema: sema, visited: &visited) {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-CLASS-REF-NULLABLE",
                "Expression in a class literal has a nullable type. Use '!!' to make it non-nullable.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let targetType = sema.types.makeNonNullable(receiverType)
        sema.bindings.bindClassRefTargetType(id, type: targetType)
        sema.bindings.bindBoundClassRef(id)
        let kClassType = sema.types.makeKClassType(argument: targetType)
        sema.bindings.bindExprType(id, type: kClassType)
        return kClassType
    }

    private func classRefReceiverCanBeNull(_ type: TypeID, sema: SemaModule, visited: inout Set<TypeID>) -> Bool {
        guard visited.insert(type).inserted else {
            return true
        }
        switch sema.types.kind(of: type) {
        case let .typeParam(parameter):
            if parameter.nullability == .nullable {
                return true
            }
            let bounds = sema.symbols.typeParameterUpperBounds(for: parameter.symbol)
            return bounds.allSatisfy { classRefReceiverCanBeNull($0, sema: sema, visited: &visited) }
        case let .intersection(parts):
            return parts.allSatisfy { classRefReceiverCanBeNull($0, sema: sema, visited: &visited) }
        default:
            return sema.types.nullability(of: type) == .nullable
        }
    }

    func inferSuperRefExpr(
        _ id: ExprID,
        interfaceQualifier: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0050",
                "'super' is not allowed outside of a class body.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let classSymbol = driver.helpers.nominalSymbol(of: receiverType, types: sema.types) else {
            return emitNoSuperclass(id: id, range: range, ctx: ctx)
        }
        if let qualifier = interfaceQualifier {
            return resolveQualifiedSuper(
                id: id, qualifier: qualifier, classSymbol: classSymbol, range: range, ctx: ctx
            )
        }
        return resolveUnqualifiedSuper(
            id: id, classSymbol: classSymbol, receiverType: receiverType, range: range, ctx: ctx
        )
    }

    /// Resolves `super<T>` — only direct supertypes (interfaces and classes) are valid per Kotlin spec.
    private func resolveQualifiedSuper(
        id: ExprID,
        qualifier: InternedString,
        classSymbol: SymbolID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let supertypes = sema.symbols.directSupertypes(for: classSymbol)
        for superID in supertypes {
            guard let superSym = ctx.cachedSymbol(superID) else { continue }
            let isValidKind = superSym.kind == .interface || superSym.kind == .class || superSym.kind == .enumClass
            if isValidKind, superSym.name == qualifier {
                let typeArgs: [TypeArg]
                if let receiverType = ctx.implicitReceiverType,
                   case let .classType(currentClass) = sema.types.kind(of: receiverType) {
                    typeArgs = sema.types.liftedNominalSupertypeArgs(
                        from: classSymbol, childArgs: currentClass.args, to: superID
                    ) ?? []
                } else {
                    typeArgs = []
                }
                let superType = sema.types.make(.classType(ClassType(classSymbol: superID, args: typeArgs)))
                sema.bindings.bindExprType(id, type: superType)
                return superType
            }
        }
        let qualifierStr = ctx.interner.resolve(qualifier)
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0054",
            "No type '\(qualifierStr)' found in direct supertypes for qualified 'super'.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    private func resolveUnqualifiedSuper(
        id: ExprID,
        classSymbol: SymbolID,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        let supertypes = sema.symbols.directSupertypes(for: classSymbol)
        let classSupertypes = supertypes.filter {
            let kind = ctx.cachedSymbol($0)?.kind
            return kind == .class || kind == .enumClass
        }
        if let superclass = classSupertypes.first {
            let superType = sema.types.make(.classType(ClassType(classSymbol: superclass)))
            sema.bindings.bindExprType(id, type: superType)
            return superType
        }
        let hasInterfaces = supertypes.contains { ctx.cachedSymbol($0)?.kind == .interface }
        if hasInterfaces {
            sema.bindings.bindExprType(id, type: receiverType)
            return receiverType
        }
        return emitNoSuperclass(id: id, range: range, ctx: ctx)
    }

    private func emitNoSuperclass(id: ExprID, range: SourceRange, ctx: TypeInferenceContext) -> TypeID {
        let sema = ctx.sema
        ctx.semaCtx.diagnostics.error(
            "KSWIFTK-SEMA-0052",
            "Class has no superclass.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    func inferThisRefExpr(
        _ id: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        guard let receiverType = ctx.implicitReceiverType else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0051",
                "'this' is not allowed in this context.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let label {
            if let qualifiedType = ctx.resolveQualifiedThis(label: label) {
                // An outer receiver whose enclosing `this` is capturable (e.g.
                // the class around an object literal) binds to its receiver
                // parameter symbol so capture analysis stores it and KIR
                // reads the captured value instead of the innermost receiver.
                if let receiverSymbol = ctx.resolveQualifiedThisReceiverSymbol(label: label) {
                    sema.bindings.bindIdentifier(id, symbol: receiverSymbol)
                } else if let currentDeclSymbol = ctx.currentDeclSymbol,
                          let currentDecl = sema.symbols.symbol(currentDeclSymbol),
                          currentDecl.name == label,
                          sema.symbols.functionSignature(for: currentDeclSymbol)?.receiverType != nil
                {
                    // An extension function's receiver is also addressable by the
                    // function-name label (for example `this@describe`). Bind that
                    // reference to the same synthetic receiver symbol used by KIR
                    // so nested receiver lambdas capture the outer receiver rather
                    // than accidentally reading their own receiver.
                    sema.bindings.bindIdentifier(
                        id,
                        symbol: SyntheticSymbolScheme.receiverParameterSymbol(for: currentDeclSymbol)
                    )
                }
                sema.bindings.bindExprType(id, type: qualifiedType)
                return qualifiedType
            }
            let labelStr = ctx.interner.resolve(label)
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0053",
                "Unresolved label '\(labelStr)' for qualified 'this'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let thisLocal = locals[ctx.interner.intern("this")] {
            sema.bindings.bindIdentifier(id, symbol: thisLocal.symbol)
            sema.bindings.bindExprType(id, type: thisLocal.type)
            return thisLocal.type
        }
        sema.bindings.bindExprType(id, type: receiverType)
        return receiverType
    }

    private enum ParentLambdaCallContext {
        case topLevel(calleeName: InternedString, argIndex: Int, typeArgs: [TypeRefID])
        case member(receiverType: TypeID?, calleeName: InternedString, argIndex: Int, typeArgs: [TypeRefID])
    }

    /// Finds the parent call context for a lambda expression by scanning the arena.
    private func findParentCallContext(for lambdaId: ExprID, ctx: TypeInferenceContext, sema _: SemaModule) -> ParentLambdaCallContext? {
        let ast = ctx.ast
        for expr in ast.arena.exprs {
            switch expr {
            case let .call(callee, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }),
                      let calleeExpr = ast.arena.expr(callee),
                      case let .nameRef(calleeName, _) = calleeExpr
                else {
                    continue
                }
                return .topLevel(calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            case let .memberCall(receiver, calleeName, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            case let .safeMemberCall(receiver, calleeName, typeArgs, args, _):
                guard let argIndex = args.firstIndex(where: { $0.expr == lambdaId }) else {
                    continue
                }
                let receiverType = ctx.sema.bindings.exprTypes[receiver]
                return .member(receiverType: receiverType, calleeName: calleeName, argIndex: argIndex, typeArgs: typeArgs)

            default:
                continue
            }
        }
        return nil
    }

    /// Infers the type for an implicit `it` parameter based on context
    private func inferItParameterType(ctx: TypeInferenceContext, id: ExprID, sema: SemaModule) -> TypeID? {
        if let parentCall = findParentCallContext(for: id, ctx: ctx, sema: sema) {
            return inferTypeFromHOFContext(parentCall, ctx: ctx, sema: sema)
        }

        if let assignmentType = inferFromAssignmentContext() {
            return assignmentType
        }

        return nil
    }

    /// Infers lambda parameter type from HOF call context
    private func inferTypeFromHOFContext(
        _ callContext: ParentLambdaCallContext,
        ctx: TypeInferenceContext,
        sema: SemaModule
    ) -> TypeID? {
        let candidateSymbols: [SymbolID]
        let argIndex: Int
        let explicitTypeArgRefs: [TypeRefID]

        switch callContext {
        case let .topLevel(calleeName, index, typeArgs):
            argIndex = index
            explicitTypeArgRefs = typeArgs
            candidateSymbols = ctx.filterByVisibility(
                ctx.cachedScopeLookup(calleeName).filter { candidate in
                    guard let symbol = ctx.cachedSymbol(candidate) else { return false }
                    return symbol.kind == .function || symbol.kind == .constructor
                }
            ).visible

        case let .member(receiverType, calleeName, index, typeArgs):
            guard let receiverType else {
                return nil
            }
            argIndex = index
            explicitTypeArgRefs = typeArgs
            candidateSymbols = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: receiverType,
                sema: sema,
                interner: ctx.interner
            )
        }

        let explicitTypeArgs = explicitTypeArgRefs.map { typeArgRef in
            driver.helpers.resolveTypeRef(
                typeArgRef,
                ast: ctx.ast,
                sema: sema,
                interner: ctx.interner,
                scope: ctx.scope,
                inferenceContext: ctx
            )
        }

        var inferredParameterTypes: [TypeID] = []
        for candidate in candidateSymbols {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  argIndex < signature.parameterTypes.count
            else {
                continue
            }
            let parameterType = signature.parameterTypes[argIndex]
            if case let .functionType(functionType) = sema.types.kind(of: parameterType),
               functionType.params.count == 1
            {
                inferredParameterTypes.append(substituteExplicitTypeArgument(
                    functionType.params[0],
                    signature: signature,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                ))
                continue
            }
            if let samFunctionType = driver.helpers.samFunctionType(for: parameterType, sema: sema),
               samFunctionType.params.count == 1
            {
                inferredParameterTypes.append(substituteExplicitTypeArgument(
                    samFunctionType.params[0],
                    signature: signature,
                    explicitTypeArgs: explicitTypeArgs,
                    sema: sema
                ))
            }
        }

        guard let firstType = inferredParameterTypes.first else {
            return nil
        }
        let allSame = inferredParameterTypes.dropFirst().allSatisfy { $0 == firstType }
        return allSame ? firstType : nil
    }

    /// Replaces a candidate's own type parameter with the explicit type argument
    /// written at the call site. Overloads of the same generic function declare
    /// distinct type parameter symbols, so without this substitution the candidate
    /// parameter types never agree and the implicit `it` type stays unresolved for
    /// every argument of a call such as `compareBy<Row>({ it.a }, { it.b })`.
    private func substituteExplicitTypeArgument(
        _ type: TypeID,
        signature: FunctionSignature,
        explicitTypeArgs: [TypeID],
        sema: SemaModule
    ) -> TypeID {
        guard !explicitTypeArgs.isEmpty,
              case let .typeParam(typeParam) = sema.types.kind(of: type)
        else {
            return type
        }
        let ownTypeParameters = signature.typeParameterSymbols.dropFirst(signature.classTypeParameterCount)
        guard let offset = ownTypeParameters.firstIndex(of: typeParam.symbol) else {
            return type
        }
        let argOffset = offset - ownTypeParameters.startIndex
        guard argOffset < explicitTypeArgs.count else {
            return type
        }
        let explicitType = explicitTypeArgs[argOffset]
        guard explicitType != sema.types.errorType else {
            return type
        }
        return typeParam.nullability == .nullable
            ? sema.types.makeNullable(explicitType)
            : explicitType
    }

    /// Infers lambda parameter type from assignment context
    private func inferFromAssignmentContext() -> TypeID? {
        // This would analyze assignments like `val x: (Int) -> String = { it.toString() }`
        return nil
    }

    /// Optimizes return type inference for lambda expressions
    private func inferOptimizedReturnType(
        inferredBodyType: TypeID,
        expectedReturnType: TypeID,
        sema: SemaModule
    ) -> TypeID {
        // Unit optimization: if expected type is Unit, always return Unit
        if expectedReturnType == sema.types.unitType {
            return sema.types.unitType
        }

        // If the body is already compatible with expected type, use it
        if sema.types.isSubtype(inferredBodyType, expectedReturnType) {
            return inferredBodyType
        }

        // Fall back to inferred type
        return inferredBodyType
    }
}
