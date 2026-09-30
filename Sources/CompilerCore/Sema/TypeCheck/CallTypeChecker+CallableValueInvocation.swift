
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
        expectedType: TypeID?,
        arityPolicy: CallableValueArityPolicy = .receiverNeverExplicit
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
        if receiverArgOffset == 1, let receiverType = functionType.receiver {
            driver.emitSubtypeConstraint(
                left: argTypes[0],
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
                left: argTypes[argIndex],
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
        sema.bindings.bindCallableValueCall(
            id,
            binding: CallableValueCallBinding(
                target: callableTarget,
                functionType: nonNullCalleeType,
                parameterMapping: parameterMapping
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
}
