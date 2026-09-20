/// Resolution and expansion of non-inline lambda bodies passed to inline
/// functions.
///
/// `resolveLambdaFunction` finds the `KIRFunction` behind a call argument --
/// either a direct `symbolRef` on the argument expression, or a temporary
/// defined by a `constValue` carrying a `symbolRef` payload -- so lambda
/// inlining works regardless of how the argument was materialized.
/// `expandLambdaBody` then splices that body into the caller: leading
/// parameters not covered by the call arguments are captures already bound
/// at the call site, extra leading arguments are a receiver prepended to a
/// receiver-lambda call, normal returns are merged through an exit label
/// when the body has more than one, and `nonLocalReturn` markers pass
/// through so the caller's `inlineTransform` can convert them. Nested
/// `kk_function_invoke` sites inside the body recurse through the same
/// resolve/expand pair. `appendInlinedLambdaExpansion` splices a finished
/// expansion while routing its throws into an existing local exception
/// slot via `InlineThrowRerouting`.
extension InlineLoweringPass {
    /// Resolve the lambda function for an argument expression. The argument
    /// expression may be a direct `symbolRef` pointing to a lambda KIR function,
    /// or it may be a temporary that was defined via a `constValue` instruction
    /// carrying a `symbolRef` payload. Both patterns are resolved here so that
    /// lambda inlining works regardless of how the call argument was materialized.
    func resolveLambdaFunction(
        argExpr: KIRExprID,
        arena: KIRArena,
        allFunctionsBySymbol: [SymbolID: KIRFunction],
        callerBody: [KIRInstruction]
    ) -> KIRFunction? {
        // Direct symbolRef on the expression itself (most common path).
        if case let .symbolRef(lambdaSymbol)? = arena.expr(argExpr) {
            if let fn = allFunctionsBySymbol[lambdaSymbol] {
                return fn
            }
        }
        // Fall back: scan the caller body for a constValue that defines this
        // expression with a symbolRef value. This handles cases where the
        // argument is a temporary assigned via `.constValue(result: argExpr,
        // value: .symbolRef(symbol))`.
        for instruction in callerBody {
            if case let .constValue(result, .symbolRef(symbol)) = instruction,
               result == argExpr,
               let fn = allFunctionsBySymbol[symbol]
            {
                return fn
            }
        }
        return nil
    }

