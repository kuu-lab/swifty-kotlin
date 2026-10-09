
extension CallTypeChecker {
    func markRangeCallBindings(
        _ id: ExprID,
        chosen: SymbolID,
        returnType: TypeID,
        sema: SemaModule
    ) {
        let interner = driver.interner
        let isRangeConstructor: Bool
        let externalLinkName = sema.symbols.externalLinkName(for: chosen)
        if let externalLinkName, !CallLowerer.isSourceBackedLinkName(externalLinkName) {
            isRangeConstructor = [
                "kk_op_rangeTo",
                "__kk_op_rangeUntil",
                "__kk_op_ulong_rangeUntil",
                "__kk_uint_rangeTo",
                "__kk_ulong_rangeTo",
                "__kk_char_rangeTo",
                "__kk_int_progression_fromClosedRange",
                "__kk_long_progression_fromClosedRange",
                "__kk_uint_progression_fromClosedRange",
                "__kk_ulong_progression_fromClosedRange",
                "__kk_char_progression_fromClosedRange",
            ].contains(externalLinkName)
        } else if let symbol = sema.symbols.symbol(chosen) {
            let name = interner.resolve(symbol.name)
            isRangeConstructor = ["rangeTo", "until", "rangeUntil", "downTo", "step", "fromClosedRange"].contains(name)
                && driver.helpers.isRangeLikeType(returnType, sema: sema, interner: interner)
        } else {
            isRangeConstructor = false
        }

        guard isRangeConstructor else { return }

        sema.bindings.markRangeExpr(id)

        if let elementType = driver.helpers.rangeLikeDeclaredElementType(
            for: returnType,
            sema: sema,
            interner: interner
        ), elementType == sema.types.floatType || elementType == sema.types.doubleType {
            // Generic source-backed rangeUntil resolves through OpenEndRange<T>.
            // Preserve its concrete floating-point element type for the KIR/runtime
            // bridge, just as the legacy scalar range path does for range literals.
            sema.bindings.markFloatingPointRangeExpr(id)
            sema.bindings.bindFloatingPointRangeElementType(elementType, forExpr: id)
        }

        // Classify the concrete range/progression kind for UInt/ULong/Char dispatch.
        if let (_, symbol) = resolveClassTypeSymbol(returnType, sema: sema) {
            let className = interner.resolve(symbol.name)
            switch className {
            case "UIntRange", "UIntProgression":
                sema.bindings.markUIntRangeExpr(id)
            case "ULongRange", "ULongProgression":
                sema.bindings.markULongRangeExpr(id)
            case "CharRange", "CharProgression":
                sema.bindings.markCharRangeExpr(id)
            default:
                break
            }
        }

        // Preserve the legacy external-link-name fast paths for the residual
        // synthetic/runtime-backed operators (rangeTo, old signed rangeUntil,
        // etc.) whose return type may still be the scalar handle.
        if let externalLinkName = sema.symbols.externalLinkName(for: chosen) {
            if externalLinkName == "__kk_uint_rangeTo"
                || externalLinkName == "__kk_uint_progression_fromClosedRange"
                || (externalLinkName == "__kk_op_rangeUntil" && returnType == sema.types.uintType)
            {
                sema.bindings.markUIntRangeExpr(id)
            }
            if externalLinkName == "__kk_char_rangeTo" {
                sema.bindings.markCharRangeExpr(id)
            }
            if externalLinkName == "__kk_ulong_rangeTo"
                || externalLinkName == "__kk_ulong_progression_fromClosedRange"
                || externalLinkName == "__kk_op_ulong_rangeUntil"
                || externalLinkName == "__kk_ulong_rangeTo"
            {
                sema.bindings.markULongRangeExpr(id)
            }
        }
    }

    func bindCallAndResolveReturnType(
        _ id: ExprID,
        chosen: SymbolID,
        resolved: ResolvedCall,
        sema: SemaModule
    ) -> TypeID {
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
        if sema.symbols.externalLinkName(for: chosen) == "__kk_string_split" {
            sema.bindings.markCollectionExpr(id)
        }
        let returnType: TypeID
        if let signature = sema.symbols.functionSignature(for: chosen) {
            let typeVarBySymbol = sema.types.makeTypeVarBySymbol(signature.typeParameterSymbols)
            returnType = sema.types.substituteTypeParameters(
                in: signature.returnType,
                substitution: resolved.substitutedTypeArguments,
                typeVarBySymbol: typeVarBySymbol
            )
        } else {
            returnType = sema.types.anyType
        }
        markRangeCallBindings(id, chosen: chosen, returnType: returnType, sema: sema)
        return returnType
    }

