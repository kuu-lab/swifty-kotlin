
extension ExprTypeChecker {
    private struct IncrementDecrementInferenceResult {
        let expressionType: TypeID
        let assignedType: TypeID
    }

    private func bindCompoundAssignmentOperatorCall(
        exprID: ExprID,
        op: CompoundAssignOp,
        receiverType: TypeID,
        valueType: TypeID,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext,
        requireUnitReturn: Bool,
        emitDiagnostics: Bool = true,
        bindCall: Bool = true,
        allowFallbackOnNoViableOverload: Bool = false,
        inferCandidateReturnTypes: Bool = false,
        onAssignedType: ((TypeID) -> Void)? = nil
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
        let call = CallExpr(
            range: range, calleeName: operatorNames[0], args: [CallArg(type: valueType)]
        )
        var operatorCandidates = collectOperatorCandidates(
            names: operatorNames,
            receiverType: receiverType,
            call: call,
            locals: locals,
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

        if inferCandidateReturnTypes {
            // A bare object operator can be an expression-bodied member whose
            // return type is still the header's `Any` placeholder. Infer only
            // on this path before deciding whether `plusAssign` returns Unit.
            driver.inferFunctionReturnTypesIfNeeded(for: operatorCandidates)
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: operatorCandidates,
            call: call,
            expectedType: nil,
            implicitReceiverType: receiverType,
            ctx: ctx.sema
        )

        if usesScopedCharExtensions, resolved.chosenCallee == nil,
           resolved.diagnostic?.code == "KSWIFTK-SEMA-0002"
        {
            return nil
        }
        if let diagnostic = resolved.diagnostic {
            if allowFallbackOnNoViableOverload, diagnostic.code == "KSWIFTK-SEMA-0002" {
                return nil
            }
            if emitDiagnostics {
                ctx.sema.diagnostics.emit(diagnostic)
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
                ctx.sema.diagnostics.error(
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
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0301",
                    "Operator '\(interner.resolve(operatorNames[0]))' result type must be assignable to the left-hand side.",
                    range: range
                )
                sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            }
            return sema.types.errorType
        }

        if !requireUnitReturn {
            onAssignedType?(returnType)
        }
        if bindCall {
            sema.bindings.bindExprType(exprID, type: sema.types.unitType)
        }
        return sema.types.unitType
    }

    /// A missing overload returns `nil` so primitive targets can continue through
    /// the existing builtin compound-assignment path.
    private func bindIncrementDecrementOperatorCall(
        exprID: ExprID,
        op: CompoundAssignOp,
        receiverType: TypeID,
        assignmentType: TypeID,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> IncrementDecrementInferenceResult? {
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
        let call = CallExpr(
            range: range,
            calleeName: operatorName,
            args: []
        )
        let operatorCandidates = collectOperatorCandidates(
            names: [operatorName],
            receiverType: receiverType,
            call: call,
            locals: locals,
            ctx: ctx
        )
        guard !operatorCandidates.isEmpty else {
            return nil
        }

        let resolved = ctx.resolver.resolveCall(
            candidates: operatorCandidates,
            call: call,
            expectedType: nil,
            implicitReceiverType: receiverType,
            ctx: ctx.sema
        )
        if let diagnostic = resolved.diagnostic {
            ctx.sema.diagnostics.emit(diagnostic)
            sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            return IncrementDecrementInferenceResult(
                expressionType: sema.types.errorType,
                assignedType: sema.types.errorType
            )
        }
        guard let chosen = resolved.chosenCallee else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                range: range
            )
            sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            return IncrementDecrementInferenceResult(
                expressionType: sema.types.errorType,
                assignedType: sema.types.errorType
            )
        }

        let returnType = driver.callChecker.bindCallAndResolveReturnType(
            exprID,
            chosen: chosen,
            resolved: resolved,
            sema: sema
        )
        // Resolve the operator against the flow-refined read type, but check its
        // result against the declared storage type. The implicit write clears
        // the old narrowing instead of adopting the operator's return type.
        guard sema.types.isSubtype(returnType, assignmentType) else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0303",
                "Operator '\(interner.resolve(operatorName))' result type must be assignable to the left-hand side.",
                range: range
            )
            sema.bindings.bindExprType(exprID, type: sema.types.errorType)
            return IncrementDecrementInferenceResult(
                expressionType: sema.types.errorType,
                assignedType: sema.types.errorType
            )
        }

        let expressionType = ctx.ast.arena.incrementDecrementReturnsValue(exprID)
            ? returnType : sema.types.unitType
        sema.bindings.bindExprType(exprID, type: expressionType)
        return IncrementDecrementInferenceResult(
            expressionType: expressionType,
            assignedType: assignmentType
        )
    }

    func isBuiltinNumericIncrementDecrementTarget(_ type: TypeID, sema: SemaModule) -> Bool {
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
        ctx.sema.diagnostics.error(
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
        assignmentType: TypeID,
        isMutable: Bool,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> IncrementDecrementInferenceResult? {
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
            assignmentType: assignmentType,
            range: range,
            locals: locals,
            ctx: ctx
        ) {
            guard resolvedType.expressionType != ctx.sema.types.errorType else {
                return resolvedType
            }
            guard isMutable else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
                ctx.sema.bindings.bindExprType(exprID, type: ctx.sema.types.errorType)
                return IncrementDecrementInferenceResult(
                    expressionType: ctx.sema.types.errorType,
                    assignedType: ctx.sema.types.errorType
                )
            }
            return resolvedType
        }
        if usesBuiltinIncrement {
            guard isMutable else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0014",
                    "Val cannot be reassigned.",
                    range: range
                )
                ctx.sema.bindings.bindExprType(exprID, type: ctx.sema.types.errorType)
                return IncrementDecrementInferenceResult(
                    expressionType: ctx.sema.types.errorType,
                    assignedType: ctx.sema.types.errorType
                )
            }
            guard ctx.ast.arena.incrementDecrementReturnsValue(exprID) else {
                return nil
            }
            // Prefix `++` / `--` evaluates to the updated numeric value. Other
            // synthetic assignments keep compound-assignment's Unit result.
            ctx.sema.bindings.bindExprType(exprID, type: receiverType)
            return IncrementDecrementInferenceResult(
                expressionType: receiverType,
                assignedType: receiverType
            )
        }
        if !isPrimitiveIncrementDecrementTarget(receiverType, sema: ctx.sema),
           receiverType != ctx.sema.types.errorType
        {
            let errorType = reportMissingIncrementDecrementOperator(op, exprID: exprID, range: range, ctx: ctx)
            return IncrementDecrementInferenceResult(
                expressionType: errorType,
                assignedType: errorType
            )
        }
        return nil
    }

    private func numericCompoundAssignResultType(_ targetType: TypeID, ctx: TypeInferenceContext) -> TypeID {
        guard case let .primitive(primitive, .nonNull) = ctx.sema.types.kind(of: targetType) else {
            return ctx.sema.types.intType
        }
        switch primitive {
        case .boolean:
            return ctx.sema.types.intType
        case .char:
            return targetType
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
        let builtinRHS = resolvePrimitiveArithmeticUpperBound(
            of: rhs, types: sema.types, symbols: sema.symbols
        ) ?? rhs
        let invalidResult = lhs == sema.types.charType
            && [.add, .subtract].contains(binaryOp)
            && builtinRHS != sema.types.intType
        guard invalidResult || hasInvalidBuiltinCharArithmetic(op: binaryOp, lhs: lhs, rhs: builtinRHS, sema: sema) else {
            return false
        }
        ctx.sema.diagnostics.error(
            "KSWIFTK-SEMA-0002",
            "No viable builtin Char operator for compound assignment.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return true
    }

    func isBuiltinCompoundAssignOperand(
        op: CompoundAssignOp,
        lhs: TypeID,
        rhs: TypeID,
        sema: SemaModule
    ) -> Bool {
        if op == .plusAssign, sema.types.makeNonNullable(lhs) == sema.types.stringType {
            return true
        }
        // Dedicated user operators have already been considered. The builtin
        // arithmetic fallback can read a final numeric upper bound on the RHS.
        let primitiveRHS = resolvePrimitiveArithmeticUpperBound(
            of: rhs, types: sema.types, symbols: sema.symbols
        ) ?? rhs
        let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
        if lhs == sema.types.charType {
            if underlyingOp == .add || underlyingOp == .subtract {
                return primitiveRHS == sema.types.intType
            }
            return false
        }
        if primitiveRHS != rhs, sema.types.isUnsigned(lhs) != sema.types.isUnsigned(primitiveRHS) {
            return false
        }
        return sema.types.isBuiltinArithmeticOperand(lhs) && sema.types.isBuiltinArithmeticOperand(primitiveRHS)
    }

    private func inferObjectCompoundAssignExpr(
        _ id: ExprID,
        op: CompoundAssignOp,
        valueExpr: ExprID,
        originalValueType: TypeID,
        objectSymbol: SemanticSymbol,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        sema.bindings.bindIdentifier(id, symbol: objectSymbol.id)
        driver.helpers.checkDeprecation(
            for: objectSymbol.id,
            sema: sema,
            interner: interner,
            range: range,
            diagnostics: sema.diagnostics
        )
        driver.helpers.checkOptIn(
            for: objectSymbol.id,
            ctx: ctx,
            range: range,
            diagnostics: sema.diagnostics
        )

        let valueType = contextualCompoundAssignmentValueType(
            op: op,
            receiverType: receiverType,
            valueExpr: valueExpr,
            originalType: originalValueType,
            range: range,
            ctx: ctx,
            locals: &locals
        )
        if let resolvedType = inferIncrementDecrementIfNeeded(
            exprID: id,
            op: op,
            receiverType: receiverType,
            assignmentType: receiverType,
            isMutable: false,
            range: range,
            locals: locals,
            ctx: ctx
        ) {
            return resolvedType.expressionType
        }

        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: receiverType,
            valueType: valueType,
            range: range,
            locals: locals,
            ctx: ctx,
            requireUnitReturn: true,
            allowFallbackOnNoViableOverload: true,
            inferCandidateReturnTypes: true
        ) {
            return resolvedType
        }
        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: receiverType,
            valueType: valueType,
            range: range,
            locals: locals,
            ctx: ctx,
            requireUnitReturn: false,
            inferCandidateReturnTypes: true
        ) {
            guard resolvedType != sema.types.errorType else {
                return resolvedType
            }
            sema.diagnostics.error(
                "KSWIFTK-SEMA-0014",
                "Val cannot be reassigned.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        let operatorName = operatorFunctionNames(for: driver.helpers.compoundAssignToBinaryOp(op), interner: interner)[0]
        sema.diagnostics.error(
            "KSWIFTK-SEMA-0002",
            "No viable overload found for operator '\(interner.resolve(operatorName))'.",
            range: range
        )
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
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
            let declaredType = sema.symbols.propertyType(for: local.symbol) ?? local.type
            if local.type != declaredType {
                sema.bindings.bindCompoundAssignReceiverType(id, type: local.type)
            }
            let valueType = contextualCompoundAssignmentValueType(
                op: op, receiverType: local.type, valueExpr: valueExpr,
                originalType: valueType, range: range, ctx: ctx, locals: &locals
            )
            sema.bindings.bindIdentifier(id, symbol: local.symbol)
            if !local.isInitialized,
               sema.symbols.symbol(local.symbol)?.flags.contains(.lateinitProperty) != true
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0031",
                    "Variable '\(interner.resolve(name))' must be initialized before use.",
                    range: range
                )
            }
            if let cachedValue = ctx.ast.arena.incrementDecrementCachedValue(for: id) {
                validateExpressionAnnotationVisibility(cachedValue, ctx: ctx)
                _ = driver.inferExpr(cachedValue, ctx: ctx, locals: &locals, expectedType: local.type)
            }
            if let resolvedType = inferIncrementDecrementIfNeeded(
                exprID: id,
                op: op,
                receiverType: local.type,
                assignmentType: sema.symbols.propertyType(for: local.symbol) ?? local.type,
                isMutable: local.isMutable,
                range: range,
                locals: locals,
                ctx: ctx
            ) {
                if resolvedType.expressionType != sema.types.errorType {
                    locals[name] = (
                        resolvedType.assignedType, local.symbol, local.isMutable, local.isInitialized
                    )
                    locals.invalidateMembers(root: local.symbol)
                }
                return resolvedType.expressionType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: local.type,
                valueType: valueType,
                range: range,
                locals: locals,
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
                       locals: locals,
                       ctx: ctx,
                       requireUnitReturn: false,
                       emitDiagnostics: false,
                       bindCall: false
                   ),
                   binaryFallback != sema.types.errorType
                {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0302",
                        "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                return resolvedType
            }
            var assignedType = local.type
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: local.type,
                valueType: valueType,
                range: range,
                locals: locals,
                ctx: ctx,
                requireUnitReturn: false,
                onAssignedType: { assignedType = $0 }
            ) {
                if resolvedType == sema.types.errorType || !local.isMutable {
                    if !local.isMutable, resolvedType != sema.types.errorType {
                        ctx.sema.diagnostics.error(
                            "KSWIFTK-SEMA-0014",
                            "Val cannot be reassigned.",
                            range: range
                        )
                    }
                    return resolvedType == sema.types.errorType ? resolvedType : sema.types.errorType
                }
                locals[name] = (assignedType, local.symbol, local.isMutable, local.isInitialized)
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
            if !local.isMutable {
                ctx.sema.diagnostics.error(
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
            guard isBuiltinCompoundAssignOperand(op: op, lhs: local.type, rhs: valueType, sema: sema) else {
                let operatorName = operatorFunctionNames(for: underlyingOp, interner: interner)[0]
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            // Arithmetic compound assignment keeps the target's own numeric type
            // (BUG-015): demoting `Long`/`Double`/unsigned locals to `Int` here broke
            // later member resolution such as `longVar and 0xFFL`.
            let arithmeticResultType = numericCompoundAssignResultType(local.type, ctx: ctx)
            let resultType: TypeID = switch underlyingOp {
            case .add:
                if sema.types.makeNonNullable(local.type) == stringType || valueType == stringType {
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
        var implicitReceiverMember: (symbol: SemanticSymbol, type: TypeID, isMutable: Bool)?
        for receiverType in ctx.implicitReceiverMemberLookupTypes() {
            if let member = driver.helpers.lookupMemberPropertyForWrite(
                named: name,
                receiverType: sema.types.makeNonNullable(receiverType),
                sema: sema
            ),
               let memberSymbol = ctx.cachedSymbol(member.writeSymbol ?? member.symbol)
            {
                implicitReceiverMember = (memberSymbol, member.type, member.writeSymbol != nil)
                break
            }
        }

        // Same namespace rule as `inferLocalAssignExpr`: a tier binding the
        // name only to callables (or to member properties no implicit
        // receiver can reach) must not hide an outer-scope assignable
        // property, so `counter += 1` inside a class declaring `fun counter`
        // still writes the top-level `var counter` (KUU-3576). `.object`
        // candidates stay visible for the singleton operator path below.
        let allCandidateIDs = ctx.cachedScopeLookup(name, matching: { candidateID in
            guard let candidate = ctx.cachedSymbol(candidateID) else { return false }
            if candidate.kind == .object {
                return true
            }
            guard candidate.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: candidateID),
                  let parentSymbol = ctx.cachedSymbol(parentID)
            else {
                return true
            }
            return parentSymbol.kind == .package || parentSymbol.kind == .object
                || (ctx.implicitReceiverType != nil
                    && (parentSymbol.kind == .class || parentSymbol.kind == .object || parentSymbol.kind == .interface))
        })
        let dslBlockedIDs = allCandidateIDs.filter { ctx.isCandidateBlockedByDslMarker($0) }
        let dslFilteredIDs = allCandidateIDs.filter { !ctx.isCandidateBlockedByDslMarker($0) }
        let (visibleIDs, _) = ctx.filterByVisibility(dslFilteredIDs)
        let candidates = visibleIDs.compactMap { ctx.cachedSymbol($0) }
        var explicitlyImportedObjectProperties: Set<SymbolID> = []
        for importDecl in ctx.currentASTFile?.imports ?? [] {
            guard !importDecl.isWildcard,
                  (importDecl.alias ?? importDecl.path.last) == name
            else {
                continue
            }
            for candidateID in sema.symbols.lookupAll(fqName: importDecl.path) {
                guard sema.symbols.symbol(candidateID)?.kind == .property,
                      let ownerID = sema.symbols.parentSymbol(for: candidateID)
                else {
                    continue
                }
                if sema.symbols.symbol(ownerID)?.kind == .object {
                    explicitlyImportedObjectProperties.insert(candidateID)
                }
            }
        }
        let scopeVisibleProperty = candidates.first(where: { sym in
            guard sym.kind == .property else { return false }
            guard let parentID = sema.symbols.parentSymbol(for: sym.id),
                  let parentSym = sema.symbols.symbol(parentID) else { return true }
            return parentSym.kind == .package || explicitlyImportedObjectProperties.contains(sym.id)
                || (ctx.implicitReceiverType != nil
                && (parentSym.kind == .class || parentSym.kind == .object || parentSym.kind == .interface))
        })
        if let propSymbol = implicitReceiverMember?.symbol ?? scopeVisibleProperty {
            let isMutable = implicitReceiverMember?.isMutable
                ?? propSymbol.flags.contains(.mutable)
            let (_, invisible) = ctx.filterByVisibility([propSymbol.id])
            if let property = invisible.first {
                driver.helpers.emitVisibilityError(
                    for: property,
                    name: interner.resolve(name),
                    range: range,
                    diagnostics: ctx.sema.diagnostics
                )
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            sema.bindings.bindIdentifier(id, symbol: propSymbol.id)
            driver.helpers.checkOptIn(
                for: propSymbol.id, ctx: ctx, range: range, diagnostics: ctx.sema.diagnostics
            )
            if implicitReceiverMember != nil {
                sema.bindings.markImplicitReceiverMember(id, name: name)
            }
            let propType = implicitReceiverMember?.type ?? sema.symbols.propertyType(for: propSymbol.id) ?? sema.types.errorType
            let valueType = contextualCompoundAssignmentValueType(
                op: op, receiverType: propType, valueExpr: valueExpr,
                originalType: valueType, range: range, ctx: ctx, locals: &locals
            )
            if let cachedValue = ctx.ast.arena.incrementDecrementCachedValue(for: id) {
                _ = driver.inferExpr(cachedValue, ctx: ctx, locals: &locals, expectedType: propType)
            }
            if let resolvedType = inferIncrementDecrementIfNeeded(
                exprID: id,
                op: op,
                receiverType: propType,
                assignmentType: propType,
                isMutable: isMutable,
                range: range,
                locals: locals,
                ctx: ctx
            ) {
                if isMutable, !checkPropertySetterAccessibility(propertyID: propSymbol.id, name: name, range: range, ctx: ctx) {
                    return driver.helpers.bindAndReturnErrorType(id, sema: sema)
                }
                return resolvedType.expressionType
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: propType,
                valueType: valueType,
                range: range,
                locals: locals,
                ctx: ctx,
                requireUnitReturn: true
            ) {
                if isMutable,
                   isPropertySetterAccessible(propertyID: propSymbol.id, ctx: ctx),
                   let binaryFallback = bindCompoundAssignmentOperatorCall(
                       exprID: id,
                       op: op,
                       receiverType: propType,
                       valueType: valueType,
                       range: range,
                       locals: locals,
                       ctx: ctx,
                       requireUnitReturn: false,
                       emitDiagnostics: false,
                       bindCall: false
                   ),
                   binaryFallback != sema.types.errorType
                {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0302",
                        "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                return resolvedType
            }
            if isMutable, !checkPropertySetterAccessibility(propertyID: propSymbol.id, name: name, range: range, ctx: ctx) {
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            if let resolvedType = bindCompoundAssignmentOperatorCall(
                exprID: id,
                op: op,
                receiverType: propType,
                valueType: valueType,
                range: range,
                locals: locals,
                ctx: ctx,
                requireUnitReturn: false
            ) {
                if resolvedType == sema.types.errorType || !isMutable {
                    if !isMutable, resolvedType != sema.types.errorType {
                        ctx.sema.diagnostics.error(
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
            if !isMutable {
                ctx.sema.diagnostics.error(
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
            guard isBuiltinCompoundAssignOperand(op: op, lhs: propType, rhs: valueType, sema: sema) else {
                let operatorName = operatorFunctionNames(for: underlyingOp, interner: interner)[0]
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0002",
                    "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            let resultType: TypeID = switch underlyingOp {
            case .add:
                if sema.types.makeNonNullable(propType) == stringType || valueType == stringType {
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

        if let scopeVisibleObject = candidates.first(where: { $0.kind == .object }),
           let objectType = resolveTypeForCandidate(scopeVisibleObject, sema: sema)
        {
            return inferObjectCompoundAssignExpr(
                id,
                op: op,
                valueExpr: valueExpr,
                originalValueType: valueType,
                objectSymbol: scopeVisibleObject,
                receiverType: objectType,
                range: range,
                ctx: ctx,
                locals: &locals
            )
        }

        if !dslBlockedIDs.isEmpty {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-DSLMARKER",
                "'@DslMarker' implicit access to '\(interner.resolve(name))' from outer receiver is restricted. Use explicit receiver.",
                range: range
            )
        } else if name == KnownCompilerNames(interner: interner).field {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-FIELD",
                "'field' can only be used inside a property getter or setter body.",
                range: range
            )
        } else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0013",
                "Unresolved local variable '\(interner.resolve(name))'.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.errorType)
        return sema.types.errorType
    }

    /// Reserve the expression's call binding for its arithmetic operator;
    /// lowering reads and writes the selected property.
    private func resolveExtensionPropertyForCompoundAssignment(
        id: ExprID,
        named calleeName: InternedString,
        receiverType: TypeID,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> MemberPropertyLookupResult? {
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
        return MemberPropertyLookupResult(
            symbol: property,
            type: propertyType,
            writeSymbol: sema.symbols.symbol(property)?.flags.contains(.mutable) == true ? property : nil
        )
    }

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
        let originalValueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: nil)

        let nonNullReceiver = sema.types.makeNonNullable(receiverType)
        guard let propResult = driver.helpers.lookupMemberPropertyForWrite(
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
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0022",
                "Unresolved reference '\(interner.resolve(calleeName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }

        let writeSymbol = propResult.writeSymbol ?? propResult.symbol
        let isMutable = propResult.writeSymbol != nil
        sema.bindings.bindIdentifier(id, symbol: writeSymbol)
        let propType = propResult.type
        let valueType = contextualCompoundAssignmentValueType(
            op: op, receiverType: propType, valueExpr: valueExpr,
            originalType: originalValueType, range: range, ctx: ctx, locals: &locals
        )
        let propSymbol = sema.symbols.symbol(writeSymbol)
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
                diagnostics: ctx.sema.diagnostics
            )
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }
        driver.helpers.checkOptIn(
            for: writeSymbol, ctx: ctx, range: range, diagnostics: ctx.sema.diagnostics
        )
        if let cachedValue = ctx.ast.arena.incrementDecrementCachedValue(for: id) {
            _ = driver.inferExpr(cachedValue, ctx: ctx, locals: &locals, expectedType: propType)
        }

        if let resolvedType = inferIncrementDecrementIfNeeded(
            exprID: id,
            op: op,
            receiverType: propType,
            assignmentType: propType,
            isMutable: isMutable,
            range: range,
            locals: locals,
            ctx: ctx
        ) {
            if isMutable, !checkPropertySetterAccessibility(propertyID: writeSymbol, name: calleeName, range: range, ctx: ctx) {
                return driver.helpers.bindAndReturnErrorType(id, sema: sema)
            }
            return resolvedType.expressionType
        }

        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: propType,
            valueType: valueType,
            range: range,
            locals: locals,
            ctx: ctx,
            requireUnitReturn: true
        ) {
            if isMutable,
               isPropertySetterAccessible(propertyID: writeSymbol, ctx: ctx),
               let binaryFallback = bindCompoundAssignmentOperatorCall(
                   exprID: id,
                   op: op,
                   receiverType: propType,
                   valueType: valueType,
                   range: range,
                   locals: locals,
                   ctx: ctx,
                   requireUnitReturn: false,
                   emitDiagnostics: false,
                   bindCall: false
               ),
               binaryFallback != sema.types.errorType
            {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0302",
                    "Assignment operator is ambiguous because both '\(interner.resolve(operatorFunctionNames(for: op, interner: interner)[0]))' and the corresponding binary operator are applicable.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            return resolvedType
        }

        // A successful `plusAssign` mutates the value returned by the getter
        // without invoking the property setter. Setter visibility only gates
        // the binary-operator fallback that writes a replacement value.
        if isMutable, !checkPropertySetterAccessibility(propertyID: writeSymbol, name: calleeName, range: range, ctx: ctx) {
            return driver.helpers.bindAndReturnErrorType(id, sema: sema)
        }

        if let resolvedType = bindCompoundAssignmentOperatorCall(
            exprID: id,
            op: op,
            receiverType: propType,
            valueType: valueType,
            range: range,
            locals: locals,
            ctx: ctx,
            requireUnitReturn: false
        ) {
            if resolvedType == sema.types.errorType || !isMutable {
                if !isMutable, resolvedType != sema.types.errorType {
                    ctx.sema.diagnostics.error(
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

        // Unlike a bare local, a property's declared type doesn't get narrowed
        // per-assignment, so there is nothing to propagate back into `locals` here.
        if rejectInvalidBuiltinCharCompoundAssignment(
            id, op: op, lhs: propType, rhs: valueType, range: range, ctx: ctx
        ) {
            return sema.types.errorType
        }
        let underlyingOp = driver.helpers.compoundAssignToBinaryOp(op)
        guard isBuiltinCompoundAssignOperand(op: op, lhs: propType, rhs: valueType, sema: sema) else {
            let operatorName = operatorFunctionNames(for: underlyingOp, interner: interner)[0]
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for operator '\(interner.resolve(operatorName))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if !isMutable {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0014",
                "Val cannot be reassigned.",
                range: range
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    private func isPropertySetterAccessible(
        propertyID: SymbolID,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        guard let setterVisibility = sema.symbols.propertySetterVisibility(for: propertyID),
              let propSymbol = sema.symbols.symbol(propertyID)
        else {
            return true
        }
        let setter = SemanticSymbol(
            id: propSymbol.id, kind: propSymbol.kind, name: propSymbol.name, fqName: propSymbol.fqName,
            declSite: propSymbol.declSite, visibility: setterVisibility, flags: propSymbol.flags
        )
        return ctx.visibilityChecker.isAccessible(
            setter, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
        )
    }

    @discardableResult
    private func checkPropertySetterAccessibility(
        propertyID: SymbolID,
        name: InternedString,
        range: SourceRange,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        guard let setterVisibility = sema.symbols.propertySetterVisibility(for: propertyID),
              let propSymbol = sema.symbols.symbol(propertyID)
        else {
            return true
        }
        let setter = SemanticSymbol(
            id: propSymbol.id, kind: propSymbol.kind, name: propSymbol.name, fqName: propSymbol.fqName,
            declSite: propSymbol.declSite, visibility: setterVisibility, flags: propSymbol.flags
        )
        if !ctx.visibilityChecker.isAccessible(
            setter, fromFile: ctx.currentFileID, enclosingClass: ctx.enclosingClassSymbol
        ) {
            driver.helpers.emitVisibilityError(
                for: setter,
                name: ctx.interner.resolve(name),
                range: range,
                diagnostics: sema.diagnostics
            )
            return false
        }
        return true
    }
}