    /// Expand a lambda function body inline, substituting parameters with the
    /// provided call arguments. This is analogous to `expandInlineCall` but
    /// operates on non-inline lambda functions that are passed as arguments to
    /// inline functions.
    ///
    /// Returns `nil` when the expansion cannot proceed (e.g. argument/parameter
    /// count mismatch), signalling the caller to fall back to a regular call.
    func expandLambdaBody(
        lambdaFunction: KIRFunction,
        arguments: [KIRExprID],
        module: KIRModule,
        allFunctionsBySymbol: [SymbolID: KIRFunction],
        ctx: KIRContext,
        labels: inout InlineLabelAllocator
    ) -> InlineExpansion? {
        // Map lambda parameters to arguments. If the argument count does not
        // match the parameter count, skip capture parameters at the front and
        // map only the trailing value parameters.
        var lambdaParamValues: [SymbolID: KIRExprID] = [:]
        let paramCount = lambdaFunction.params.count
        if arguments.count == paramCount {
            for (param, arg) in zip(lambdaFunction.params, arguments) {
                lambdaParamValues[param.symbol] = arg
            }
        } else if arguments.count < paramCount {
            // The call supplies only value arguments; the leading parameters
            // are captures that were already bound at the call site.
            let offset = paramCount - arguments.count
            for i in 0 ..< arguments.count {
                lambdaParamValues[lambdaFunction.params[offset + i].symbol] = arguments[i]
            }
        } else {
            // More arguments than parameters.  This can happen when a
            // receiver-lambda (e.g. `StringBuilder.() -> Unit`) is invoked
            // with the receiver prepended as the first argument.  Map only
            // the trailing parameters and ignore the leading receiver args.
            let offset = arguments.count - paramCount
            for i in 0 ..< paramCount {
                lambdaParamValues[lambdaFunction.params[i].symbol] = arguments[offset + i]
            }
        }

        var localExprMap: [KIRExprID: KIRExprID] = [:]
        var lowered = KIRLoweringEmitContext()
        lowered.instructions.reserveCapacity(lambdaFunction.body.count)
        var returnedExpr: KIRExprID?
        var hasNonLocalReturn = false
        var hasNormalReturn = false

        // Count return instructions to decide whether we need a merge label.
        // Lambda bodies with control flow (if/else branches) can contain
        // multiple return instructions; breaking at the first one would
        // truncate the remaining branches.
        let returnCount = lambdaFunction.body.reduce(0) { count, inst in
            switch inst {
            case .returnUnit, .returnValue: return count + 1
            default: return count
            }
        }
        let needsMergeLabel = returnCount > 1
        let exitLabel: Int32
        var mergeResult: KIRExprID?
        if needsMergeLabel {
            exitLabel = labels.allocateScratchLabel()
            // For value-returning lambdas, allocate a merge expression to
            // hold the returned value from whichever branch executes.
            let hasValueReturn = lambdaFunction.body.contains {
                if case .returnValue = $0 { return true }
                return false
            }
            if hasValueReturn {
                // Allocate a fresh merge temporary for the returned value.
                // Uses the lambda's declared return type so later passes see
                // a properly typed merge expression.
                let returnType = lambdaFunction.returnType
                let mergeID = module.arena.appendTemporary(type: returnType
                )
                mergeResult = mergeID
            }
        } else {
            exitLabel = -1
        }

        // Give this expansion its own label IDs, so the same lambda spliced
        // twice does not define one label twice. The caller relocates them
        // again on the way in (see `InlineLabelAllocator`).
        var labelRemap: [Int32: Int32] = [:]
        for instruction in lambdaFunction.body {
            if case let .label(id) = instruction {
                labelRemap[id] = labels.allocateScratchLabel()
            }
        }

        for instruction in lambdaFunction.body {
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
                if needsMergeLabel {
                    if mergeResult == nil {
                        returnedExpr = nil
                    }
                    lowered.append(.jump(exitLabel))
                } else {
                    returnedExpr = nil
                }

            case let .returnValue(value):
                hasNormalReturn = true
                let resolved = InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap)
                if needsMergeLabel, let dest = mergeResult {
                    lowered.append(.copy(from: resolved, to: dest))
                    lowered.append(.jump(exitLabel))
                    returnedExpr = dest
                } else {
                    returnedExpr = resolved
                }

            case let .constValue(result, value):
                if case let .symbolRef(symbol) = value,
                   let mapped = lambdaParamValues[symbol]
                {
                    localExprMap[result] = mapped
                    continue
                }
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena)
                lowered.append(.constValue(result: loweredResult, value: value))

