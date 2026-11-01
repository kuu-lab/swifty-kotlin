
final class ControlFlowTypeChecker {
    unowned let driver: TypeCheckDriver

    private struct ResolvedLoopOperator {
        let call: ResolvedCall
        let dispatchReceiverSymbol: SymbolID?
    }

    init(driver: TypeCheckDriver) {
        self.driver = driver
    }

    func inferLoopElementType(
        exprID: ExprID,
        iterableExpr: ExprID,
        iterableType: TypeID,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> TypeID {
        let sema = ctx.sema
        if iterableType == sema.types.errorType {
            return sema.types.errorType
        }
        guard sema.types.nullability(of: iterableType) != .nullable else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0172",
                "The for-loop cannot iterate over a nullable receiver.",
                range: ctx.ast.arena.exprRange(iterableExpr) ?? range
            )
            return sema.types.errorType
        }
        let isRangeExpr = Self.isRangeExpression(iterableExpr, ast: ctx.ast)
            || sema.bindings.isRangeExpr(iterableExpr)
        if let elementType = bindLoopIterationOperators(
            exprID: exprID, iterableExpr: iterableExpr, iterableType: iterableType,
            range: range, locals: locals, ctx: ctx
        ) {
            return elementType
        }
        // The legacy range-element fallback bypasses iterator convention
        // lookup, so floating-point ranges may use it only after a real
        // iterator operator was bound above.
        if !sema.bindings.isFloatingPointRangeExpr(iterableExpr),
           let elementType = driver.helpers.iterableElementType(
            for: iterableType,
            isRangeExpr: isRangeExpr,
            isCharRangeExpr: sema.bindings.isCharRangeExpr(iterableExpr),
            sema: sema,
            interner: ctx.interner
           )
        {
            return elementType
        }
        ctx.sema.diagnostics.error(
            "KSWIFTK-SEMA-0172",
            "The for-loop must have an 'iterator()' method.",
            range: ctx.ast.arena.exprRange(iterableExpr) ?? range
        )
        return sema.types.errorType
    }

    func bindLoopIterationOperators(
        exprID: ExprID,
        iterableExpr: ExprID,
        iterableType: TypeID,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let interner = ctx.interner
        let nonNullIterableType = sema.types.makeNonNullable(iterableType)

        switch sema.types.kind(of: nonNullIterableType) {
        case .classType, .typeParam, .intersection:
            break
        case .primitive:
            // Primitive receivers (e.g. `for (i in 1)`) cannot carry members,
            // but a user extension such as `operator fun <T : Any>
            // T?.iterator()` still applies — its nullable type-parameter
            // receiver admits the non-null value (KUU-3583). A primitive type
            // may still be a scalar range handle (`1..5` lowered as Int), so
            // range-marked iterables keep their dedicated path.
            guard !sema.bindings.isRangeExpr(iterableExpr),
                  !sema.bindings.isCharRangeExpr(iterableExpr),
                  !sema.bindings.isUIntRangeExpr(iterableExpr),
                  !sema.bindings.isULongRangeExpr(iterableExpr),
                  !sema.bindings.isFloatingPointRangeExpr(iterableExpr),
                  !Self.isRangeExpression(iterableExpr, ast: ctx.ast)
            else {
                return nil
            }
        default:
            return nil
        }

        // Arrays already have an indexed lowering that avoids allocating the
        // stdlib iterator object. Leave their source-backed iterator
        // extensions to that established path.
        if ReceiverClassifier(sema: sema, interner: interner).isArrayLikeType(nonNullIterableType) {
            return nil
        }

        let iteratorName = interner.intern("iterator")
        let iteratorResolution = resolveLoopOperator(
            named: iteratorName,
            receiverType: nonNullIterableType,
            range: range,
            excludesUnbackedSynthetic: true,
            locals: locals,
            ctx: ctx
        )
        let iteratorCall: CallBinding?
        let iteratorType: TypeID
        if let iteratorResolution {
            if let diagnostic = iteratorResolution.call.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
                return sema.types.errorType
            }

            guard let iteratorChosen = iteratorResolution.call.chosenCallee,
                  let iteratorSignature = sema.symbols.functionSignature(for: iteratorChosen)
            else {
                return nil
            }

            let resolvedIteratorType = substituteResolvedType(
                iteratorSignature.returnType,
                signature: iteratorSignature,
                substitutedTypeArguments: iteratorResolution.call.substitutedTypeArguments,
                sema: sema
            )
            if isDirectIteratorType(nonNullIterableType, sema: sema, interner: interner),
               isStdlibIteratorIdentityExtension(iteratorChosen, sema: sema, interner: interner)
            {
                // The stdlib's Iterator<T>.iterator() is an identity
                // extension. Keep the existing direct-iterator fast path,
                // while allowing more-specific user extensions to bind above.
                iteratorCall = nil
                iteratorType = nonNullIterableType
            } else {
                iteratorCall = makeLoopOperatorCallBinding(
                    from: iteratorResolution,
                    chosenCallee: iteratorChosen
                )
                iteratorType = resolvedIteratorType
            }
        } else if isDirectIteratorType(nonNullIterableType, sema: sema, interner: interner) {
            // Iterator<T> already is the iterator; the stdlib extension
            // Iterator<T>.iterator() returns this, so skip the call and
            // use hasNext()/next() directly on the iterable value.
            iteratorCall = nil
            iteratorType = nonNullIterableType
        } else {
            return nil
        }

        let hasNextName = interner.intern("hasNext")
        let nextName = interner.intern("next")
        let hasNextResolution = resolveLoopOperator(
            named: hasNextName,
            receiverType: iteratorType,
            range: range,
            excludesUnbackedSynthetic: false,
            locals: locals,
            ctx: ctx
        )
        let nextResolution = resolveLoopOperator(
            named: nextName,
            receiverType: iteratorType,
            range: range,
            excludesUnbackedSynthetic: false,
            locals: locals,
            ctx: ctx
        )

        // `iterator()` bound, so the for-loop convention is committed: its
        // return type must now provide operator hasNext()/next(). Falling
        // back to the structural element-type guesses here would silently
        // accept `operator fun iterator() = 1` (kotlinc: 'hasNext()' cannot
        // be called on 'iterator()').
        let iterableRange = ctx.ast.arena.exprRange(iterableExpr) ?? range
        guard let hasNextResolution, let nextResolution else {
            reportMissingLoopIteratorConvention(
                missingHasNext: hasNextResolution == nil,
                missingNext: nextResolution == nil,
                iteratorType: iteratorType,
                range: iterableRange,
                locals: locals,
                ctx: ctx
            )
            return sema.types.errorType
        }

        if let diagnostic = hasNextResolution.call.diagnostic ?? nextResolution.call.diagnostic {
            ctx.sema.diagnostics.emit(diagnostic)
            return sema.types.errorType
        }

        let hasNextChosen = hasNextResolution.call.chosenCallee
        let nextChosen = nextResolution.call.chosenCallee
        let nextSignature = nextChosen.flatMap { sema.symbols.functionSignature(for: $0) }
        guard let hasNextChosen, let nextChosen, let nextSignature else {
            reportMissingLoopIteratorConvention(
                missingHasNext: hasNextChosen == nil,
                missingNext: nextSignature == nil,
                iteratorType: iteratorType,
                range: iterableRange,
                locals: locals,
                ctx: ctx
            )
            return sema.types.errorType
        }

        let hasNextCall = makeLoopOperatorCallBinding(
            from: hasNextResolution,
            chosenCallee: hasNextChosen
        )
        let nextCall = makeLoopOperatorCallBinding(
            from: nextResolution,
            chosenCallee: nextChosen
        )

        let elementType = TypeCheckHelpers().mapEntryElementType(
            for: nonNullIterableType,
            sema: sema,
            interner: interner
        ) ?? substituteResolvedType(
            nextSignature.returnType,
            signature: nextSignature,
            substitutedTypeArguments: nextResolution.call.substitutedTypeArguments,
            sema: sema
        )

        sema.bindings.bindLoopIteration(
            exprID,
            binding: LoopIterationBinding(
                iteratorCall: iteratorCall,
                hasNextCall: hasNextCall,
                nextCall: nextCall,
                iteratorType: iteratorType,
                elementType: elementType
            )
        )
        return elementType
    }

    private func resolveLoopOperator(
        named calleeName: InternedString,
        receiverType: TypeID,
        range: SourceRange,
        excludesUnbackedSynthetic: Bool,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> ResolvedLoopOperator? {
        let sema = ctx.sema
        func isZeroArgumentOperator(_ candidate: SymbolID) -> Bool {
            guard let symbol = sema.symbols.symbol(candidate),
                  symbol.flags.contains(.operatorFunction),
                  let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.isEmpty,
                  !symbol.flags.contains(.synthetic)
                    || !excludesUnbackedSynthetic
                    || sema.symbols.isSourceBackedSymbol(candidate)
            else {
                return false
            }
            return true
        }

        let receiverCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: calleeName,
            receiverType: receiverType,
            sema: sema,
            interner: ctx.interner
        )
        let directCandidates = receiverCandidates.filter { candidate in
            sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil
                && isZeroArgumentOperator(candidate)
        }
        let visibleDirectCandidates = ctx.filterByVisibility(directCandidates).visible
        if !visibleDirectCandidates.isEmpty {
            let call = CallExpr(range: range, calleeName: calleeName, args: [])
            return ResolvedLoopOperator(
                call: ctx.resolver.resolveCall(
                    candidates: visibleDirectCandidates,
                    call: call,
                    expectedType: nil,
                    implicitReceiverType: receiverType,
                    ctx: sema
                ),
                dispatchReceiverSymbol: nil
            )
        }

        for dispatchReceiver in ctx.implicitReceiverMemberLookupEntries() {
            let candidates = driver.helpers.collectMemberFunctionCandidates(
                named: calleeName,
                receiverType: dispatchReceiver.type,
                sema: sema,
                interner: ctx.interner
            ).filter { candidate in
                sema.symbols.memberExtensionOwnerSymbol(for: candidate) != nil
                    && isZeroArgumentOperator(candidate)
            }
            let dslVisibleCandidates = candidates.filter { !ctx.isCandidateBlockedByDslMarker($0) }
            let visibleCandidates = ctx.filterByVisibility(dslVisibleCandidates).visible
            guard !visibleCandidates.isEmpty else {
                continue
            }

            let call = CallExpr(
                range: range,
                calleeName: calleeName,
                args: [],
                dispatchReceiverTypes: [dispatchReceiver.type]
            )
            let viableCandidates = ctx.resolver.probeCall(
                candidates: visibleCandidates,
                call: call,
                expectedType: nil,
                implicitReceiverType: receiverType,
                ctx: sema
            ).viableCandidates.map(\.symbol)
            guard !viableCandidates.isEmpty else {
                continue
            }

            let resolved = ctx.resolver.resolveCall(
                candidates: viableCandidates,
                call: call,
                expectedType: nil,
                implicitReceiverType: receiverType,
                preserveMemberExtensionAmbiguity: true,
                ctx: sema
            )
            if resolved.chosenCallee != nil || resolved.diagnostic != nil {
                return ResolvedLoopOperator(
                    call: resolved,
                    dispatchReceiverSymbol: dispatchReceiver.symbol
                )
            }
        }

        // Top-level extensions (including locally declared extensions) are
        // part of Kotlin's operator convention lookup after real members and
        // implicit-receiver member extensions. Reuse ordinary extension-call
        // candidate collection so imports, visibility, and receiver
        // applicability follow the same rules as `receiver.iterator()`.
        let extensionCandidates = driver.callChecker.collectExtensionCallCandidates(
            named: calleeName,
            memberLookupType: receiverType,
            isSuperCall: false,
            supertypeSymbols: [],
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: ctx.interner
        ).filter { candidate in
            sema.symbols.memberExtensionOwnerSymbol(for: candidate) == nil
                && isZeroArgumentOperator(candidate)
        }
        let visibleExtensionCandidates = ctx.filterByVisibility(extensionCandidates).visible
        if !visibleExtensionCandidates.isEmpty {
            let call = CallExpr(range: range, calleeName: calleeName, args: [])
            return ResolvedLoopOperator(
                call: ctx.resolver.resolveCall(
                    candidates: visibleExtensionCandidates,
                    call: call,
                    expectedType: nil,
                    implicitReceiverType: receiverType,
                    ctx: sema
                ),
                dispatchReceiverSymbol: nil
            )
        }
        return nil
    }

    /// `iterator()` resolved but its return type lacks a callable operator
    /// `hasNext()`/`next()`. A present-but-non-`operator` member or extension
    /// reports kotlinc's "'operator' modifier is required" instead of the
    /// missing-candidate "'<name>()' cannot be called on 'iterator()'".
    private func reportMissingLoopIteratorConvention(
        missingHasNext: Bool,
        missingNext: Bool,
        iteratorType: TypeID,
        range: SourceRange,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) {
        let sema = ctx.sema
        for (missing, convention) in [(missingHasNext, "hasNext"), (missingNext, "next")] where missing {
            let name = ctx.interner.intern(convention)
            if hasNonOperatorLoopConventionCandidate(named: name, receiverType: iteratorType, locals: locals, ctx: ctx) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0432",
                    "'operator' modifier is required on '\(convention)' in '\(driver.helpers.conventionReceiverDisplayName(iteratorType, sema: sema, interner: ctx.interner))'.",
                    range: range
                )
            } else {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0172",
                    "'\(convention)()' cannot be called on 'iterator()'.",
                    range: range
                )
            }
        }
    }

    private func hasNonOperatorLoopConventionCandidate(
        named name: InternedString,
        receiverType: TypeID,
        locals: LocalBindings,
        ctx: TypeInferenceContext
    ) -> Bool {
        let sema = ctx.sema
        let memberCandidates = driver.helpers.collectMemberFunctionCandidates(
            named: name,
            receiverType: receiverType,
            sema: sema,
            interner: ctx.interner
        )
        if memberCandidates.contains(where: {
            driver.helpers.isNonOperatorConventionFunction($0, sema: sema)
        }) {
            return true
        }
        let extensionCandidates = driver.callChecker.collectExtensionCallCandidates(
            named: name,
            memberLookupType: receiverType,
            isSuperCall: false,
            supertypeSymbols: [],
            ctx: ctx,
            locals: locals,
            sema: sema,
            interner: ctx.interner
        )
        return extensionCandidates.contains {
            driver.helpers.isNonOperatorConventionFunction($0, sema: sema)
        }
    }

    private func makeLoopOperatorCallBinding(
        from resolution: ResolvedLoopOperator,
        chosenCallee: SymbolID
    ) -> CallBinding {
        CallBinding(
            chosenCallee: chosenCallee,
            substitutedTypeArguments: resolution.call.substitutedTypeArguments
                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                .map { _, value in value },
            parameterMapping: resolution.call.parameterMapping,
            defaultArgumentOwner: resolution.call.defaultArgumentOwner,
            dispatchReceiverSymbol: resolution.dispatchReceiverSymbol
        )
    }

    private func substituteResolvedType(
        _ type: TypeID,
        signature: FunctionSignature,
        substitutedTypeArguments: [TypeVarID: TypeID],
        sema: SemaModule
    ) -> TypeID {
        let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
        return sema.types.substituteTypeParameters(
            in: type,
            substitution: substitutedTypeArguments,
            typeVarBySymbol: typeVarBySymbol
        )
    }

    private func isDirectIteratorType(
        _ type: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let iteratorFQName = [
            interner.intern("kotlin"),
            interner.intern("collections"),
            interner.intern("Iterator")
        ]
        guard let iteratorSymbol = sema.symbols.lookup(fqName: iteratorFQName) else {
            return false
        }
        let iteratorType = sema.types.make(.classType(ClassType(
            classSymbol: iteratorSymbol,
            args: [.star],
            nullability: .nonNull
        )))
        return sema.types.isSubtype(sema.types.makeNonNullable(type), iteratorType)
    }

    private func isStdlibIteratorIdentityExtension(
        _ candidate: SymbolID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        let expectedFQName = ["kotlin", "collections", "iterator"].map(interner.intern)
        let iteratorFQName = ["kotlin", "collections", "Iterator"].map(interner.intern)
        guard sema.symbols.symbol(candidate)?.fqName == expectedFQName,
              sema.symbols.symbol(candidate)?.flags.contains(.inlineFunction) == true,
              let iteratorSymbol = sema.symbols.lookup(fqName: iteratorFQName),
              let signature = sema.symbols.functionSignature(for: candidate),
              let receiverType = signature.receiverType,
              resolveClassTypeSymbol(receiverType, sema: sema)?.symbol.id == iteratorSymbol
        else {
            return false
        }
        return true
    }

    func inferForExpr(
        _ id: ExprID,
        loopVariable: InternedString?,
        iterableExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let sema = ctx.sema
        let inferredIterableType = driver.inferExpr(iterableExpr, ctx: ctx, locals: &locals, expectedType: nil)
        // Floating-point ranges keep an Int scalar representation for lowering,
        // but for-in convention lookup must use their source-level range type.
        // Otherwise the integer-range fallback accepts them without checking
        // that an `iterator()` operator exists.
        let iterableType: TypeID
        if sema.bindings.isFloatingPointRangeExpr(iterableExpr),
           let sourceLevelRangeType = driver.callChecker.floatingPointRangeArgumentType(
               iterableExpr,
               ast: ctx.ast,
               sema: sema,
               interner: ctx.interner
           )
        {
            iterableType = sourceLevelRangeType
        } else {
            iterableType = inferredIterableType
        }
        let elementType = inferLoopElementType(
            exprID: id, iterableExpr: iterableExpr, iterableType: iterableType,
            range: range, locals: locals, ctx: ctx
        )
        // An explicit `for (c: T in xs)` annotation must accept the iterator
        // element type; kotlinc reports an initializer type mismatch.
        let declaredLoopType = ctx.ast.arena.forVariableTypeRef(for: id).map {
            driver.helpers.resolveTypeRef(
                $0, ast: ctx.ast, sema: sema, interner: ctx.interner,
                scope: ctx.scope, diagnostics: ctx.sema.diagnostics,
                inferenceContext: ctx, usageRange: range
            )
        }
        if let declaredLoopType {
            driver.emitSubtypeConstraint(
                left: elementType, right: declaredLoopType,
                range: range, solver: ConstraintSolver(),
                sema: sema, diagnostics: ctx.sema.diagnostics
            )
        }
        let loopValueType = declaredLoopType ?? elementType
        invalidateNullableControlFlowAssignments(id, ctx: ctx, locals: &locals)
        var bodyLocals = locals
        if let loopVariable {
            let loopVariableSymbol = sema.symbols.define(
                kind: .local,
                name: loopVariable,
                fqName: [
                    ctx.interner.intern("__for_\(id.rawValue)"),
                    loopVariable,
                ],
                declSite: range,
                visibility: .private,
                flags: []
            )
            // Only register primitive, enum, and value-class element types in the
            // symbol table; for complex types (e.g. IndexedValue<Char>) this
            // would change downstream lowering in ways that break field-access
            // codegen (kk_array_get_inbounds gets wrong indices). Value classes
            // are a single-field wrapper like a primitive at the ABI level, so
            // ValueClassUnboxingPass needs this type recorded to recognize
            // `for (box in list) { box.value }` as an unboxing site — without
            // it the loop variable falls back to Any and the property read
            // stays a raw kk_array_get_inbounds on the unboxed underlying value.
            // Enum name lowering likewise needs the enum identity on the loop
            // temporary to select its generated ordinal-to-name helper.
            let isNominalValueElement: Bool = {
                guard case let .classType(classType) = sema.types.kind(of: elementType),
                      classType.nullability == .nonNull,
                      let sym = sema.symbols.symbol(classType.classSymbol)
                else { return false }
                return sym.flags.contains(.valueType) || sym.kind == .enumClass
            }()
            if case .primitive(_, .nonNull) = sema.types.kind(of: loopValueType) {
                sema.symbols.setPropertyType(loopValueType, for: loopVariableSymbol)
            } else if isNominalValueElement {
                sema.symbols.setPropertyType(loopValueType, for: loopVariableSymbol)
            }
            bodyLocals[loopVariable] = (loopValueType, loopVariableSymbol, false, true)
            sema.bindings.bindIdentifier(id, symbol: loopVariableSymbol)
        }
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        let loopFlowScope = LoopControlFlowInferenceScope(label: label)
        var loopFlowScopes = ctx.loopFlowScopes
        loopFlowScopes.append(loopFlowScope)
        var bodyCtx = ctx.copying(
            loopDepth: ctx.loopDepth + 1,
            loopLabelStack: newLabelStack,
            loopFlowScopes: loopFlowScopes
        )
        // The loop body runs on its own locals copy; narrowing inside it cannot
        // leak to the enclosing conditional path.
        bodyCtx.isConditionallyEvaluated = false
        _ = driver.inferExpr(
            bodyExpr,
            ctx: bodyCtx,
            locals: &bodyLocals,
            expectedType: nil,
            isStatementContext: true
        )
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }

    func inferWhileExpr(
        _ id: ExprID,
        conditionExpr: ExprID,
        bodyExpr: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType
        invalidateNullableControlFlowAssignments(id, ctx: ctx, locals: &locals)
        let conditionType = driver.inferExpr(conditionExpr, ctx: ctx, locals: &locals, expectedType: boolType)
        driver.emitSubtypeConstraint(
            left: conditionType,
            right: boolType,
            range: ast.arena.exprRange(conditionExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.sema.diagnostics
        )
        let branch = ctx.dataFlow.branchOnCondition(
            conditionExpr, base: ctx.flowState.includingMembers(from: locals), locals: locals,
            ast: ast, sema: sema, interner: interner, scope: ctx.scope
        )
        var bodyLocals = locals
        driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &bodyLocals, sema: sema)
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        let loopFlowScope = LoopControlFlowInferenceScope(label: label)
        var loopFlowScopes = ctx.loopFlowScopes
        loopFlowScopes.append(loopFlowScope)
        var bodyCtx = ctx.copying(
            loopDepth: ctx.loopDepth + 1,
            loopLabelStack: newLabelStack,
            loopFlowScopes: loopFlowScopes,
            flowState: branch.trueState
        )
        bodyCtx.isConditionallyEvaluated = false
        _ = driver.inferExpr(
            bodyExpr,
            ctx: bodyCtx,
            locals: &bodyLocals,
            expectedType: nil,
            isStatementContext: true
        )
        var loopExitStates = loopFlowScope.breakLocalStates
        if !isConstantTrueCondition(conditionExpr, ast: ast),
           canCompleteNormally(conditionExpr, ctx: ctx)
        {
            loopExitStates.append(locals)
        }
        mergeDefiniteInitializationAcrossLoopExits(loopExitStates, into: &locals)
        let resultType = if isConstantTrueCondition(conditionExpr, ast: ast) && !containsBreakTargetingCurrentLoop(
            bodyExpr, loopLabelStack: [label], ast: ast, ctx: ctx
        ) {
            sema.types.nothingType
        } else {
            sema.types.unitType
        }
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    func inferDoWhileExpr(
        _ id: ExprID,
        bodyExpr: ExprID,
        conditionExpr: ExprID,
        label: InternedString?,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let boolType = sema.types.booleanType
        invalidateNullableControlFlowAssignments(id, ctx: ctx, locals: &locals)
        var newLabelStack = ctx.loopLabelStack
        if let label { newLabelStack.append(label) }
        let loopFlowScope = LoopControlFlowInferenceScope(label: label)
        var loopFlowScopes = ctx.loopFlowScopes
        loopFlowScopes.append(loopFlowScope)
        var bodyLocals = locals
        let loopScope = BlockScope(parent: ctx.scope, symbols: sema.symbols)
        let loopCtx = ctx.copying(
            scope: loopScope,
            loopDepth: ctx.loopDepth + 1,
            loopLabelStack: newLabelStack,
            loopFlowScopes: loopFlowScopes
        )
        var bodyCtx = loopCtx.copying(exportBlockLocalsForExpr: bodyExpr)
        bodyCtx.isConditionallyEvaluated = false
        _ = driver.inferExpr(
            bodyExpr,
            ctx: bodyCtx,
            locals: &bodyLocals,
            expectedType: nil,
            isStatementContext: true
        )
        let bodyCanReachCondition = canCompleteNormally(bodyExpr, ctx: loopCtx)
        var conditionEntryStates = loopFlowScope.continueLocalStates
        if bodyCanReachCondition {
            conditionEntryStates.append(bodyLocals)
        }
        var conditionLocals = conditionEntryStates.isEmpty
            ? bodyLocals
            : mergingLoopInitializationFacts(conditionEntryStates, into: bodyLocals)
        loopFlowScope.recordsJumps = !conditionEntryStates.isEmpty
        let conditionType = driver.inferExpr(
            conditionExpr,
            ctx: loopCtx.copying(scope: loopScope),
            locals: &conditionLocals,
            expectedType: boolType
        )
        driver.emitSubtypeConstraint(
            left: conditionType,
            right: boolType,
            range: ast.arena.exprRange(conditionExpr) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.sema.diagnostics
        )
        var loopExitStates = loopFlowScope.breakLocalStates
        if !isConstantTrueCondition(conditionExpr, ast: ast),
           !conditionEntryStates.isEmpty,
           canCompleteNormally(conditionExpr, ctx: loopCtx)
        {
            loopExitStates.append(conditionLocals)
        }
        mergeDefiniteInitializationAcrossLoopExits(loopExitStates, into: &locals)
        let hasCurrentLoopBreak = containsBreakTargetingCurrentLoop(
            conditionExpr, loopLabelStack: [label], ast: ast, ctx: ctx
        ) || containsBreakTargetingCurrentLoop(bodyExpr, loopLabelStack: [label], ast: ast, ctx: ctx)
        // Inline lambdas carry non-local loop jumps without contributing to
        // this loop's local-state records, so inspect those routes as well.
        let bodyCannotReachCondition = conditionEntryStates.isEmpty && !containsBreakTargetingCurrentLoop(
            bodyExpr, loopLabelStack: [label], ast: ast, ctx: ctx, includingContinues: true
        )
        let resultType = if !hasCurrentLoopBreak && (bodyCannotReachCondition || isConstantTrueCondition(conditionExpr, ast: ast)) {
            sema.types.nothingType
        } else {
            sema.types.unitType
        }
        sema.bindings.bindExprType(id, type: resultType)
        return resultType
    }

    private func mergingLoopInitializationFacts(
        _ states: [LocalBindings],
        into fallback: LocalBindings
    ) -> LocalBindings {
        guard !states.isEmpty else { return fallback }
        var merged = fallback
        for (name, local) in fallback {
            let initializedOnEveryPath = states.allSatisfy { state in
                guard let pathLocal = state[name], pathLocal.symbol == local.symbol else { return false }
                return pathLocal.isInitialized
            }
            merged[name] = (local.type, local.symbol, local.isMutable, initializedOnEveryPath)
        }
        return merged
    }

    private func mergeDefiniteInitializationAcrossLoopExits(
        _ exitStates: [LocalBindings],
        into locals: inout LocalBindings
    ) {
        guard !exitStates.isEmpty else { return }
        for (name, local) in locals where !local.isInitialized {
            let initializedOnEveryExit = exitStates.allSatisfy { state in
                guard let exitLocal = state[name], exitLocal.symbol == local.symbol else { return false }
                return exitLocal.isInitialized
            }
            if initializedOnEveryExit {
                locals[name] = (local.type, local.symbol, local.isMutable, true)
            }
        }
    }

    /// Loop-carried writes invalidate assignment facts on later iterations
    /// and break paths, regardless of the body's final type.
    func invalidateNullableControlFlowAssignments(_ expression: ExprID, ctx: TypeInferenceContext, locals: inout LocalBindings) {
        for (name, local) in locals where local.isMutable {
            guard let declaration = ctx.dataFlow.localDeclarations[local.symbol],
                  ctx.dataFlow.localStability.isReassigned(declaration, within: expression),
                  let declaredType = ctx.sema.symbols.propertyType(for: local.symbol),
                  ctx.sema.types.nullability(of: declaredType) == .nullable
            else { continue }
            locals[name] = (declaredType, local.symbol, local.isMutable, local.isInitialized)
            locals.invalidateMembers(root: local.symbol)
        }
    }

    func mergeNullableBranchAssignments(_ branches: [LocalBindings], sema: SemaModule, locals: inout LocalBindings) {
        guard !branches.isEmpty else { return }
        for (name, local) in locals where local.isMutable {
            guard let declaredType = sema.symbols.propertyType(for: local.symbol),
                  sema.types.nullability(of: declaredType) == .nullable
            else { continue }
            let types = branches.map { branch in
                branch[name].flatMap { $0.symbol == local.symbol ? $0.type : nil } ?? declaredType
            }
            locals[name] = (sema.types.lub(types), local.symbol, local.isMutable, local.isInitialized)
        }
    }

    private func isConstantTrueCondition(_ conditionExpr: ExprID, ast: ASTModule) -> Bool {
        guard let expr = ast.arena.expr(conditionExpr) else { return false }
        if case .boolLiteral(true, _) = expr { return true }
        return false
    }

    /// Returns true if `exprID` has a break that can exit the loop at the bottom
    /// of `loopLabelStack` (index 0). The stack is ordered from the loop being
    /// checked outwards, so nested loops are appended. A non-completing `finally`
    /// suppresses breaks from its try/catch paths.
    private func containsBreakTargetingCurrentLoop(
        _ exprID: ExprID,
        loopLabelStack: [InternedString?],
        ast: ASTModule,
        ctx: TypeInferenceContext,
        includingContinues: Bool = false
    ) -> Bool {
        func visit(_ exprID: ExprID, loopLabelStack: [InternedString?]) -> Bool {
            guard let expr = ast.arena.expr(exprID) else { return false }
            switch expr {
            case .breakExpr(let label, _), .continueExpr(let label, _):
                if case .continueExpr = expr, !includingContinues { return false }
                let targetIndex: Int
                if let label {
                    if let idx = loopLabelStack.lastIndex(where: { $0 == label }) {
                        targetIndex = idx
                    } else {
                        return false
                    }
                } else {
                    targetIndex = loopLabelStack.count - 1
                }
                return targetIndex == 0
            case .forExpr(_, let iterable, let body, let label, _):
                if visit(iterable, loopLabelStack: loopLabelStack) { return true }
                var nestedStack = loopLabelStack
                nestedStack.append(label)
                return visit(body, loopLabelStack: nestedStack)
            case .whileExpr(let condition, let body, let label, _):
                // A while condition runs before entering the loop body, so an
                // unlabelled jump there targets an enclosing loop.
                if visit(condition, loopLabelStack: loopLabelStack) { return true }
                var nestedStack = loopLabelStack
                nestedStack.append(label)
                return visit(body, loopLabelStack: nestedStack)
            case .doWhileExpr(let body, let condition, let label, _):
                var nestedStack = loopLabelStack
                nestedStack.append(label)
                if visit(body, loopLabelStack: nestedStack) { return true }
                return visit(condition, loopLabelStack: nestedStack)
            case .forDestructuringExpr(_, let iterable, let body, _, _):
                if visit(iterable, loopLabelStack: loopLabelStack) { return true }
                var nestedStack = loopLabelStack
                nestedStack.append(ast.arena.loopLabel(for: exprID))
                return visit(body, loopLabelStack: nestedStack)
            case .ifExpr(let condition, let thenExpr, let elseExpr, _):
                if visit(condition, loopLabelStack: loopLabelStack) { return true }
                if visit(thenExpr, loopLabelStack: loopLabelStack) { return true }
                if let elseExpr, visit(elseExpr, loopLabelStack: loopLabelStack) { return true }
                return false
            case .whenExpr(let subject, let branches, let elseExpr, _):
                if let subject, visit(subject, loopLabelStack: loopLabelStack) { return true }
                for branch in branches {
                    for condition in branch.conditions {
                        if visit(condition, loopLabelStack: loopLabelStack) { return true }
                    }
                    if let guardExpr = branch.guard_, visit(guardExpr, loopLabelStack: loopLabelStack) { return true }
                    if visit(branch.body, loopLabelStack: loopLabelStack) { return true }
                }
                if let elseExpr, visit(elseExpr, loopLabelStack: loopLabelStack) { return true }
                return false
            case .tryExpr(let body, let catchClauses, let finallyExpr, _):
                if let finallyExpr, !canCompleteNormally(finallyExpr, ctx: ctx) {
                    return visit(finallyExpr, loopLabelStack: loopLabelStack)
                }
                if visit(body, loopLabelStack: loopLabelStack) { return true }
                for clause in catchClauses {
                    if visit(clause.body, loopLabelStack: loopLabelStack) { return true }
                }
                if let finallyExpr, visit(finallyExpr, loopLabelStack: loopLabelStack) { return true }
                return false
            case .blockExpr(let statements, let trailingExpr, _):
                for statement in statements {
                    if visit(statement, loopLabelStack: loopLabelStack) { return true }
                }
                if let trailingExpr, visit(trailingExpr, loopLabelStack: loopLabelStack) { return true }
                return false
            case .returnExpr(let value, _, _):
                if let value, visit(value, loopLabelStack: loopLabelStack) { return true }
                return false
            case .throwExpr(let value, _):
                return visit(value, loopLabelStack: loopLabelStack)
            case .localDecl(_, _, _, let initializer, _, _, _):
                if let initializer, visit(initializer, loopLabelStack: loopLabelStack) { return true }
                return false
            case .localAssign(_, let value, _):
                return visit(value, loopLabelStack: loopLabelStack)
            case .memberAssign(let receiver, _, let value, _),
                 .safeMemberAssign(let receiver, _, let value, _):
                return visit(receiver, loopLabelStack: loopLabelStack) || visit(value, loopLabelStack: loopLabelStack)
            case .indexedAssign(let receiver, let indices, let value, _):
                if visit(receiver, loopLabelStack: loopLabelStack) { return true }
                for index in indices {
                    if visit(index, loopLabelStack: loopLabelStack) { return true }
                }
                return visit(value, loopLabelStack: loopLabelStack)
            case .call(let callee, _, let args, _),
                 .memberCall(let callee, _, _, let args, _),
                 .safeMemberCall(let callee, _, _, let args, _):
                if visit(callee, loopLabelStack: loopLabelStack) { return true }
                let binding = ctx.sema.bindings.callBinding(for: exprID)
                let inlineCallee = binding.flatMap { ctx.sema.symbols.symbol($0.chosenCallee) }?.flags.contains(.inlineFunction) == true
                let signature = binding.flatMap { ctx.sema.symbols.functionSignature(for: $0.chosenCallee) }
                return args.enumerated().contains { index, argument in
                    let parameter = binding?.parameterMapping[index] ?? index
                    let allowsJump = signature.map { !$0.valueParameterAllowsNonLocalReturn.indices.contains(parameter) || $0.valueParameterAllowsNonLocalReturn[parameter] } ?? false
                    if inlineCallee, allowsJump, case let .lambdaLiteral(_, body, _, _) = ast.arena.expr(argument.expr) {
                        return visit(body, loopLabelStack: loopLabelStack)
                    }
                    return visit(argument.expr, loopLabelStack: loopLabelStack)
                }
            case .indexedAccess(let receiver, let indices, _):
                if visit(receiver, loopLabelStack: loopLabelStack) { return true }
                return indices.contains { visit($0, loopLabelStack: loopLabelStack) }
            case .binary(_, let lhs, let rhs, _):
                return visit(lhs, loopLabelStack: loopLabelStack) || visit(rhs, loopLabelStack: loopLabelStack)
            case .unaryExpr(_, let operand, _), .isCheck(let operand, _, _, _),
                 .asCast(let operand, _, _, _), .nullAssert(let operand, _):
                return visit(operand, loopLabelStack: loopLabelStack)
            case .compoundAssign(_, _, let value, _):
                return visit(value, loopLabelStack: loopLabelStack)
            case .indexedCompoundAssign(_, let receiver, let indices, let value, _):
                if visit(receiver, loopLabelStack: loopLabelStack) { return true }
                for index in indices {
                    if visit(index, loopLabelStack: loopLabelStack) { return true }
                }
                return visit(value, loopLabelStack: loopLabelStack)
            case .memberCompoundAssign(_, let receiver, _, let value, _):
                return visit(receiver, loopLabelStack: loopLabelStack) || visit(value, loopLabelStack: loopLabelStack)
            case .inExpr(let lhs, let rhs, _), .notInExpr(let lhs, let rhs, _):
                return visit(lhs, loopLabelStack: loopLabelStack) || visit(rhs, loopLabelStack: loopLabelStack)
            case .destructuringDecl(_, _, let initializer, _):
                return visit(initializer, loopLabelStack: loopLabelStack)
            case .stringTemplate(let parts, _):
                for part in parts {
                    if case .expression(let expression) = part,
                       visit(expression, loopLabelStack: loopLabelStack) {
                        return true
                    }
                }
                return false
            case .lambdaLiteral, .localFunDecl, .localNominalDecl, .objectLiteral, .callableRef, .superRef, .thisRef:
                return false
            case .nullLiteral, .intLiteral, .longLiteral, .uintLiteral, .ulongLiteral, .floatLiteral, .doubleLiteral, .charLiteral, .boolLiteral, .stringLiteral, .nameRef:
                return false
            @unknown default:
                return false
            }
        }
        return visit(exprID, loopLabelStack: loopLabelStack)
    }

    func inferIfExpr(
        _ id: ExprID,
        condition: ExprID,
        thenExpr: ExprID,
        elseExpr: ExprID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        isStatementContext: Bool = false
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let boolType = sema.types.booleanType
        let conditionType = driver.inferExpr(condition, ctx: ctx, locals: &locals, expectedType: boolType)
        if conditionType != boolType {
            driver.emitSubtypeConstraint(
                left: conditionType,
                right: boolType,
                range: ast.arena.exprRange(condition),
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics
            )
        }
        let branch = ctx.dataFlow.branchOnCondition(
            condition, base: ctx.flowState.includingMembers(from: locals), locals: locals,
            ast: ast, sema: sema, interner: interner, scope: ctx.scope
        )
        var thenLocals = locals
        driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &thenLocals, sema: sema)
        var thenCtx = ctx.copying(flowState: branch.trueState)
        // Branch bodies run on their own locals copies, so narrowing inside
        // them cannot leak — the conditional-evaluation flag only guards the
        // enclosing linear scope.
        thenCtx.isConditionallyEvaluated = false
        var thenType = driver.inferExpr(thenExpr, ctx: thenCtx, locals: &thenLocals, expectedType: expectedType, isStatementContext: isStatementContext || elseExpr == nil)
        // A bare `ClassName` branch denotes the companion object; keep the
        // companion value type through the join (KUU-3232).
        thenType = driver.helpers.retypeClassNameAsCompanionValue(
            thenExpr, currentType: thenType, ast: ast, sema: sema
        ) ?? thenType
        var elseLocals = locals
        driver.exprChecker.applyFlowStateToLocals(branch.falseState, locals: &elseLocals, sema: sema)
        var elseCompletes = true
        let resolvedType: TypeID
        if let elseExpr {
            var elseCtx = ctx.copying(flowState: branch.falseState)
            elseCtx.isConditionallyEvaluated = false
            var elseType = driver.inferExpr(elseExpr, ctx: elseCtx, locals: &elseLocals, expectedType: expectedType, isStatementContext: isStatementContext)
            elseType = driver.helpers.retypeClassNameAsCompanionValue(
                elseExpr, currentType: elseType, ast: ast, sema: sema
            ) ?? elseType
            // A nested call in a branch can leave a type parameter
            // unresolved because it is only fixed by the sibling branch's
            // type — kotlinc solves both branches under one constraint
            // system. When a branch failed to infer, no contextual expected
            // type was provided, and the sibling produced a usable type,
            // retry the failing branch against that sibling type so
            // `if (b) OD<Boolean, Boolean>(false) else OD(false)` resolves.
            // Block bodies qualify through their value-producing tail
            // expression (KUU-3797).
            func retriableBranchExpr(_ expr: ExprID) -> Bool {
                var candidate = expr
                while case let .blockExpr(_, trailingExpr, _) = ast.arena.expr(candidate),
                      let trailingExpr
                {
                    candidate = trailingExpr
                }
                switch ast.arena.expr(candidate) {
                case .call, .memberCall, .ifExpr, .whenExpr, .tryExpr:
                    return true
                default:
                    return false
                }
            }
            if expectedType == nil, elseType == sema.types.errorType,
               thenType != sema.types.errorType, thenType != sema.types.nothingType,
               retriableBranchExpr(elseExpr)
            {
                // Drop the first pass's error diagnostics inside the branch
                // range up front: re-inference re-emits the ones that stay
                // genuine, while inference-dependent ones prove stale when
                // the retry succeeds (same restore pattern as KUU-3750).
                var removedDiagnostics: [Diagnostic] = []
                if let elseRange = ast.arena.exprRange(elseExpr) {
                    removedDiagnostics = ctx.sema.diagnostics.removeErrorDiagnostics(containedIn: elseRange)
                }
                let retryCheckpoint = ctx.sema.diagnostics.checkpoint()
                var retryLocals = locals
                driver.exprChecker.applyFlowStateToLocals(branch.falseState, locals: &retryLocals, sema: sema)
                let retried = driver.inferExpr(
                    elseExpr,
                    ctx: elseCtx,
                    locals: &retryLocals,
                    expectedType: thenType,
                    isStatementContext: isStatementContext
                )
                if retried != sema.types.errorType {
                    elseType = retried
                    elseLocals = retryLocals
                } else {
                    ctx.sema.diagnostics.rollback(to: retryCheckpoint)
                    for diagnostic in removedDiagnostics {
                        ctx.sema.diagnostics.emit(diagnostic)
                    }
                }
            }
            if expectedType == nil, thenType == sema.types.errorType,
               elseType != sema.types.errorType, elseType != sema.types.nothingType,
               retriableBranchExpr(thenExpr)
            {
                var removedDiagnostics: [Diagnostic] = []
                if let thenRange = ast.arena.exprRange(thenExpr) {
                    removedDiagnostics = ctx.sema.diagnostics.removeErrorDiagnostics(containedIn: thenRange)
                }
                let retryCheckpoint = ctx.sema.diagnostics.checkpoint()
                var retryLocals = locals
                driver.exprChecker.applyFlowStateToLocals(branch.trueState, locals: &retryLocals, sema: sema)
                let retried = driver.inferExpr(
                    thenExpr,
                    ctx: thenCtx,
                    locals: &retryLocals,
                    expectedType: elseType,
                    isStatementContext: isStatementContext
                )
                if retried != sema.types.errorType {
                    thenType = retried
                    thenLocals = retryLocals
                } else {
                    ctx.sema.diagnostics.rollback(to: retryCheckpoint)
                    for diagnostic in removedDiagnostics {
                        ctx.sema.diagnostics.emit(diagnostic)
                    }
                }
            }
            if let companionType = driver.helpers.retypeBranchClassObjectValue(
                thenExpr, currentType: thenType, ast: ast, sema: sema
            ) {
                thenType = companionType
            }
            if let companionType = driver.helpers.retypeBranchClassObjectValue(
                elseExpr, currentType: elseType, ast: ast, sema: sema
            ) {
                elseType = companionType
            }
            let joinedRangeType = bindJoinedRangeExpressionMetadata(
                id,
                thenExpr: thenExpr,
                thenType: thenType,
                elseExpr: elseExpr,
                elseType: elseType,
                ctx: ctx
            )
            let contextualizedTypes = contextualizeLongBranchLiterals(
                expressions: [thenExpr, elseExpr], types: [thenType, elseType], ctx: ctx
            )
            let inferredType = joinedRangeType ?? sema.types.lub(contextualizedTypes)
            resolvedType = contextualizeBranchJoin(
                inferredType,
                branchTypes: contextualizedTypes,
                expectedType: expectedType,
                ctx: ctx
            )
            // A branch typed `Nothing` (ends in `return`/`throw`/`break`/`continue`)
            // never completes normally, so it vacuously satisfies initialization:
            // control only reaches the code after the `if` through whichever
            // branch does complete.
            let thenCompletes = thenType != sema.types.nothingType
            elseCompletes = elseType != sema.types.nothingType
            for (name, local) in locals {
                if !local.isInitialized {
                    let thenOK = !thenCompletes || (thenLocals[name]?.isInitialized == true && thenLocals[name]?.symbol == local.symbol)
                    let elseOK = !elseCompletes || (elseLocals[name]?.isInitialized == true && elseLocals[name]?.symbol == local.symbol)
                    if thenOK, elseOK, thenCompletes || elseCompletes {
                        let reachingBranches = [
                            thenCompletes ? thenLocals : nil,
                            elseCompletes ? elseLocals : nil,
                        ].compactMap { $0 }
                        let joinedType = joinedInitializedLocalType(
                            name: name,
                            symbol: local.symbol,
                            from: reachingBranches,
                            fallback: local.type,
                            sema: sema
                        )
                        locals[name] = (joinedType, local.symbol, local.isMutable, true)
                    }
                }
            }
            let reachingBranchLocals = [
                thenCompletes ? thenLocals : nil,
                elseCompletes ? elseLocals : nil,
            ].compactMap { $0 }
            // Kotlin joins per-branch narrowing into the state after the `if`:
            // a local narrowed on every reaching branch keeps the join of those
            // narrowed types (e.g. `x === y` narrowing on one side and `x as T`
            // on the other leaves `x` at the tighter type afterwards).
            for (name, local) in locals {
                guard local.isInitialized else { continue }
                let branchTypes = reachingBranchLocals.compactMap { branch -> TypeID? in
                    guard let narrowed = branch[name], narrowed.symbol == local.symbol else {
                        return nil
                    }
                    return narrowed.type
                }
                guard branchTypes.count == reachingBranchLocals.count else { continue }
                let joinedType = sema.types.lub(branchTypes)
                if joinedType != local.type, joinedType != sema.types.errorType {
                    locals[name] = (joinedType, local.symbol, local.isMutable, local.isInitialized)
                }
            }
            locals.memberFlow = joinMemberFlow(from: reachingBranchLocals, base: locals.memberFlow)
            locals.joinVariableFacts(from: reachingBranchLocals)
        } else {
            // An `if` without `else` is a statement in Kotlin; using it where a
            // value is consumed must fail like kotlinc's INVALID_IF_AS_EXPRESSION.
            // Parenthesizing the `if` also makes it an expression even in an
            // otherwise-discarded statement slot (kotlinc rejects `(if (c) {})`
            // in every position).
            if !isStatementContext || ast.arena.isParenthesized(id) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0434",
                    "'if' must have both main and 'else' branches when used as an expression.",
                    range: ast.arena.exprRange(id)
                )
            }
            resolvedType = sema.types.unitType
            if thenType == sema.types.nothingType {
                // The then-branch never completes normally (return/throw/break/continue),
                // so control only reaches the code after this `if` via the implicit else
                // path, i.e. the negated condition. Apply that narrowed state so it survives
                // the fallthrough.
                driver.exprChecker.applyFlowStateToLocals(branch.falseState, locals: &locals, sema: sema)
            } else {
                locals.joinVariableFacts(from: [thenLocals, elseLocals])
            }
        }
        // Retain nullable-local assignment facts only on paths that can
        // reach the following statement. The implicit else path participates
        // too, so conditional initialization alone cannot prove non-nullness.
        for (name, local) in locals where local.isMutable {
            guard let declaredType = sema.symbols.propertyType(for: local.symbol),
                  sema.types.nullability(of: declaredType) == .nullable
            else { continue }
            var reachingTypes: [TypeID] = []
            if thenType != sema.types.nothingType,
               let thenLocal = thenLocals[name], thenLocal.symbol == local.symbol
            {
                reachingTypes.append(thenLocal.type)
            }
            if elseCompletes, let elseLocal = elseLocals[name], elseLocal.symbol == local.symbol {
                reachingTypes.append(elseLocal.type)
            }
            if !reachingTypes.isEmpty {
                locals[name] = (sema.types.lub(reachingTypes), local.symbol, local.isMutable, local.isInitialized)
            }
        }
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    func joinedInitializedLocalType(
        name: InternedString,
        symbol: SymbolID,
        from branches: [LocalBindings],
        fallback: TypeID,
        sema: SemaModule
    ) -> TypeID {
        guard !branches.isEmpty else { return fallback }
        let branchTypes = branches.compactMap { branch -> TypeID? in
            guard let local = branch[name], local.symbol == symbol, local.isInitialized else {
                return nil
            }
            return local.type
        }
        guard branchTypes.count == branches.count else { return fallback }
        return sema.types.lub(branchTypes)
    }

    func joinMemberFlow(
        from branches: [LocalBindings],
        base: [DataFlowReference: VariableFlowState]) -> [DataFlowReference: VariableFlowState] {
        guard !branches.isEmpty else { return base }
        if branches.count == 1 {
            return branches[0].memberFlow
        }
        var joined: [DataFlowReference: VariableFlowState] = [:]
        let firstBranch = branches[0]
        for (reference, firstState) in firstBranch.memberFlow {
            var allStates = [firstState]
            var presentInAll = true
            for otherBranch in branches.dropFirst() {
                if let otherState = otherBranch.memberFlow[reference] {
                    allStates.append(otherState)
                } else {
                    presentInAll = false
                    break
                }
            }
            guard presentInAll else { continue }
            var combinedTypes: Set<TypeID> = []
            var isNullable = false
            var isStable = true
            for s in allStates {
                combinedTypes.formUnion(s.possibleTypes)
                if s.nullability == .nullable { isNullable = true }
                if !s.isStable { isStable = false }
            }
            joined[reference] = VariableFlowState(
                possibleTypes: combinedTypes,
                nullability: isNullable ? .nullable : .nonNull,
                isStable: isStable
            )
        }
        return joined
    }

    private func bindJoinedRangeExpressionMetadata(
        _ resultExpr: ExprID,
        thenExpr: ExprID,
        thenType: TypeID,
        elseExpr: ExprID,
        elseType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        let branches: [(expr: ExprID, type: TypeID)] = [
            (thenExpr, thenType),
            (elseExpr, elseType),
        ].filter { $0.type != sema.types.nothingType }
        guard let first = branches.first,
              branches.allSatisfy({ sema.bindings.isRangeExpr($0.expr) })
        else {
            return nil
        }

        // `rangeTo` keeps the scalar Sema type while `rangeUntil` returns a
        // nominal range type. Normalize both through the call-argument view
        // before joining so an if-expression can retain the common range type.
        let sourceRangeTypes = branches.map {
            driver.callChecker.sourceLevelRangeArgumentType(
                $0.expr,
                inferredType: $0.type,
                ctx: ctx
            )
        }
        guard let resultType = sourceRangeTypes.first,
              sourceRangeTypes.allSatisfy({ $0 == resultType })
        else {
            return nil
        }

        let isCharRange = sema.bindings.isCharRangeExpr(first.expr)
        let isUIntRange = sema.bindings.isUIntRangeExpr(first.expr)
        let isULongRange = sema.bindings.isULongRangeExpr(first.expr)
        let isFloatingPointRange = sema.bindings.isFloatingPointRangeExpr(first.expr)
        guard branches.allSatisfy({
            sema.bindings.isCharRangeExpr($0.expr) == isCharRange
                && sema.bindings.isUIntRangeExpr($0.expr) == isUIntRange
                && sema.bindings.isULongRangeExpr($0.expr) == isULongRange
                && sema.bindings.isFloatingPointRangeExpr($0.expr) == isFloatingPointRange
        }) else {
            return nil
        }

        let floatingPointElementType = sema.bindings.floatingPointRangeElementType(forExpr: first.expr)
        let isOpenFloatingPointRange = sema.bindings.isOpenFloatingPointRangeExpr(first.expr)
        guard !isFloatingPointRange || branches.allSatisfy({
            sema.bindings.floatingPointRangeElementType(forExpr: $0.expr) == floatingPointElementType
                && sema.bindings.isOpenFloatingPointRangeExpr($0.expr) == isOpenFloatingPointRange
        }) else {
            return nil
        }

        sema.bindings.markRangeExpr(resultExpr)
        if isCharRange {
            sema.bindings.markCharRangeExpr(resultExpr)
        }
        if isUIntRange {
            sema.bindings.markUIntRangeExpr(resultExpr)
        }
        if isULongRange {
            sema.bindings.markULongRangeExpr(resultExpr)
        }
        if isFloatingPointRange, let floatingPointElementType {
            sema.bindings.bindFloatingPointRangeElementType(
                floatingPointElementType,
                forExpr: resultExpr,
                endExclusive: isOpenFloatingPointRange
            )
        }
        return resultType
    }

    func inferTryExpr(
        _ id: ExprID,
        body: ExprID,
        catchClauses: [CatchClause],
        finallyExpr: ExprID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        isStatementContext: Bool = false
    ) -> TypeID {
        let sema = ctx.sema
        let interner = ctx.interner
        let preTryLocals = locals
        var branchTypes: [TypeID] = []
        var normalCompletionLocals: [LocalBindings] = []
        // A discarded try expression is Unit-coerced by its statement
        // context. Do not push that Unit expectation into generic calls in
        // the branches, whose values are not used by the enclosing statement.
        let branchExpectedType = isStatementContext && expectedType == sema.types.unitType
            ? nil
            : expectedType
        var branchCtx = ctx
        if isStatementContext && expectedType == nil {
            // A discarded try expression does not provide a Unit result type
            // to generic calls nested in its branches.
            branchCtx.isUnitCoercionContext = false
        }
        // Try/catch bodies run on their own locals copies; narrowing inside
        // them cannot leak to the enclosing conditional path.
        branchCtx.isConditionallyEvaluated = false

        var tryBodyLocals = preTryLocals
        var tryBodyType = driver.inferExpr(
            body, ctx: branchCtx, locals: &tryBodyLocals,
            expectedType: branchExpectedType, isStatementContext: isStatementContext
        )
        if let companionType = driver.helpers.retypeBranchClassObjectValue(
            body, currentType: tryBodyType, ast: ctx.ast, sema: sema
        ) {
            tryBodyType = companionType
        }
        branchTypes.append(tryBodyType)
        if tryBodyType != sema.types.nothingType {
            normalCompletionLocals.append(tryBodyLocals)
        }

        for (index, clause) in catchClauses.enumerated() {
            var catchLocals = preTryLocals
            let catchParamType = resolveCatchClauseParameterType(
                clause.paramType,
                ctx: ctx,
                range: clause.range
            )
            var catchParamSymbol = SymbolID.invalid
            if let paramName = clause.paramName {
                catchParamSymbol = sema.symbols.define(
                    kind: .local,
                    name: paramName,
                    fqName: [
                        interner.intern("__try_\(id.rawValue)_catch_\(index)"),
                        paramName,
                    ],
                    declSite: clause.range,
                    visibility: .internal
                )
                sema.symbols.setPropertyType(catchParamType, for: catchParamSymbol)
                catchLocals[paramName] = (catchParamType, catchParamSymbol, false, true)
                sema.bindings.bindIdentifier(clause.body, symbol: catchParamSymbol)
            }
            sema.bindings.bindCatchClause(
                clause.body,
                binding: CatchClauseBinding(parameterSymbol: catchParamSymbol, parameterType: catchParamType)
            )
            var catchType = driver.inferExpr(
                clause.body, ctx: branchCtx, locals: &catchLocals,
                expectedType: branchExpectedType, isStatementContext: isStatementContext
            )
            if let companionType = driver.helpers.retypeBranchClassObjectValue(
                clause.body, currentType: catchType, ast: ctx.ast, sema: sema
            ) {
                catchType = companionType
            }
            branchTypes.append(catchType)
            if catchType != sema.types.nothingType {
                normalCompletionLocals.append(catchLocals)
            }
        }

        mergeNullableBranchAssignments(normalCompletionLocals, sema: sema, locals: &locals)

        if let finallyExpr {
            // Finally is always checked for side effects, but it does not participate in try-expr type inference.
            var finallyLocals = locals
            _ = driver.inferExpr(finallyExpr, ctx: ctx, locals: &finallyLocals, expectedType: nil, isStatementContext: true)
            locals = finallyLocals
        }

        if !normalCompletionLocals.isEmpty {
            for (name, local) in preTryLocals where !local.isInitialized {
                let initializedInAllNormalBranches = normalCompletionLocals.allSatisfy { branchLocals in
                    guard let branchLocal = branchLocals[name], branchLocal.symbol == local.symbol else {
                        return false
                    }
                    return branchLocal.isInitialized
                }
                guard initializedInAllNormalBranches else {
                    continue
                }
                let joinedType = joinedInitializedLocalType(
                    name: name,
                    symbol: local.symbol,
                    from: normalCompletionLocals,
                    fallback: local.type,
                    sema: sema
                )
                if let current = locals[name], current.symbol == local.symbol {
                    locals[name] = (joinedType, current.symbol, current.isMutable, true)
                } else {
                    locals[name] = (joinedType, local.symbol, local.isMutable, true)
                }
            }
        }

        let resolvedType = sema.types.lub(branchTypes)
        sema.bindings.bindExprType(id, type: resolvedType)
        return resolvedType
    }

    private func resolveCatchClauseParameterType(
        _ paramType: TypeRefID?,
        ctx: TypeInferenceContext,
        range: SourceRange?
    ) -> TypeID {
        let sema = ctx.sema
        guard let paramType else {
            return sema.types.anyType
        }
        // Route through the same type-reference resolution used by declarations
        // and `is`/`as` expressions so that import priority (explicit > wildcard
        // > default), aliases, and qualified names resolve identically here.
        var resolved = driver.helpers.resolveTypeRef(
            paramType,
            ast: ctx.ast,
            sema: sema,
            interner: ctx.interner,
            scope: ctx.scope,
            diagnostics: nil,
            inferenceContext: nil,
            usageRange: range
        )
        if resolved != sema.types.errorType,
           case let .named(path, _, _)? = ctx.ast.arena.typeRef(paramType),
           path.count > 1,
           !catchQualifiedCandidatesExist(path, ctx: ctx, sema: sema)
        {
            // resolveTypeRef falls back to last-segment short-name lookup even
            // for qualified references, so `unknown.Error` could bind a same-named
            // type in an unrelated package. Require a qualifier-consistent hit.
            resolved = sema.types.errorType
        }
        if resolved == sema.types.errorType {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0085",
                "Unresolved exception type '\(catchParamTypeDisplayName(paramType, ctx: ctx))' in catch clause.",
                range: range
            )
        } else if let throwableType = driver.helpers.throwableType(sema: sema, interner: ctx.interner),
                  !sema.types.isSubtype(resolved, throwableType)
        {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0413",
                "throwable type mismatch: actual type is '\(sema.types.displayName(of: resolved, symbols: sema.symbols, interner: ctx.interner))'.",
                range: range
            )
        }
        return resolved
    }

    private func catchQualifiedCandidatesExist(_ path: [InternedString], ctx: TypeInferenceContext, sema: SemaModule) -> Bool {
        func isTypeLike(_ symbolID: SymbolID) -> Bool {
            guard let symbol = sema.symbols.symbol(symbolID) else { return false }
            switch symbol.kind {
            case .class, .interface, .object, .enumClass, .annotationClass, .typeAlias:
                return true
            default:
                return false
            }
        }
        if sema.symbols.lookupAll(fqName: path).contains(where: isTypeLike) {
            return true
        }
        let scope = ctx.scope
        var current = scope.lookupClassifier(path[0], matching: isTypeLike)
        for component in path.dropFirst() {
            current = current.flatMap { ownerID -> [SymbolID] in
                guard let owner = sema.symbols.symbol(ownerID) else { return [] }
                return sema.symbols.lookupAll(fqName: owner.fqName + [component]).filter(isTypeLike)
            }
            if current.isEmpty {
                break
            }
        }
        return !current.isEmpty
    }

    private func catchParamTypeDisplayName(_ typeRef: TypeRefID, ctx: TypeInferenceContext) -> String {
        guard let ref = ctx.ast.arena.typeRef(typeRef) else {
            return "?"
        }
        switch ref {
        case let .named(path, _, _):
            return path.map { ctx.interner.resolve($0) }.joined(separator: ".")
        default:
            return "?"
        }
    }
}
