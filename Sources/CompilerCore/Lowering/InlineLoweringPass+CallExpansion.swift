/// Expansion of a regular (non-lambda) `inline` function body into its caller.
///
/// `expandInlineCall` lowers the callee's instructions into caller-scoped
/// expressions: call-site arguments bind the parameter symbols, reified type
/// parameters become token expressions via `InlineReifiedTypeTokens`, generic
/// types are substituted through `InlineTypeSubstitution`, expression cloning
/// goes through `InlineExprCloning`, erased-ABI argument/result adjustments
/// through `InlineErasedLambdaABI`, and calls to function-typed parameters or
/// direct `kk_function_invoke` sites delegate to the lambda expansion
/// machinery still hosted on `InlineLoweringPass` (`resolveLambdaFunction` /
/// `expandLambdaBody` / `appendInlinedLambdaExpansion`). Throw rerouting of
/// the spliced body stays with the caller via `InlineThrowRerouting`.
extension InlineLoweringPass {
    func expandInlineCall(
        inlineTarget: KIRFunction,
        arguments: [KIRExprID],
        allFunctionsBySymbol: [SymbolID: KIRFunction],
        module: KIRModule,
        ctx: KIRContext,
        callerBody: [KIRInstruction],
        labels: inout InlineLabelAllocator
    ) -> InlineExpansion? {
        guard arguments.count == inlineTarget.params.count else {
            return nil
        }

        let parameterValues = Dictionary(uniqueKeysWithValues: zip(inlineTarget.params.map(\.symbol), arguments))

        let typeParamTokenValues = InlineReifiedTypeTokens.buildTypeParamTokenValues(
            inlineTarget: inlineTarget,
            parameterValues: parameterValues,
            ctx: ctx
        )
        let inlineTypeSubstitution = InlineTypeSubstitution.build(
            inlineTarget: inlineTarget,
            arguments: arguments,
            module: module,
            ctx: ctx
        )
        // Keep expression cloning independent from the type-substitution
        // mapping by passing only the operation it needs.
        func substituteType(_ type: TypeID?) -> TypeID? {
            inlineTypeSubstitution?.applying(to: type, in: ctx) ?? type
        }
        let substitutedInlineReturnType = inlineTypeSubstitution?.applying(
            to: inlineTarget.returnType,
            in: ctx
        ) ?? inlineTarget.returnType

        // Build a set of parameter symbols that have function types so we can
        // detect calls to lambda parameters inside the inline body.
        let lambdaParamSymbols: Set<SymbolID> = {
            guard let sema = ctx.sema else { return [] }
            var result: Set<SymbolID> = []
            for param in inlineTarget.params {
                if case .functionType = sema.types.kind(of: param.type) {
                    result.insert(param.symbol)
                }
            }
            return result
        }()

        let lambdaParamByCalleeName: [InternedString: SymbolID] = {
            guard let sema = ctx.sema else { return [:] }
            var result: [InternedString: SymbolID] = [:]
            for param in inlineTarget.params {
                if case .functionType = sema.types.kind(of: param.type),
                   let symbolInfo = sema.symbols.symbol(param.symbol) {
                    result[symbolInfo.name] = param.symbol
                }
            }
            return result
        }()

        // A body restored from a library's inline KIR was ABI-lowered when that
        // library was built: it passes and receives every erased value boxed,
        // and its instructions carry no expr types to detect that from.
        let erasedExpansionABI = InlineErasedLambdaABI.usesErasedLambdaABI(inlineTarget, ctx: ctx)

        var localExprMap: [KIRExprID: KIRExprID] = [:]
        var unitResultAliasExprs: Set<KIRExprID> = []
        var lowered = KIRLoweringEmitContext()
        lowered.instructions.reserveCapacity(inlineTarget.body.count)
        var returnedExpr: KIRExprID?
        var hasNonLocalReturn = false
        var hasNormalReturn = false
        let inlineReturnCount = inlineTarget.body.reduce(0) { count, inst in
            switch inst {
            case .returnUnit, .returnValue: return count + 1
            default: return count
            }
        }
        let needsInlineMergeLabel = inlineReturnCount > 1
        let inlineExitLabel: Int32
        var inlineMergeResult: KIRExprID?
        if needsInlineMergeLabel {
            inlineExitLabel = labels.allocateScratchLabel()
            let hasValueReturn = inlineTarget.body.contains {
                if case .returnValue = $0 { return true }
                return false
            }
            if hasValueReturn {
                inlineMergeResult = module.arena.appendTemporary(type: substitutedInlineReturnType)
            }
        } else {
            inlineExitLabel = -1
        }

        // Slots written from more than one place are branch merge points
        // (`&&`/`||`/`?:` lower to a temporary each arm copies into). Retyping
        // one of their writers below would redirect every reader to the
        // replacement expression while the other writers keep filling the
        // original, so they are left alone.
        let mergeSlotExprs = multiplyWrittenExprs(in: inlineTarget.body)

        // Give this expansion its own label IDs, so the same function inlined
        // twice does not define one label twice. The caller relocates them
        // again on the way in (see `InlineLabelAllocator`).
        var labelRemap: [Int32: Int32] = [:]
        for instruction in inlineTarget.body {
            if case let .label(id) = instruction {
                labelRemap[id] = labels.allocateScratchLabel()
            }
        }

        let sequenceGenerateCallee = ctx.interner.intern("__kk_sequence_generate")
        for instruction in inlineTarget.body {
            switch instruction {
            case .beginBlock, .endBlock:
                continue

            case .nop:
                lowered.append(.nop)

            case let .label(id):
                lowered.append(.label(labelRemap[id] ?? id))

            case let .jump(target):
                lowered.append(.jump(labelRemap[target] ?? target))

            case let .jumpIfEqual(lhs, rhs, target):
                lowered.append(
                    .jumpIfEqual(
                        lhs: InlineExprAliasing.resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: InlineExprAliasing.resolveAlias(of: rhs, aliases: localExprMap),
                        target: labelRemap[target] ?? target
                    )
                )

            case .returnUnit:
                hasNormalReturn = true
                if needsInlineMergeLabel {
                    if inlineMergeResult == nil {
                        returnedExpr = nil
                    }
                    lowered.append(.jump(inlineExitLabel))
                } else {
                    returnedExpr = nil
                    // Preserve in lowered instructions so inlineTransform can
                    // convert it to an exit-label jump in the NLR path.
                    lowered.append(.returnUnit)
                }

            case let .returnValue(value):
                hasNormalReturn = true
                let resolved = InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap)
                if needsInlineMergeLabel, let dest = inlineMergeResult {
                    lowered.append(.copy(from: resolved, to: dest))
                    lowered.append(.jump(inlineExitLabel))
                    returnedExpr = dest
                } else {
                    returnedExpr = resolved
                    // Preserve in lowered instructions so inlineTransform can
                    // convert it to an exit-label jump in the NLR path.
                    lowered.append(.returnValue(resolved))
                }

            case let .nonLocalReturn(value):
                // Non-local return from a lambda inside this inline function.
                // Preserve it so the caller's inlineTransform can convert it
                // to a real return from the enclosing function.
                hasNonLocalReturn = true
                if let value {
                    lowered.append(.nonLocalReturn(InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap)))
                } else {
                    lowered.append(.nonLocalReturn(nil))
                }

            case let .constValue(result, value):
                if case let .symbolRef(symbol) = value,
                   let mapped = parameterValues[symbol] ?? typeParamTokenValues[symbol]
                {
                    localExprMap[result] = mapped
                    continue
                }
                if case let .symbolRef(symbol) = value,
                   let captureArgs = module.arena.lambdaCaptureArgsBySymbol[symbol],
                   !captureArgs.isEmpty
                {
                    let resolvedCaptureArgs = captureArgs.map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }
                    module.arena.registerLambdaCaptureArgs(symbol, captureArgs: resolvedCaptureArgs)
                }
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                lowered.append(.constValue(result: loweredResult, value: value))