    /// How an extension-function-typed callee's own receiver (if any) may be
    /// supplied when the arity of `argTypes` doesn't by itself say whether
    /// argument 0 is that receiver or the first ordinary parameter.
    enum CallableValueArityPolicy {
        /// The callee type's receiver (if any) is never read from `argTypes`.
        /// Matches the original, receiver-unaware behavior. Used by the
        /// member-property callable-invocation sugar (`receiver.prop(args)`),
        /// which is unrelated to explicit-receiver call forms and must not
        /// change behavior.
        case receiverNeverExplicit
        /// A bare call (`ef(...)`) accepts either the historical shape, where
        /// the receiver comes from an active implicit-receiver scope
        /// (`argTypes.count == params.count`, e.g. calling a `T.() -> Unit`
        /// value bare inside `T.run { ... }`), or the receiver supplied
        /// positionally as argument 0 (`argTypes.count == params.count + 1`,
        /// e.g. `ef(3, 4)`).
        case receiverOptionallyExplicit
        /// An explicit `.invoke(...)` member call has no implicit-receiver
        /// concept: when the callee type has a receiver, it must always be
        /// supplied positionally as argument 0 (`ef.invoke(3, 4)`); there is
        /// no arity at which it may be omitted (`ef.invoke(4)` is invalid).
        case receiverRequiredExplicit
    }

