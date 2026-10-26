
extension LocalDeclTypeChecker {
    /// `kotlin.concurrent.atomics`' array classes have no `operator get`/`set`
    /// on the real (JVM/common) API surface; index access must not fall
    /// through to the built-in array path (KUU-1365). The legacy
    /// `kotlin.concurrent` arrays keep their bundled `get`/`set` extensions
    /// and never reach this check.
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

    /// Returns the element type only for Kotlin's built-in array classes.
    /// Generic type arguments alone do not make an arbitrary class indexable.
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

    func inferIndexedAccessExpr(
        _ id: ExprID,
        receiverExpr: ExprID,
        indices: [ExprID],
        range: SourceRange,
        expectedType: TypeID?,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings
    ) -> TypeID {
        let ast = ctx.ast
        let sema = ctx.sema
        let interner = ctx.interner
        let intType = sema.types.make(.primitive(.int, .nonNull))

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)

        let getName = interner.intern("get")
        let allGetMembers = driver.helpers.collectMemberFunctionCandidates(
            named: getName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        )
        var getCandidates = ctx.filterByVisibility(allGetMembers).visible.filter {
            ctx.cachedSymbol($0)?.flags.contains(.operatorFunction) == true
        }
        if getCandidates.isEmpty {
            getCandidates = collectIndexedOperatorExtensionCandidates(
                named: getName, receiverType: receiverType, locals: locals, ctx: ctx
            )
        }

        // Infer all index expressions without forcing Int.
        // Int constraint is only applied in the built-in array fallback.
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
        })
        // Member existence does not imply applicability. Probe without emitting
        // diagnostics, retaining even ambiguous viable members ahead of extensions.
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
                // Record the resolved call so KIR lowering can dispatch correctly
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: resolved.substitutedTypeArguments
                            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                            .map { _, value in value },
                        parameterMapping: resolved.parameterMapping
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                // Substitute type parameters in the return type so that
                // generic get() calls (e.g. List<String?>.get()) return
                // the concrete element type (String?) instead of T.
                let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
                let returnType = sema.types.substituteTypeParameters(
                    in: signature.returnType,
                    substitution: resolved.substitutedTypeArguments,
                    typeVarBySymbol: typeVarBySymbol
                )
                sema.bindings.bindExprType(id, type: returnType)
                return returnType
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
                        args: callArgs
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
                    sema.bindings.bindExprType(id, type: signature.returnType)
                    return signature.returnType
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
            diagnostics: ctx.sema.diagnostics
        )
        if sema.types.isSubtype(receiverType, sema.types.stringType) {
            sema.bindings.bindExprType(id, type: sema.types.charType)
            return sema.types.charType
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
        sema.bindings.bindExprType(id, type: elementType)
        return elementType
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

        let receiverType = driver.inferExpr(receiverExpr, ctx: ctx, locals: &locals, expectedType: nil)

        let setName = interner.intern("set")
        let allSetMembers = driver.helpers.collectMemberFunctionCandidates(
            named: setName,
            receiverType: receiverType,
            sema: sema,
            interner: interner
        )
        var setCandidates = ctx.filterByVisibility(allSetMembers).visible.filter {
            ctx.cachedSymbol($0)?.flags.contains(.operatorFunction) == true
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
                // Preserve cachedScopeLookup's expect/actual filtering.
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
            // Bundled stdlib operator extensions (e.g. AtomicIntArray.set) are
            // conceptually members and resolve without an explicit import.
            setCandidates = driver.callChecker.collectBundledStdlibExtensionCandidates(
                named: setName,
                receiverType: receiverType,
                requireOperator: true,
                sourceFile: ctx.currentASTFile,
                sema: sema,
                interner: interner
            )
        }

        // Infer all index expressions without forcing Int.
        // Int constraint is only applied in the built-in array fallback.
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

        // Determine the expected element type so integer literals can be
        // narrowed for built-in array assignment and operator-set calls
        // (e.g. ByteArray[0] = 9).
        let valueParameterIndex = indices.count
        let setValueExpectedType: TypeID? = {
            if !setCandidates.isEmpty {
                var valueTypes: [TypeID] = []
                for candidate in setCandidates {
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
                    valueTypes.append(sema.types.makeNonNullable(paramType))
                }
                if let first = valueTypes.first, valueTypes.dropFirst().allSatisfy({ $0 == first }) {
                    return first
                }
            }
            return driver.helpers.arrayElementType(for: receiverType, sema: sema, interner: interner)
        }()

        // Pass concrete contextual numeric types or a fully-substituted function
        // type as the expected type; a still-generic element type (e.g. an
        // unsubstituted `MutableMap.set` value type `T`) must not influence
        // inference of non-literal values.
        let valueExpectedType: TypeID? = {
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
            default:
                return nil
            }
        }()

        let valueType = driver.inferExpr(valueExpr, ctx: ctx, locals: &locals, expectedType: valueExpectedType)

        let argumentExprs = indices + [valueExpr]
        var setCallArgs = zip(indices, indexTypes).map { expr, type in
            let literal = driver.callChecker.integerLiteralValues(expr, ast: ast)
            return CallArg(type: type, signedIntegerLiteral: literal.signed, unsignedIntegerLiteral: literal.unsigned)
        }
        setCallArgs.append(CallArg(type: valueType, bindsToLastParameter: true))
        let setCall = CallExpr(range: range, calleeName: setName, args: setCallArgs)
        // A single-index member cannot handle a multi-index assignment.
        // Preserve applicable (including ambiguous) members, but try lexical
        // operator extensions when none of the collected candidates applies.
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
                driver.callChecker.contextualizeResolvedIntegerArguments(
                    args: argumentExprs.map { CallArgument(expr: $0) }, resolved: resolved, ctx: ctx, locals: &locals
                )
                // Record the resolved call so KIR lowering can dispatch correctly
                sema.bindings.bindCall(
                    id,
                    binding: CallBinding(
                        chosenCallee: chosen,
                        substitutedTypeArguments: resolved.substitutedTypeArguments
                            .sorted(by: { $0.key.rawValue < $1.key.rawValue })
                            .map { _, value in value },
                        parameterMapping: resolved.parameterMapping
                    )
                )
                sema.bindings.bindCallableTarget(id, target: .symbol(chosen))
                sema.bindings.bindExprType(id, type: sema.types.unitType)
                return sema.types.unitType
            }
        }

        // A member `set` without the `operator` modifier cannot serve
        // `x[i] = v`; reject before the built-in array fallback swallows it.
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
        // Read-only receivers (List, Map, String, ...) have no `set`; the
        // built-in fallback below only exists for arrays and mutable collections.
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
        driver.emitSubtypeConstraint(
            left: indexTypes[0],
            right: intType,
            range: ast.arena.exprRange(indices[0]) ?? range,
            solver: ConstraintSolver(),
            sema: sema,
            diagnostics: ctx.sema.diagnostics
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
                diagnostics: ctx.sema.diagnostics
            )
        }
        sema.bindings.bindExprType(id, type: sema.types.unitType)
        return sema.types.unitType
    }
}