            case let .binary(op, lhs, rhs, result):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                lowered.append(
                    .binary(
                        op: op,
                        lhs: InlineExprAliasing.resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: InlineExprAliasing.resolveAlias(of: rhs, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case let .call(symbol, callee, args, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
                let calleeStr = ctx.interner.resolve(callee)
                // Attempt to inline a lambda argument passed to this inline function.
                let resolvedLambdaParamSymbol: SymbolID? = if let symbol, lambdaParamSymbols.contains(symbol) {
                    symbol
                } else if symbol == nil, let matched = lambdaParamByCalleeName[callee] {
                    matched
                } else {
                    nil
                }
                if let lambdaParamSym = resolvedLambdaParamSymbol,
                   let argExpr = parameterValues[lambdaParamSym],
                   let lambdaFunction = resolveLambdaFunction(
                       argExpr: argExpr,
                       arena: module.arena,
                       allFunctionsBySymbol: allFunctionsBySymbol,
                       callerBody: callerBody
                   )
                {
                    let resolvedArgs = args.map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }
                    let captureArgs = module.arena.lambdaCaptureArgsBySymbol[lambdaFunction.symbol] ?? []
                    let valueArgs: [KIRExprID]
                    if ["kk_function_invoke", "kk_function_invoke_0", "kk_function_invoke_2", "kk_function_invoke_3", "kk_function_invoke_4", "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2"]
                        .contains(calleeStr)
                    {
                        valueArgs = Array(resolvedArgs.dropFirst())
                    } else {
                        valueArgs = resolvedArgs
                    }
                    let fullArgs = InlineErasedLambdaABI.unboxErasedLambdaArguments(
                        arguments: captureArgs + valueArgs,
                        lambdaFunction: lambdaFunction,
                        module: module,
                        ctx: ctx,
                        erasedCallConvention: erasedExpansionABI,
                        into: &lowered
                    )
                    if let lambdaExpansion = expandLambdaBody(
                        lambdaFunction: lambdaFunction,
                        arguments: fullArgs,
                        module: module,
                        allFunctionsBySymbol: allFunctionsBySymbol,
                        ctx: ctx,
                        labels: &labels
                    ) {
                        hasNonLocalReturn = hasNonLocalReturn || lambdaExpansion.hasNonLocalReturn
                        hasNormalReturn = hasNormalReturn || lambdaExpansion.hasNormalReturn
                        appendInlinedLambdaExpansion(
                            lambdaExpansion,
                            callThrownResult: thrownResult,
                            localExprMap: localExprMap,
                            into: &lowered
                        )
                        if let result {
                            if let lambdaReturn = lambdaExpansion.returnedExpr,
                               exprIsDefined(lambdaReturn, in: lowered.instructions)
                            {
                                localExprMap[result] = InlineErasedLambdaABI.boxErasedLambdaResultIfNeeded(
                                    returnedExpr: lambdaReturn,
                                    result: result,
                                    module: module,
                                    ctx: ctx,
                                    erasedCallConvention: erasedExpansionABI,
                                    into: &lowered
                                )
                            } else {
                                let unitExpr = module.arena.appendExpr(.unit, type: nil)
                                lowered.append(.constValue(result: unitExpr, value: .unit))
                                localExprMap[result] = unitExpr
                                unitResultAliasExprs.insert(unitExpr)
                            }
                        }
                        break
                    }
                }

                // A previously inlined function may return a direct lambda symbol.
                // If that symbol still carries capture arguments in the callee's
                // local alias map, inline its body here as well so returned
                // function values preserve their captures.
                let resolvedArgs = args.map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }
                if ["kk_function_invoke", "kk_function_invoke_0", "kk_function_invoke_2", "kk_function_invoke_3", "kk_function_invoke_4", "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2"].contains(calleeStr),
                   let callableExpr = resolvedArgs.first,
                   let lambdaFunction = resolveLambdaFunction(
                       argExpr: callableExpr,
                       arena: module.arena,
                       allFunctionsBySymbol: allFunctionsBySymbol,
                       callerBody: callerBody
                   )
                {
                    let captureArgs = (module.arena.lambdaCaptureArgsBySymbol[lambdaFunction.symbol] ?? [])
                        .map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }
                    let fullArgs = InlineErasedLambdaABI.unboxErasedLambdaArguments(
                        arguments: captureArgs + Array(resolvedArgs.dropFirst()),
                        lambdaFunction: lambdaFunction,
                        module: module,
                        ctx: ctx,
                        erasedCallConvention: erasedExpansionABI,
                        into: &lowered
                    )
                    if let lambdaExpansion = expandLambdaBody(
                        lambdaFunction: lambdaFunction,
                        arguments: fullArgs,
                        module: module,
                        allFunctionsBySymbol: allFunctionsBySymbol,
                        ctx: ctx,
                        labels: &labels
                    ) {
                        hasNonLocalReturn = hasNonLocalReturn || lambdaExpansion.hasNonLocalReturn
                        hasNormalReturn = hasNormalReturn || lambdaExpansion.hasNormalReturn
                        appendInlinedLambdaExpansion(
                            lambdaExpansion,
                            callThrownResult: thrownResult,
                            localExprMap: localExprMap,
                            into: &lowered
                        )
                        if let result {
                            if let lambdaReturn = lambdaExpansion.returnedExpr,
                               exprIsDefined(lambdaReturn, in: lowered.instructions)
                            {
                                localExprMap[result] = InlineErasedLambdaABI.boxErasedLambdaResultIfNeeded(
                                    returnedExpr: lambdaReturn,
                                    result: result,
                                    module: module,
                                    ctx: ctx,
                                    erasedCallConvention: erasedExpansionABI,
                                    into: &lowered
                                )
                            } else {
                                let unitExpr = module.arena.appendExpr(.unit, type: nil)
                                lowered.append(.constValue(result: unitExpr, value: .unit))
                                localExprMap[result] = unitExpr
                                unitResultAliasExprs.insert(unitExpr)
                            }
                        }
                        break
                    }
                }

                let loweredResult = result.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                }
                let loweredThrownResult = thrownResult.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                }
                var loweredArgs = args.map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }

                // The nullable seed branch of bundled `generateSequence` can
                // leave the bridge argument typed only as `T` after inlining.
                // Recover the concrete call-site type before the erased bridge
                // stores the seed, so enum ordinals retain their entry name.
                if callee == sequenceGenerateCallee,
                   let types = ctx.sema?.types,
                   let seed = loweredArgs.first,
                   let substitutedSeedType: TypeID? = {
                       if let seedType = module.arena.exprType(seed),
                          case .typeParam = types.kind(of: seedType),
                          let substituted = inlineTypeSubstitution?.applying(to: seedType, in: ctx),
                          substituted != seedType
                       {
                           return substituted
                       }
                       // Some in-process test pipelines do not preserve the
                       // expression type on the copy that crosses the nullable
                       // branch. `generateSequence` has one type parameter, so
                       // its inline substitution is still an unambiguous source
                       // of the concrete seed type in that representation.
                       guard let substituted = inlineTypeSubstitution?.soleSubstitutedType
                       else {
                           return nil
                       }
                       return substituted
                   }(),
                   let substitutedSeedType
                {
                    loweredArgs[0] = boxValueForAnySlot(
                        seed,
                        sourceType: substitutedSeedType,
                        types: types,
                        symbols: ctx.sema?.symbols,
                        interner: ctx.interner,
                        arena: module.arena,
                        into: &lowered
                    )
                }
                // The lambda could not be spliced, so it is reached through a
                // function value whose adapter speaks the erased convention.
                // Substituting concrete type arguments turned the values that
                // meet the invoke into plain primitives; re-erase them.
                let erasedInvoke = InlineErasedLambdaABI.erasedFunctionInvokeCallees
                    .contains(calleeStr)
                let erasedInvokeReturnType = erasedInvoke
                    ? InlineErasedLambdaABI.importedLambdaInvokeReturnType(
                        inlineTarget: inlineTarget,
                        typeSubstitution: inlineTypeSubstitution,
                        ctx: ctx
                    )
                    : nil
                if let erasedInvokeReturnType, let loweredResult {
                    // Imported inline KIR intentionally omits expression types. Restore
                    // the lambda result type before unboxing the erased invoke result.
                    module.arena.setExprType(erasedInvokeReturnType, for: loweredResult)
                }
                if erasedInvoke {
                    loweredArgs = InlineErasedLambdaABI.boxSubstitutedErasedArguments(
                        originalArguments: args,
                        loweredArguments: loweredArgs,
                        module: module,
                        ctx: ctx,
                        into: &lowered
                    )
                }
                if erasedInvoke, let result, let loweredResult,
                   let unboxCallee = InlineErasedLambdaABI.substitutedErasedResultUnboxingCallee(
                       originalResult: result,
                       loweredResult: loweredResult,
                       expectedType: erasedInvokeReturnType,
                       module: module,
                       ctx: ctx
                   )
                {
                    let boxedResult = module.arena.appendTemporary(
                        type: ctx.sema?.types.nullableAnyType ?? module.arena.exprType(result)
                    )
                    lowered.append(.call(
                        symbol: symbol,
                        callee: callee,
                        arguments: loweredArgs,
                        result: boxedResult,
                        canThrow: canThrow,
                        thrownResult: loweredThrownResult,
                        isSuperCall: isSuperCall,
                        qualifiedSuperType: qualifiedSuperType
                    ))
                    lowered.append(.call(
                        symbol: nil,
                        callee: unboxCallee,
                        arguments: [boxedResult],
                        result: loweredResult,
                        canThrow: false,
                        thrownResult: nil
                    ))
                    break
                }
                let normalizedArgs = erasedExpansionABI
                    ? InlineErasedLambdaABI.unboxErasedArithmeticArgumentsIfNeeded(
                        callee: callee,
                        arguments: loweredArgs,
                        module: module,
                        ctx: ctx,
                        into: &lowered
                    )
                    : loweredArgs
                lowered.append(
                    .call(
                        symbol: symbol,
                        callee: callee,
                        arguments: normalizedArgs,
                        result: loweredResult,
                        canThrow: canThrow,
                        thrownResult: loweredThrownResult,
                        isSuperCall: isSuperCall,
                        qualifiedSuperType: qualifiedSuperType
                    )
                )

            case let .virtualCall(symbol, callee, receiver, args, result, canThrow, thrownResult, dispatch):
                let loweredResult = result.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                }
                let loweredThrownResult = thrownResult.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                }
                lowered.append(
                    .virtualCall(
                        symbol: symbol,
                        callee: callee,
                        receiver: InlineExprAliasing.resolveAlias(of: receiver, aliases: localExprMap),
                        arguments: args.map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) },
                        result: loweredResult,
                        canThrow: canThrow,
                        thrownResult: loweredThrownResult,
                        dispatch: dispatch
                    )
                )

            case let .returnIfEqual(lhs, rhs):
                lowered.append(
                    .returnIfEqual(
                        lhs: InlineExprAliasing.resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: InlineExprAliasing.resolveAlias(of: rhs, aliases: localExprMap)
                    )
                )

            case let .jumpIfNotNull(value, target):
                lowered.append(
                    .jumpIfNotNull(
                        value: InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap),
                        target: labelRemap[target] ?? target
                    )
                )

            case let .copy(from, to):
                let resolvedFrom = InlineExprAliasing.resolveAlias(of: from, aliases: localExprMap)
                // A branch-merged slot is written by multiple arms and may be
                // read after the merge. Give its first write a stable caller
                // expression so a later call using the same serialized KIR ID
                // cannot be cloned into a different, branch-local value.
                var resolvedTo = mergeSlotExprs.contains(to)
                    ? InlineExprCloning.cloneOrReuseExpr(
                        to,
                        localExprMap: &localExprMap,
                        in: module.arena,
                        substituteType: substituteType
                    )
                    : InlineExprAliasing.resolveAlias(of: to, aliases: localExprMap)
                if !mergeSlotExprs.contains(to),
                   let fromType = module.arena.exprType(resolvedFrom),
                   shouldRetypeInlineCopyTarget(
                       currentType: module.arena.exprType(resolvedTo),
                       fromType: fromType,
                       inlineReturnType: substitutedInlineReturnType,
                       isUnitPlaceholder: unitResultAliasExprs.contains(resolvedTo),
                       ctx: ctx
                   )
                {
                    if module.arena.exprType(resolvedTo) == nil {
                        // The copy target is a freshly-cloned imported expression
                        // whose type was not serialized. Promote it to the inferred
                        // inline return type so the accumulator variable stays a
                        // single expression instead of being split into an initial
                        // value and a separately-typed replacement.
                        module.arena.setExprType(fromType, for: resolvedTo)
                    } else {
                        let replacement = module.arena.appendExpr(
                            module.arena.expr(resolvedTo) ?? .temporary(Int32(module.arena.expressions.count)),
                            type: fromType
                        )
                        let aliasKeysToUpdate = localExprMap.compactMap { key, value in
                            value == resolvedTo ? key : nil
                        }
                        for key in aliasKeysToUpdate {
                            localExprMap[key] = replacement
                        }
                        localExprMap[to] = replacement
                        unitResultAliasExprs.remove(resolvedTo)
                        resolvedTo = replacement
                    }
                }
                lowered.append(
                    .copy(
                        from: resolvedFrom,
                        to: resolvedTo
                    )
                )

            case let .storeGlobal(value, symbol):
                lowered.append(
                    .storeGlobal(
                        value: InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap),
                        symbol: symbol
                    )
                )

            case let .loadGlobal(result, symbol):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                lowered.append(.loadGlobal(result: loweredResult, symbol: symbol))

            case let .rethrow(value):
                lowered.append(
                    .rethrow(value: InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap))
                )

            case let .unary(op, operand, result):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                lowered.append(
                    .unary(
                        op: op,
                        operand: InlineExprAliasing.resolveAlias(of: operand, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case let .nullAssert(operand, result):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena, substituteType: substituteType)
                lowered.append(
                    .nullAssert(
                        operand: InlineExprAliasing.resolveAlias(of: operand, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case .beginFinallyGuard:
                lowered.append(.beginFinallyGuard)

            case .endFinallyGuard:
                lowered.append(.endFinallyGuard)
            }
        }

        if needsInlineMergeLabel {
            lowered.append(.label(inlineExitLabel))
        }

        return InlineExpansion(
            instructions: lowered.instructions,
            returnedExpr: returnedExpr,
            hasNonLocalReturn: hasNonLocalReturn,
            hasNormalReturn: hasNormalReturn
        )
    }

    private func isInlineUnitType(_ type: TypeID, ctx: KIRContext) -> Bool {
        guard let sema = ctx.sema else {
            return false
        }
        if type == sema.types.unitType {
            return true
        }
        if case .unit = sema.types.kind(of: type) {
            return true
        }
        return false
    }

    /// Expressions `body` writes from more than one instruction.
    private func multiplyWrittenExprs(in body: [KIRInstruction]) -> Set<KIRExprID> {
        var writeCounts: [KIRExprID: Int] = [:]
        for instruction in body {
            let written: KIRExprID? = switch instruction {
            case let .copy(_, to): to
            case let .call(_, _, _, result, _, _, _, _): result
            case let .virtualCall(_, _, _, _, result, _, _, _): result
            case let .binary(_, _, _, result): result
            case let .unary(_, _, result): result
            case let .constValue(result, _): result
            case let .nullAssert(_, result): result
            case let .loadGlobal(result, _): result
            default: nil
            }
            if let written {
                writeCounts[written, default: 0] += 1
            }
        }
        return Set(writeCounts.filter { $0.value > 1 }.keys)
    }

    private func shouldRetypeInlineCopyTarget(
        currentType: TypeID?,
        fromType: TypeID,
        inlineReturnType: TypeID?,
        isUnitPlaceholder: Bool,
        ctx: KIRContext
    ) -> Bool {
        if isUnitPlaceholder {
            return !isInlineUnitType(fromType, ctx: ctx)
        }
        guard let inlineReturnType,
              fromType == inlineReturnType,
              currentType != fromType
        else {
            return false
        }
        if let currentType {
            return isInlineUnitType(currentType, ctx: ctx) || currentType != inlineReturnType
        }
        return true
    }
}