    func inferCallableValueInvocation(
        _ id: ExprID,
        calleeType: TypeID,
        callableTarget: CallableTarget?,
        args: [CallArgument],
        argTypes: [TypeID],
        range: SourceRange,
        ctx: TypeInferenceContext,
        locals: inout LocalBindings,
        expectedType: TypeID?,
        arityPolicy: CallableValueArityPolicy = .receiverNeverExplicit,
        extensionCallableExpr: ExprID? = nil
    ) -> TypeID? {
        let ast = ctx.ast
        let sema = ctx.sema
        let nonNullCalleeType = sema.types.makeNonNullable(calleeType)
        guard case let .functionType(functionType) = sema.types.kind(of: nonNullCalleeType) else {
            return nil
        }
        let receiverArgOffset: Int = switch arityPolicy {
        case .receiverNeverExplicit:
            0
        case .receiverOptionallyExplicit:
            (functionType.receiver != nil && argTypes.count == functionType.params.count + 1) ? 1 : 0
        case .receiverRequiredExplicit:
            functionType.receiver != nil ? 1 : 0
        }
        guard !args.contains(where: { $0.label != nil || $0.isSpread }),
              functionType.params.count + receiverArgOffset == argTypes.count
        else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0002",
                "No viable overload found for call.",
                range: range
            )
            sema.bindings.bindExprType(id, type: sema.types.errorType)
            return sema.types.errorType
        }
        var parameterMapping: [Int: Int] = [:]
        func contextualizedArgumentType(at index: Int, parameterType: TypeID) -> TypeID {
            guard isLambdaOrCallableRefArg(args[index].expr, ast: ast)
                || integerLiteralFitsParameter(args[index].expr, parameterType: parameterType, ctx: ctx) else {
                return argTypes[index]
            }
            return driver.inferExpr(args[index].expr, ctx: ctx, locals: &locals, expectedType: parameterType)
        }
        if receiverArgOffset == 1, let receiverType = functionType.receiver {
            driver.emitSubtypeConstraint(
                left: contextualizedArgumentType(at: 0, parameterType: receiverType),
                right: receiverType,
                range: ast.arena.exprRange(args[0].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        for paramIndex in functionType.params.indices {
            let argIndex = paramIndex + receiverArgOffset
            if receiverArgOffset == 0 {
                parameterMapping[argIndex] = paramIndex
            }
            driver.emitSubtypeConstraint(
                left: contextualizedArgumentType(at: argIndex, parameterType: functionType.params[paramIndex]),
                right: functionType.params[paramIndex],
                range: ast.arena.exprRange(args[argIndex].expr) ?? range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        if let expectedType {
            driver.emitSubtypeConstraint(
                left: functionType.returnType,
                right: expectedType,
                range: range,
                solver: ConstraintSolver(),
                sema: sema,
                diagnostics: ctx.semaCtx.diagnostics
            )
        }
        // A bare receiver-function call in an escaping lambda reads an outer
        // `this` even when its body contains no ordinary member reference.
        // Record that value so capture analysis retains it and KIR supplies it.
        if receiverArgOffset == 0, let requiredReceiver = functionType.receiver,
           case .call = ast.arena.expr(id) {
            let localThis = locals[ctx.interner.intern("this")].flatMap { local in
                sema.types.isSubtype(local.type, requiredReceiver) ? local.symbol : nil
            }
            let receiverSymbol = localThis
                ?? ctx.implicitReceiverStack.reversed().first(where: {
                    sema.types.isSubtype($0.type, requiredReceiver)
                })?.symbol
                ?? ctx.outerReceiverTypes.reversed().first(where: {
                    sema.types.isSubtype($0.type, requiredReceiver)
                })?.symbol
            if let receiverSymbol {
                sema.bindings.markImplicitExtensionReceiver(id, symbol: receiverSymbol)
            }
        }
        sema.bindings.bindCallableValueCall(
            id,
            binding: CallableValueCallBinding(
                target: callableTarget,
                functionType: nonNullCalleeType,
                parameterMapping: parameterMapping,
                extensionCallableExpr: extensionCallableExpr
            )
        )
        if let callableTarget {
            sema.bindings.bindCallableTarget(id, target: callableTarget)
        }
        sema.bindings.bindExprType(id, type: functionType.returnType)
        return functionType.returnType
    }

    func inferFunctionTypeOrError(from type: TypeID, sema: SemaModule) -> TypeID? {
        let nonNullType = sema.types.makeNonNullable(type)
        guard case .functionType = sema.types.kind(of: nonNullType) else {
            return nil
        }
        return nonNullType
    }

    func inferLexicalExtensionCallableInvocation(
        _ request: MemberCallInferenceRequest,
        receiverType: TypeID,
        locals: inout LocalBindings
    ) -> TypeID? {
        let ctx = request.ctx
        let sema = ctx.sema
        let name = request.calleeName
        let candidateType: TypeID?
        if let local = locals[name] {
            candidateType = local.type
        } else if let implicitReceiver = ctx.implicitReceiverType,
                  let property = driver.helpers.lookupMemberProperty(
                      named: name,
                      receiverType: sema.types.makeNonNullable(implicitReceiver),
                      sema: sema
                  ) {
            candidateType = property.type
        } else {
            candidateType = ctx.cachedScopeLookup(name).first(where: {
                sema.symbols.symbol($0)?.kind == .property
            }).flatMap { sema.symbols.propertyType(for: $0) }
        }
        guard let candidateType,
              case let .functionType(candidateFunction) = sema.types.kind(of: candidateType),
              candidateFunction.receiver != nil
        else {
            return nil
        }

        let calleeExpr = ctx.ast.arena.appendExpr(.nameRef(name, request.range))
        let calleeType = driver.inferExpr(calleeExpr, ctx: ctx, locals: &locals)
        guard case let .functionType(functionType) = sema.types.kind(of: calleeType),
              functionType.receiver != nil
        else {
            return driver.helpers.bindAndReturnErrorType(request.id, sema: sema)
        }
        guard functionType.nullability == .nonNull, request.explicitTypeArgs.isEmpty else {
            ctx.semaCtx.diagnostics.error(
                "KSWIFTK-SEMA-0024",
                "Cannot invoke nullable or type-argument-qualified function value '\(ctx.interner.resolve(name))'.",
                range: request.range
            )
            return driver.helpers.bindAndReturnErrorType(request.id, sema: sema)
        }
        let argumentTypes = request.args.enumerated().map { index, argument in
            driver.inferExpr(
                argument.expr,
                ctx: ctx,
                locals: &locals,
                expectedType: functionType.params.indices.contains(index) ? functionType.params[index] : nil
            )
        }
        let result = inferCallableValueInvocation(
            request.id,
            calleeType: calleeType,
            callableTarget: driver.helpers.callableTargetForCalleeExpr(calleeExpr, sema: sema),
            args: [CallArgument(expr: request.receiverID)] + request.args,
            argTypes: [request.safeCall ? sema.types.makeNonNullable(receiverType) : receiverType] + argumentTypes,
            range: request.range,
            ctx: ctx,
            locals: &locals,
            expectedType: request.expectedType,
            arityPolicy: .receiverRequiredExplicit,
            extensionCallableExpr: calleeExpr
        ) ?? sema.types.errorType
        // Keep the lexical reference visible to lambda/local-class capture analysis.
        if let symbol = sema.bindings.identifierSymbol(for: calleeExpr) {
            sema.bindings.bindIdentifier(request.id, symbol: symbol)
        }
        let finalType = request.safeCall ? sema.types.makeNullable(result) : result
        sema.bindings.bindExprType(request.id, type: finalType)
        return finalType
    }
}
