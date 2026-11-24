
extension LocalDeclTypeChecker {
    func isCanonicalAtomicArrayReceiver(
        _ receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> Bool {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return false
        }
        let atomicsPrefix: [InternedString] = [
            interner.intern("kotlin"),
            interner.intern("concurrent"),
            interner.intern("atomics"),
        ]
        guard symbol.fqName.starts(with: atomicsPrefix) else { return false }
        return symbol.name == interner.intern("AtomicIntArray")
            || symbol.name == interner.intern("AtomicLongArray")
            || symbol.name == interner.intern("AtomicArray")
    }

    func builtinArrayElementType(
        for receiverType: TypeID,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard let (_, symbol) = resolveClassTypeSymbol(receiverType, sema: sema) else {
            return nil
        }
        let names = KnownCompilerNames(interner: interner)
        let builtinArrayNames = [
            names.kotlinArrayFQName,
            names.kotlinIntArrayFQName,
            names.kotlinLongArrayFQName,
            names.kotlinShortArrayFQName,
            names.kotlinByteArrayFQName,
            names.kotlinUByteArrayFQName,
            names.kotlinUShortArrayFQName,
            names.kotlinUIntArrayFQName,
            names.kotlinULongArrayFQName,
            names.kotlinDoubleArrayFQName,
            names.kotlinFloatArrayFQName,
            names.kotlinBooleanArrayFQName,
            names.kotlinCharArrayFQName,
        ]
        guard builtinArrayNames.contains(symbol.fqName) else { return nil }
        return driver.helpers.arrayElementType(for: receiverType, sema: sema, interner: interner)
    }

    /// When the sole shape-matching get()/set() candidate expects a non-Int
    /// integer primitive (Long, UInt, ULong, Byte, Short) at `parameterIndex`
    /// and `indexExpr` is a bare integer literal, Kotlin contextualizes the
    /// literal to that parameter type instead of defaulting it to Int —
    /// mirroring the analogous adaptation already applied to the assigned
    /// value below (`setValueExpectedType`). Without this, `b[0]` against
    /// `operator fun get(position: Long)` infers the literal as Int,
    /// overload resolution then rejects the only candidate (Int is not a
    /// subtype of Long), and both Sema and KIR lowering silently fall back
    /// to treating `b` as a raw built-in array.
    func contextualIntegerLiteralExpectedType(
        candidates: [SymbolID],
        parameterIndex: Int,
        indexExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule
    ) -> TypeID? {
        guard driver.callChecker.isContextualizableIntegerLiteral(indexExpr, ast: ast) else {
            return nil
        }
        var paramTypes: [TypeID] = []
        for candidate in candidates {
            guard let signature = sema.symbols.functionSignature(for: candidate),
                  signature.parameterTypes.count > parameterIndex
            else {
                continue
            }
            paramTypes.append(sema.types.makeNonNullable(signature.parameterTypes[parameterIndex]))
        }
        guard paramTypes.count == 1,
              case let .primitive(primitive, _) = sema.types.kind(of: paramTypes[0])
        else {
            return nil
        }
        switch primitive {
        case .long, .uint, .ulong, .byte, .short:
            return paramTypes[0]
        default:
            return nil
        }
    }

    /// Preserves the source element type for an integer literal written
    /// directly through an unchecked `Array<Any>` view. The JVM compiler
    /// contextualizes this literal from the cast operand's `Array<Byte>`,
    /// `Array<Short>`, `Array<Int>`, or `Array<Long>` type; an array view
    /// returned across a function boundary has no such source expression.
    func uncheckedArrayViewIntegerLiteralExpectedType(
        receiverExpr: ExprID,
        receiverType: TypeID,
        valueExpr: ExprID,
        ast: ASTModule,
        sema: SemaModule,
        interner: StringInterner
    ) -> TypeID? {
        guard driver.callChecker.isContextualizableIntegerLiteral(valueExpr, ast: ast),
              case let .asCast(operand, _, isSafe, _) = ast.arena.expr(receiverExpr),
              !isSafe,
              let sourceType = sema.bindings.exprType(for: operand),
              let (sourceArray, sourceSymbol) = resolveClassTypeSymbol(sourceType, sema: sema),
              sourceSymbol.fqName == KnownCompilerNames(interner: interner).kotlinArrayFQName,
              let sourceElementType = sourceArray.args.first.flatMap({ argument -> TypeID? in
                  switch argument {
                  case let .invariant(type), let .out(type), let .in(type):
                      return type
                  case .star:
                      return nil
                  }
              }),
              let (viewArray, viewSymbol) = resolveClassTypeSymbol(receiverType, sema: sema),
              viewSymbol.fqName == KnownCompilerNames(interner: interner).kotlinArrayFQName,
              let viewElementType = viewArray.args.first.flatMap({ argument -> TypeID? in
                  switch argument {
                  case let .invariant(type), let .out(type), let .in(type):
                      return type
                  case .star:
                      return nil
                  }
              }),
              sema.types.makeNonNullable(viewElementType) == sema.types.anyType
        else {
            return nil
        }

        let nonNullSourceElementType = sema.types.makeNonNullable(sourceElementType)
        guard case let .primitive(primitive, _) = sema.types.kind(of: nonNullSourceElementType) else {
            return nil
        }
        switch primitive {
        case .byte, .short, .int, .long:
            return nonNullSourceElementType
        default:
            return nil
        }
    }