            case let .binary(op, lhs, rhs, result):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena)
                lowered.append(
                    .binary(
                        op: op,
                        lhs: InlineExprAliasing.resolveAlias(of: lhs, aliases: localExprMap),
                        rhs: InlineExprAliasing.resolveAlias(of: rhs, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case let .call(symbol, callee, args, result, canThrow, thrownResult, isSuperCall, qualifiedSuperType):
                let resolvedArgs = args.map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }
                if ["kk_function_invoke", "kk_function_invoke_0", "kk_function_invoke_2", "kk_function_invoke_3", "kk_function_invoke_4", "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2"].contains(ctx.interner.resolve(callee)),
                   let callableExpr = resolvedArgs.first,
                   let nestedLambdaFunction = resolveLambdaFunction(
                       argExpr: callableExpr,
                       arena: module.arena,
                       allFunctionsBySymbol: allFunctionsBySymbol,
                       callerBody: lambdaFunction.body
                   )
                {
                    let captureArgs = (module.arena.lambdaCaptureArgsBySymbol[nestedLambdaFunction.symbol] ?? [])
                        .map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }
                    let fullArgs = captureArgs + Array(resolvedArgs.dropFirst())
                    if let lambdaExpansion = expandLambdaBody(
                        lambdaFunction: nestedLambdaFunction,
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
                            if let lambdaReturn = lambdaExpansion.returnedExpr {
                                localExprMap[result] = lambdaReturn
                            } else {
                                let unitExpr = module.arena.appendExpr(.unit, type: nil)
                                lowered.append(.constValue(result: unitExpr, value: .unit))
                                localExprMap[result] = unitExpr
                            }
                        }
                        break
                    }
                }
                let loweredResult = result.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena)
                }
                let loweredThrownResult = thrownResult.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena)
                }
                lowered.append(
                    .call(
                        symbol: symbol,
                        callee: callee,
                        arguments: resolvedArgs,
                        result: loweredResult,
                        canThrow: canThrow,
                        thrownResult: loweredThrownResult,
                        isSuperCall: isSuperCall,
                        qualifiedSuperType: qualifiedSuperType
                    )
                )

            case let .virtualCall(symbol, callee, receiver, args, result, canThrow, thrownResult, dispatch):
                let loweredResult = result.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena)
                }
                let loweredThrownResult = thrownResult.map { expr -> KIRExprID in
                    InlineExprCloning.cloneOrReuseExpr(expr, localExprMap: &localExprMap, in: module.arena)
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
                // A copy defines its destination, so it clones like a call's
                // result rather than merely resolving an alias: a temporary
                // written from more than one branch (`&&`/`||`/`?:`) would
                // otherwise be cloned by whichever branch happened to be
                // rewritten into a call first and left dangling in the others.
                let loweredFrom = InlineExprAliasing.resolveAlias(of: from, aliases: localExprMap)
                let loweredTo = InlineExprCloning.cloneOrReuseExpr(to, localExprMap: &localExprMap, in: module.arena)
                lowered.append(.copy(from: loweredFrom, to: loweredTo))

            case let .storeGlobal(value, symbol):
                lowered.append(
                    .storeGlobal(
                        value: InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap),
                        symbol: symbol
                    )
                )

            case let .loadGlobal(result, symbol):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena)
                lowered.append(.loadGlobal(result: loweredResult, symbol: symbol))

            case let .rethrow(value):
                lowered.append(
                    .rethrow(value: InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap))
                )

            case let .unary(op, operand, result):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena)
                lowered.append(
                    .unary(
                        op: op,
                        operand: InlineExprAliasing.resolveAlias(of: operand, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case let .nullAssert(operand, result):
                let loweredResult = InlineExprCloning.cloneOrReuseExpr(result, localExprMap: &localExprMap, in: module.arena)
                lowered.append(
                    .nullAssert(
                        operand: InlineExprAliasing.resolveAlias(of: operand, aliases: localExprMap),
                        result: loweredResult
                    )
                )

            case let .nonLocalReturn(value):
                // Non-local return from a nested lambda. Preserve it so the
                // caller's inlineTransform can convert it to a real return.
                hasNonLocalReturn = true
                if let value {
                    lowered.append(.nonLocalReturn(InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap)))
                } else {
                    lowered.append(.nonLocalReturn(nil))
                }

            case .beginFinallyGuard:
                lowered.append(.beginFinallyGuard)

            case .endFinallyGuard:
                lowered.append(.endFinallyGuard)
            }
        }

        // Emit merge label so all branches converge after the inlined body.
        if needsMergeLabel {
            lowered.append(.label(exitLabel))
        }

        return InlineExpansion(
            instructions: lowered.instructions,
            returnedExpr: returnedExpr,
            hasNonLocalReturn: hasNonLocalReturn,
            hasNormalReturn: hasNormalReturn
        )
    }

    /// Splice a lambda expansion in place of a call that already owns a local
    /// exception slot, routing the lambda body's throws into that slot so the
    /// surrounding inline try/catch can observe them.
    func appendInlinedLambdaExpansion(
        _ lambdaExpansion: InlineExpansion,
        callThrownResult: KIRExprID?,
        localExprMap: [KIRExprID: KIRExprID],
        into lowered: inout KIRLoweringEmitContext
    ) {
        let routedSlot = callThrownResult.map {
            InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap)
        }
        lowered.append(contentsOf: InlineThrowRerouting.routeUnprotectedThrowsToSlot(
            in: lambdaExpansion.instructions,
            thrownSlot: routedSlot
        ))
    }
}