    private func nonNullSafeChainReceiverType(
        _ receiverExpr: ExprID,
        inferredReceiverType: TypeID,
        ctx: TypeInferenceContext
    ) -> TypeID? {
        let sema = ctx.sema
        guard !ctx.ast.arena.isParenthesized(receiverExpr) else { return nil }
        switch ctx.ast.arena.expr(receiverExpr) {
        case .safeMemberCall:
            let chosen = sema.bindings.callBinding(for: receiverExpr)?.chosenCallee
                ?? sema.bindings.identifierSymbol(for: receiverExpr)
            guard let chosen else { return nil }
            let memberResultType: TypeID?
            if let signature = sema.symbols.functionSignature(for: chosen) {
                memberResultType = signature.returnType
            } else {
                memberResultType = sema.symbols.propertyType(for: chosen)
            }
            guard let memberResultType,
                  sema.types.nullability(of: memberResultType) == .nonNull
            else { return nil }
            return sema.types.makeNonNullable(inferredReceiverType)
        case .indexedAccess:
            guard let valueType = sema.bindings.safeChainIndexedValueType(for: receiverExpr),
                  sema.types.nullability(of: valueType) == .nonNull
            else { return nil }
            return valueType
        default:
            return nil
        }
    }

    func inferIndexedAccessExpr(
        _ id: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        range: SourceRange,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        isSafeChain: Bool
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))

        var receiverCtx = ctx
        receiverCtx.isConditionallyEvaluated = ctx.receiverConditionallyEvaluated
        let inferredReceiverType = driver.inferExpr(receiverExpr, ctx: receiverCtx, locals: &locals, expectedType: nil)
        var effectiveIsSafeChain = isSafeChain
        var operatorReceiverType = inferredReceiverType
        if isSafeChain,
           let nonNullSafeReceiverType = nonNullSafeChainReceiverType(
               receiverExpr,
               inferredReceiverType: inferredReceiverType,
               ctx: ctx
           )
        {
            operatorReceiverType = nonNullSafeReceiverType
        } else {
            effectiveIsSafeChain = false
        }

        let getName = interner.intern("get")
        let receiverInfo = indexedOperatorMemberCandidates(
            named: getName, receiverExpr: receiverExpr, receiverType: operatorReceiverType, ctx: ctx
        )
        let receiverType = receiverInfo.receiverType
        func safeChainResultType(_ type: TypeID) -> TypeID {
            if effectiveIsSafeChain {
                sema.bindings.bindSafeChainIndexedValueType(id, type: type)
                return sema.types.makeNullable(type)
            }
            return type
        }
        let allGetMembers = receiverInfo.allMembers
        var getCandidates = receiverInfo.candidates
        if getCandidates.isEmpty {
            getCandidates = collectIndexedOperatorExtensionCandidates(
                named: getName, receiverType: receiverType, locals: locals, ctx: ctx
            )
        }

        var indexTypes: [TypeID] = []
        for (position, indexExpr) in indices.enumerated() {
            let literalExpectedType = contextualIntegerLiteralExpectedType(
                candidates: getCandidates,
                parameterIndex: position,
                indexExpr: indexExpr,
                ast: ast,
                sema: sema
            )
            let indexType = driver.inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: literalExpectedType)
            let valueType = driver.helpers.retypeClassNameAsCompanionValue(
                indexExpr, currentType: indexType, ast: ast, sema: sema
            ) ?? indexType
            indexTypes.append(valueType)
        }

        let getCall = CallExpr(range: range, calleeName: getName, args: zip(indices, indexTypes).map { index, type in
            let literal = driver.callChecker.integerLiteralValues(index, ast: ast)
            return CallArg(type: type, signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned)
        }, dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type), isOperatorCall: true)
        if ctx.resolver.probeCall(
            candidates: getCandidates, call: getCall, expectedType: expectedType,
            implicitReceiverType: receiverType, ctx: sema
        ).viableCandidates.isEmpty {
            let extensions = collectIndexedOperatorExtensionCandidates(
                named: getName, receiverType: receiverType, call: getCall, locals: locals, ctx: ctx
            )
            if !extensions.isEmpty { getCandidates = extensions }
        }

        if !getCandidates.isEmpty {
            // A forward-declared `get` operator can still carry the header's
            // inferred-return placeholder. Select by receiver and indices
            // first, infer the chosen callee's return type, then resolve
            // against the updated signature (KUU-4479).
            let hasUninferredGetReturn = getCandidates.contains { candidate in
                driver.inferredReturnFunctions[candidate] != nil
                    && !driver.checkedInferredReturnFunctions.contains(candidate)
                    && !driver.checkingInferredReturnFunctions.contains(candidate)
            }
            if hasUninferredGetReturn {
                let inputSelection = ctx.resolver.resolveCall(
                    candidates: getCandidates,
                    call: getCall,
                    expectedType: nil,
                    implicitReceiverType: receiverType,
                    ctx: ctx.sema
                )
                if inputSelection.diagnostic == nil,
                   let chosen = inputSelection.chosenCallee
                {
                    driver.inferFunctionReturnTypesIfNeeded(for: [chosen])
                }
            }
            let resolved = ctx.resolver.resolveCall(
                candidates: getCandidates,
                call: getCall,
                expectedType: expectedType,
                implicitReceiverType: receiverType,
                ctx: ctx.sema
            )
            if let diagnostic = resolved.diagnostic {
                ctx.sema.diagnostics.emit(diagnostic)
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
            if let chosen = resolved.chosenCallee,
               let signature = sema.symbols.functionSignature(for: chosen)
            {
                driver.callChecker.contextualizeResolvedIntegerArguments(
                    args: indices.map { CallArgument(expr: $0) }, resolved: resolved, ctx: ctx, locals: &locals
                )
                var mergedSubstitution = resolved.substitutedTypeArguments
                if let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
                    receiverType: receiverType,
                    signature: signature,
                    symbols: sema.symbols
                ) {
                    mergedSubstitution.merge(varianceResult.covariantSubstitution) { _, projected in projected }
                }
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: mergedSubstitution
                            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                            .map { _, value in value },
                        parameterMapping: resolved.parameterMapping,
                        dispatchReceiverSymbol: indexedOperatorDispatchReceiverSymbol(
                            for: chosen, named: getName, ctx: ctx
                        )
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                let returnType = sema.types.substituteTypeParameters(
                    in: signature.returnType,
                    substitution: mergedSubstitution,
                    typeVarBySymbol: typeVarBySymbol
                )
                let finalType = safeChainResultType(returnType)
                sema.bindings.bindExprType(id, type: finalType)
                return finalType
            }
        }

        if sema.types.isSubtype(receiverType, sema.types.stringType) {
            let stringGetCandidates = ctx.cachedScopeLookup(getName).filter { symbolID in
                guard let symbol = ctx.cachedSymbol(symbolID),
                      symbol.kind == .function,
                      let signature = sema.symbols.functionSignature(for: symbolID),
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                return sema.types.isSubtype(sema.types.stringType, declaredReceiver)
                    && symbol.flags.contains(.operatorFunction)
            }
            if !stringGetCandidates.isEmpty {
                let callArgs = indexTypes.map { CallArg(type: $0) }
                let resolved = ctx.resolver.resolveCall(
                    candidates: stringGetCandidates,
                    call: CallExpr(
                        range: range,
                        calleeName: getName,
                        args: callArgs,
                        isOperatorCall: true
                    ),
                    expectedType: expectedType,
                    implicitReceiverType: receiverType,
                    ctx: ctx.sema
                )
                if let chosen = resolved.chosenCallee,
                   let signature = sema.symbols.functionSignature(for: chosen)
                {
                    sema.bindings.bindCall(
                        id,
                        binding: CallBinding(
                            chosenCallee: chosen,
                            substitutedTypeArguments: resolved.substitutedTypeArguments
                                .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                                .map(\.value),
                            parameterMapping: resolved.parameterMapping
                        )
                    )
                    sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                    let finalType = safeChainResultType(signature.returnType)
                    sema.bindings.bindExprType(id, type: finalType)
                    return finalType
                }
            }
        }

        // A member `get` that merely shares the convention name without the
        // `operator` modifier cannot serve `x[i]`; reaching this point means no
        // operator candidate resolved, so reject instead of letting the
        // built-in array fallback silently bind (kotlinc: 'operator' modifier
        // is required).
        if allGetMembers.contains(where: { driver.helpers.isNonOperatorConventionFunction($0, sema: sema) }) {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0432",
                "'operator' modifier is required on 'get' in '\(driver.helpers.conventionReceiverDisplayName(receiverType, sema: sema, interner: interner))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard indices.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        driver.emitSubtypeConstraint(
            left: indexTypes[0],
            right: intType,
            range: ast.arena.exprRange(indices[0]) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.sema.diagnostics,
            diagnosticCode: "KSWIFTK-SEMA-0473",
            failureMessage: "Argument type mismatch."
        )
        if sema.types.isSubtype(receiverType, sema.types.stringType) {
            let finalType = safeChainResultType(sema.types.charType)
            sema.bindings.bindExprType(id, type: finalType)
            return finalType
        }
        guard !isCanonicalAtomicArrayReceiver(receiverType, sema: sema, interner: interner) else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function 'get'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard let elementType = builtinArrayElementType(
            for: receiverType, sema: sema, interner: interner
        ) else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function 'get'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        let finalType = safeChainResultType(elementType)
        sema.bindings.bindExprType(id, type: finalType)
        return finalType
    }

    func inferIndexedAssignExpr(
        _ id: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        valueExpr: ExprID,
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))

        var receiverCtx = ctx
        receiverCtx.isConditionallyEvaluated = ctx.receiverConditionallyEvaluated
        let inferredReceiverType = driver.inferExpr(receiverExpr, ctx: receiverCtx, locals: &locals, expectedType: nil)

        let setName = interner.intern("set")
        let receiverInfo = indexedOperatorMemberCandidates(
            named: setName, receiverExpr: receiverExpr, receiverType: inferredReceiverType, ctx: ctx
        )
        let receiverType = receiverInfo.receiverType
        let allSetMembers = receiverInfo.allMembers
        var setCandidates = receiverInfo.candidates
        if setCandidates.isEmpty {
            setCandidates = collectIndexedOperatorMemberExtensionCandidates(
                named: setName, receiverType: receiverType, ctx: ctx
            )
        }
        if setCandidates.isEmpty {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            // An unrelated nearer extension must not hide an applicable set
            // from an outer scope (e.g. the default-imported MutableMap.set).
            // Stop at the first scope with receiver-compatible operators so
            // applicable user extensions retain their normal priority.
            let scopedCandidates = ctx.scope.lookup(setName, matching: { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.operatorFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                if symbol.flags.contains(.expectDeclaration),
                   sema.symbols.actualSymbol(for: candidate) != nil
                {
                    return false
                }
                return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            })
            setCandidates = ctx.filterByVisibility(scopedCandidates).visible
        }
        if setCandidates.isEmpty {
            let nonNullReceiver = sema.types.makeNonNullable(receiverType)
            let visibleSyntheticCandidates = ctx.filterByVisibility(sema.symbols.lookupByShortName(setName)).visible
            setCandidates = visibleSyntheticCandidates.filter { candidate in
                guard let symbol = ctx.cachedSymbol(candidate),
                      symbol.kind == .function,
                      symbol.flags.contains(.synthetic),
                      symbol.flags.contains(.operatorFunction),
                      let signature = sema.symbols.functionSignature(for: candidate),
                      let declaredReceiver = signature.receiverType
                else {
                    return false
                }
                if let parentID = sema.symbols.parentSymbol(for: candidate),
                   let parentSymbol = sema.symbols.symbol(parentID),
                   parentSymbol.kind == .property
                {
                    return false
                }
                return driver.callChecker.extensionSyntheticFallbackReceiverMatches(
                    callSiteReceiver: nonNullReceiver,
                    declaredReceiver: declaredReceiver,
                    sema: sema
                )
            }
        }
        if setCandidates.isEmpty {
            setCandidates = driver.callChecker.collectBundledStdlibExtensionCandidates(
                named: setName,
                receiverType: receiverType,
                requireOperator: true,
                sourceFile: ctx.currentASTFile,
                sema: sema,
                interner: interner
            )
        }

        var indexTypes: [TypeID] = []
        for (position, indexExpr) in indices.enumerated() {
            let literalExpectedType = contextualIntegerLiteralExpectedType(
                candidates: setCandidates,
                parameterIndex: position,
                indexExpr: indexExpr,
                ast: ast,
                sema: sema
            )
            let indexType = driver.inferExpr(indexExpr, ctx: ctx, locals: &locals, expectedType: literalExpectedType)
            indexTypes.append(indexType)
        }

        let isBuiltinArray = builtinArrayElementType(for: receiverType, sema: sema, interner: interner) != nil
        let contextSetCandidates: [SymbolID] = {
            guard isBuiltinArray else { return setCandidates }
            let extensions = collectIndexedOperatorExtensionCandidates(
                named: setName, receiverType: receiverType, locals: locals, ctx: ctx
            )
            return setCandidates + extensions.filter { !setCandidates.contains($0) }
        }()

        let valueParameterIndex = indices.count
        let setValueExpectedType: TypeID? = {
            if !contextSetCandidates.isEmpty {
                var valueTypes: [TypeID] = []
                for candidate in contextSetCandidates {
                    guard let sig = sema.symbols.functionSignature(for: candidate),
                          sig.parameterTypes.count > valueParameterIndex,
                          let valueParameterType = sig.parameterTypes.last
                    else {
                        continue
                    }
                    // The declared `set` signature's value parameter is often
                    // still the operator's own raw type parameter (e.g. `V` in
                    // `operator fun <K, V> MutableMap<K, V>.set(key: K, value:
                    // V)`); substitute the call-site receiver's concrete type
                    // arguments first so a fully-resolved value type (e.g.
                    // `(Int) -> Int`) reaches the checks below instead of the
                    // bare type parameter.
                    let paramType = driver.callChecker.applyReceiverClassTypeArgs(
                        to: valueParameterType,
                        signature: sig,
                        candidate: candidate,
                        receiverType: receiverType,
                        sema: sema
                    )
                    if isBuiltinArray,
                       !driver.callChecker.typeMentionsTypeParameter(paramType, sema: sema)
                    {
                        let indexArgs = zip(indices, indexTypes).map { expr, type in
                            let literal = driver.callChecker.integerLiteralValues(expr, ast: ast)
                            return CallArg(type: type, signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned)
                        }
                        let probe = CallExpr(
                            range: range,
                            calleeName: setName,
                            args: indexArgs + [CallArg(type: paramType, bindsToLastParameter: true)],
                            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type),
                            isOperatorCall: true
                        )
                        if ctx.resolver.probeCall(
                            candidates: [candidate], call: probe, expectedType: nil,
                            implicitReceiverType: receiverType, ctx: sema
                        ).viableCandidates.isEmpty {
                            continue
                        }
                    }
                    valueTypes.append(sema.types.makeNonNullable(paramType))
                }
                // Candidates swept up through the generic-receiver fallback
                // can declare an unresolved type parameter as the value type
                // (e.g. `CPointer<CPointerVarOf<P>>.set` collected for a
                // concrete `CPointer<IntVar>` receiver). An unresolved type
                // parameter cannot narrow an integer literal, so prefer the
                // concrete declared types when both are present.
                let concreteValueTypes = valueTypes.filter {
                    !driver.callChecker.typeMentionsTypeParameter($0, sema: sema)
                }
                let narrowingValueTypes = concreteValueTypes.isEmpty ? valueTypes : concreteValueTypes
                if let first = narrowingValueTypes.first {
                    if narrowingValueTypes.dropFirst().allSatisfy({ $0 == first }) { return first }
                    if isBuiltinArray { return nil }
                }
            }
            // The raw array write-back only exists for a single index; for a
            // multi-index `a[i, j] = v` the outer array's element type is
            // unrelated to the operator `set()`'s value parameter, so it must
            // not steer value inference (e.g. `cells[i, j] = f()` on
            // `Array<CharArray>` must not expect `CharArray`).
            guard indices.count == 1 else { return nil }
            return driver.helpers.arrayElementType(for: receiverType, sema: sema, interner: interner)
        }()
        let setValueTypeHasUnresolvedTypeParameter: Bool = {
            guard let setValueExpectedType, !contextSetCandidates.isEmpty else { return false }
            return contextSetCandidates.contains { candidate in
                guard let signature = sema.symbols.functionSignature(for: candidate) else {
                    return true
                }
                return ctx.resolver.containsTypeVariable(
                    setValueExpectedType,
                    typeVarBySymbol: sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols),
                    typeSystem: sema.types
                )
            }
        }()

        // Pass concrete contextual numeric types for literal narrowing, and
        // fully-substituted function or class types for nested calls. A
        // setter's unresolved type parameter must not influence other values.
        let resolvedValueExpectedType: TypeID? = {
            guard let setValueExpectedType else { return nil }
            let nonNull = sema.types.makeNonNullable(setValueExpectedType)
            switch sema.types.kind(of: nonNull) {
            case let .primitive(primitive, _):
                guard primitive == .long || primitive == .uint || primitive == .ulong ||
                    primitive == .byte || primitive == .short ||
                    primitive == .ubyte || primitive == .ushort
                else {
                    return nil
                }
                return nonNull
            case .functionType:
                guard !driver.callChecker.typeMentionsTypeParameter(nonNull, sema: sema) else {
                    return nil
                }
                return nonNull
            case .classType:
                guard driver.callChecker.isInferableNestedCallExpr(valueExpr, ast: ast),
                      !setValueTypeHasUnresolvedTypeParameter
                else {
                    return nil
                }
                return nonNull
            default:
                return nil
            }
        }()

        let uncheckedArrayViewExpectedType = uncheckedArrayViewIntegerLiteralExpectedType(
            receiverExpr: receiverExpr,
            receiverType: receiverType,
            valueExpr: valueExpr,
            ast: ast,
            sema: sema,
            interner: interner
        )
        let valueExpectedType = uncheckedArrayViewExpectedType ?? resolvedValueExpectedType

        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: valueExpectedType)

        let argumentExprs = indices + [valueExpr]
        var setCallArgs = zip(indices, indexTypes).map { expr, type in
            let literal = driver.callChecker.integerLiteralValues(expr, ast: ast)
            return CallArg(type: type, signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned)
        }
        setCallArgs.append(CallArg(type: valueType, bindsToLastParameter: true))
        let setCall = CallExpr(
            range: range,
            calleeName: setName,
            args: setCallArgs,
            dispatchReceiverTypes: ctx.implicitReceiverMemberLookupEntries().map(\.type),
            isOperatorCall: true
        )
        if ctx.resolver.probeCall(
            candidates: setCandidates, call: setCall, expectedType: nil,
            implicitReceiverType: receiverType, ctx: sema
        ).viableCandidates.isEmpty {
            let extensions = collectIndexedOperatorExtensionCandidates(
                named: setName, receiverType: receiverType, call: setCall, locals: locals, ctx: ctx
            )
            if !extensions.isEmpty { setCandidates = extensions }
        }

        if !setCandidates.isEmpty {
            let resolved = ctx.resolver.resolveCall(
                candidates: setCandidates,
                call: setCall,
                expectedType: nil,
                implicitReceiverType: receiverType,
                ctx: ctx.sema
            )
            if let chosen = resolved.chosenCallee {
                if !driver.callChecker.allowsProjectedReceiverUnsafeVariance(
                    chosen, sema: sema, interner: interner
                ),
                   let signature = sema.symbols.functionSignature(for: chosen),
                   let varianceResult = sema.types.buildVarianceProjectionSubstitutions(
                       receiverType: receiverType,
                       signature: signature,
                       symbols: sema.symbols
                   ),
                   let violatingParamIndex = sema.types.checkVarianceViolationInParameters(
                       signature: signature,
                       writeForbiddenSymbols: varianceResult.writeForbiddenSymbols,
                       nullableWriteSymbols: varianceResult.nullableWriteSymbols,
                       argumentTypes: setCallArgs.map(\.type),
                       parameterMapping: resolved.parameterMapping
                   )
                {
                    let paramType = sema.types.displayName(
                        of: signature.parameterTypes[violatingParamIndex],
                        symbols: sema.symbols,
                        interner: interner
                    )
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-VAR-OUT",
                        "A type projection on the receiver prevents calling 'set' because the type parameter appears in an 'in' position (parameter type '\(paramType)').",
                        range: range
                    )
                    sema.bindings.bindExprType(id, type: sema.types.errorType)
                    return sema.types.errorType
                }
                driver.callChecker.contextualizeResolvedIntegerArguments(
                    args: argumentExprs.map { CallArgument(expr: $0) }, resolved: resolved, ctx: ctx, locals: &locals
                )
                // The resolved Array<Any?> setter would re-infer this literal
                // as Int. Restore the JVM-compatible source-array context,
                // which is available only on this direct unchecked cast view.
                if let uncheckedArrayViewExpectedType {
                    _ = driver.inferExpr(
                        valueExpr,
                        ctx: ctx,
                        locals: &locals,
                        expectedType: uncheckedArrayViewExpectedType
                    )
                }
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: resolved.substitutedTypeArguments
                            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                            .map { _, value in value },
                        parameterMapping: resolved.parameterMapping,
                        dispatchReceiverSymbol: indexedOperatorDispatchReceiverSymbol(
                            for: chosen, named: setName, ctx: ctx
                        )
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
            // KUU-3667: `set` candidates existed but none accepted the
            // arguments (e.g. `map[1] = v` on `Map<String, V>` where the
            // MutableMap.set extension rejects the Int key). A non-array
            // receiver must emit the resolve diagnostic and reject — falling
            // through to the built-in array fallback would accept the write
            // and lower to kk_array_set on a non-array receiver, which panics
            // at runtime. A genuine array receiver instead keeps the legacy
            // constraint fallback below, which reports the same diagnostics
            // it always has (e.g. an element literal that cannot narrow).
            guard isBuiltinArray else {
                if let diagnostic = resolved.diagnostic {
                    ctx.sema.diagnostics.emit(diagnostic)
                } else {
                    ctx.sema.diagnostics.error(
                        "KSWIFTK-SEMA-0002",
                        "No viable overload found for operator 'set'.",
                        range: range
                    )
                }
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
        }

        if allSetMembers.contains(where: { driver.helpers.isNonOperatorConventionFunction($0, sema: sema) }) {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0432",
                "'operator' modifier is required on 'set' in '\(driver.helpers.conventionReceiverDisplayName(receiverType, sema: sema, interner: interner))'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard indices.count == 1 else {
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        guard !isCanonicalAtomicArrayReceiver(receiverType, sema: sema, interner: interner) else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function 'set'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if sema.types.makeNonNullable(receiverType) == sema.types.stringType {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function 'set'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        if let (_, receiverSymbol) = resolveClassTypeSymbol(sema.types.makeNonNullable(receiverType), sema: sema) {
            let readOnlyFQNames: Set<[InternedString]> = Set(
                ["kotlin.collections.List", "kotlin.collections.Map", "kotlin.collections.Collection",
                 "kotlin.collections.Set", "kotlin.collections.Iterable", "kotlin.String", "kotlin.CharSequence"]
                    .map { $0.split(separator: ".").map { interner.intern(String($0)) } }
            )
            if readOnlyFQNames.contains(receiverSymbol.fqName) {
                ctx.sema.diagnostics.error(
                    "KSWIFTK-SEMA-0024",
                    "Unresolved member function 'set'.",
                    range: range
                )
                sema.bindings.bindExprType(id, type: sema.types.errorType)
                return sema.types.errorType
            }
        }
        // The built-in array fallback only exists for genuine array receivers
        // (including the synthetic array shells used by --no-stdlib / .kklib
        // builds, which carry no `set` member). A non-array receiver reaching
        // this point has no applicable indexed-`set` convention at all; reject
        // instead of lowering to kk_array_set on a foreign object layout
        // (KUU-3667).
        guard isBuiltinArray else {
            ctx.sema.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Unresolved member function 'set'.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        driver.emitSubtypeConstraint(
            left: indexTypes[0],
            right: intType,
            range: ast.arena.exprRange(indices[0]) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.sema.diagnostics,
            diagnosticCode: "KSWIFTK-SEMA-0473",
            failureMessage: "Argument type mismatch."
        )
        let elementExpectedType = driver.helpers.arrayElementType(
            for: receiverType, sema: sema, interner: interner
        )
        if let elementExpectedType {
            driver.emitSubtypeConstraint(
                left: valueType,
                right: elementExpectedType,
                range: ast.arena.exprRange(valueExpr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.sema.diagnostics,
                diagnosticCode: "KSWIFTK-SEMA-0473",
                failureMessage: "Argument type mismatch."
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
