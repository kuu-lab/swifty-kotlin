extension InlineLoweringPass {
    func lambdaCaptureArguments(
        for callableExpr: KIRExprID,
        symbol: SymbolID,
        aliases: [KIRExprID: KIRExprID],
        arena: KIRArena,
        ctx: KIRContext,
        into body: inout KIRLoweringEmitContext
    ) -> [KIRExprID] {
        let callable = InlineExprAliasing.resolveAlias(of: callableExpr, aliases: aliases)
        let captures = lambdaCaptureArgsByExpr[callable]
            ?? arena.lambdaCaptureArgsBySymbol[symbol] ?? []
        let resolved = captures.map { InlineExprAliasing.resolveAlias(of: $0, aliases: aliases) }
        guard resolved.count >= 2,
              arena.callableValueInfo(for: callable)?.hasClosureParam == true,
              let types = ctx.sema?.types else { return resolved }
        // A runtime HOF lambda receives one packed environment parameter,
        // although its callable metadata lists the individual captured values.
        // Splicing those values as separate parameters would bind the final
        // capture (often a String message) as the environment object.
        let count = arena.appendExpr(.intLiteral(Int64(resolved.count + 2)), type: types.intType)
        let classID = arena.appendExpr(.intLiteral(0), type: types.intType)
        body.append(.constValue(result: count, value: .intLiteral(Int64(resolved.count + 2))))
        body.append(.constValue(result: classID, value: .intLiteral(0)))
        let environment = arena.appendTemporary(type: types.anyType)
        body.append(.call(
            symbol: nil, callee: ctx.interner.intern("kk_object_new"), arguments: [count, classID],
            result: environment, canThrow: false, thrownResult: nil
        ))
        for (index, capture) in resolved.enumerated() {
            let offset = arena.appendExpr(.intLiteral(Int64(index + 2)), type: types.intType)
            body.append(.constValue(result: offset, value: .intLiteral(Int64(index + 2))))
            body.append(.call(
                symbol: nil, callee: ctx.interner.intern("kk_array_set"), arguments: [environment, offset, capture],
                result: nil, canThrow: false, thrownResult: nil
            ))
        }
        return [environment]
    }

    func recordClonedLambdaCaptures(
        source: KIRExprID,
        cloned: KIRExprID,
        value: KIRExprKind,
        aliases: [KIRExprID: KIRExprID],
        arena: KIRArena
    ) {
        guard case let .symbolRef(symbol) = value else { return }
        // Captures belong to this reference, not to the shared lambda symbol:
        // later rounds and snapshot clones must retain this expansion's slots.
        let captures = lambdaCaptureArgsByExpr[source]
            ?? arena.lambdaCaptureArgsBySymbol[symbol] ?? []
        guard !captures.isEmpty else { return }
        let clonedCaptures = captures.map {
            InlineExprAliasing.resolveAlias(of: $0, aliases: aliases)
        }
        lambdaCaptureArgsByExpr[cloned] = clonedCaptures
        if let info = arena.callableValueInfo(for: source) {
            arena.callableValueInfoByExprID[cloned] = KIRCallableValueInfo(
                symbol: symbol,
                callee: info.callee,
                captureArguments: clonedCaptures,
                hasClosureParam: info.hasClosureParam
            )
        } else if let function = arena.function(for: symbol) {
            arena.callableValueInfoByExprID[cloned] = KIRCallableValueInfo(
                symbol: symbol,
                callee: function.name,
                captureArguments: clonedCaptures,
                hasClosureParam: false
            )
        }
    }

    private func lambdaSymbolRef(
        for expr: KIRExprID,
        arena: KIRArena,
        callerBody: [KIRInstruction]
    ) -> SymbolID? {
        if case let .symbolRef(symbol)? = arena.expr(expr) {
            return symbol
        }
        for instruction in callerBody {
            if case let .constValue(result, .symbolRef(symbol)) = instruction,
               result == expr
            {
                return symbol
            }
        }
        return nil
    }

    func resolveLambdaFunction(
        argExpr: KIRExprID,
        arena: KIRArena,
        allFunctionsBySymbol: [SymbolID: KIRFunction],
        callerBody: [KIRInstruction],
        ctx: KIRContext? = nil
    ) -> KIRFunction? {
        if let symbol = lambdaSymbolRef(for: argExpr, arena: arena, callerBody: callerBody),
           let fn = allFunctionsBySymbol[symbol]
        {
            return fn
        }
        // A callable materialized through `kk_function_create_N` wraps the
        // lambda or adapter symbol as its first argument. CoroutineLowering
        // rewrites suspend factories to `kk_suspend_function_create`, so both
        // factory forms must be visible here for inline HOF callbacks.
        if let ctx {
            for instruction in callerBody {
                guard case let .call(_, callee, arguments, result, _, _, _, _) = instruction,
                      result == argExpr,
                      let calleeName = Optional(ctx.interner.resolve(callee)),
                      calleeName.hasPrefix("kk_function_create")
                      || calleeName == "kk_suspend_function_create",
                      let first = arguments.first,
                      let symbol = lambdaSymbolRef(for: first, arena: arena, callerBody: callerBody),
                      let fn = allFunctionsBySymbol[symbol]
                else {
                    continue
                }
                // The factory call's second argument carries the captured
                // environment handed to the callable's leading closure
                // parameter. Preserve it for `lambdaCaptureArguments` when
                // the factory is expanded.
                if arguments.count > 1 {
                    lambdaCaptureArgsByExpr[argExpr] = [arguments[1]]
                }
                return fn
            }
        }
        return nil
    }

    /// Returns `nil` when the expansion cannot proceed (e.g. argument/parameter
    /// count mismatch), signalling the caller to fall back to a regular call.
    func expandLambdaBody(
        lambdaFunction: KIRFunction,
        arguments: [KIRExprID],
        module: KIRModule,
        allFunctionsBySymbol: [SymbolID: KIRFunction],
        ctx: KIRContext,
        labels: inout InlineLabelAllocator,
        expansionBudget: InlineExpansionBudget? = nil,
        externalLoopAliases: [InlineLoopLabelAliases] = []
    ) -> InlineExpansion? {
        let budget = expansionBudget ?? InlineExpansionBudget(arena: module.arena)
        guard budget.enter(lambdaFunction, arena: module.arena) else { return nil }
        defer { budget.leave() }
        guard budget.permitsAdditional(arguments.count, outputCount: 0, arena: module.arena) else { return nil }
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
        var callAncestries: [Int: [SymbolID]] = [:]
        var callExternalLoopAliases: [Int: [InlineLoopLabelAliases]] = [:]
        // Caller-supplied lambdas may legitimately call their enclosing inline function.
        let lambdaAncestry = budget.ancestry.filter { !budget.inlineSymbols.contains($0) }
        lowered.instructions.reserveCapacity(lambdaFunction.body.count)
        for param in lambdaFunction.params {
            guard let argument = lambdaParamValues[param.symbol] else { continue }
            lambdaParamValues[param.symbol] = InlineErasedLambdaABI.bindEnumArgumentToInterfaceParameter(
                argument, parameterType: param.type, module: module, ctx: ctx, into: &lowered
            )
        }
        var returnedExpr: KIRExprID?
        var hasNonLocalReturn = false
        var hasNormalReturn = false

        // Lambda bodies with control flow (if/else branches) can contain
        // multiple return instructions; breaking at the first one would
        // truncate the remaining branches.
        let returnCount = lambdaFunction.body.reduce(0) { count, inst in
            switch inst {
            case .returnUnit, .returnValue: return count + 1
            default: return count
            }
        }
        let ownsNonLocalReturn = nonLocalReturnTargets.contains(.function(lambdaFunction.symbol))
        let needsMergeLabel = returnCount > 1 || ownsNonLocalReturn
        let exitLabel: Int32
        var mergeResult: KIRExprID?
        if needsMergeLabel {
            exitLabel = labels.allocateScratchLabel()
            let hasValueReturn = lambdaFunction.body.contains {
                if case .returnValue = $0 { return true }
                return false
            }
            if hasValueReturn || ownsNonLocalReturn {
                // Uses the lambda's declared return type so later passes see
                // a properly typed merge expression.
                let returnType = lambdaFunction.returnType
                let mergeID = module.arena.appendTemporary(type: returnType
                )
                mergeResult = mergeID
                if ownsNonLocalReturn {
                    returnedExpr = mergeID
                    lowered.append(.beginNonLocalReturnScope(
                        value: mergeID, target: exitLabel, function: .function(lambdaFunction.symbol)
                    ))
                }
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
        var enclosingCallAliases = externalLoopAliases
        if !labelRemap.isEmpty {
            enclosingCallAliases.insert(
                InlineLoopLabelAliases(labels: labelRemap, needsRelocation: true), at: 0
            )
        }
        for instruction in lambdaFunction.body {
            guard budget.permitsOutput(lowered.instructions.count, arena: module.arena) else { return nil }
            let outputStart = lowered.instructions.count
            defer {
                for offset in outputStart ..< lowered.instructions.count {
                    if case .call = lowered.instructions[offset], callAncestries[offset] == nil {
                        callAncestries[offset] = lambdaAncestry
                    }
                    if case .call = lowered.instructions[offset], callExternalLoopAliases[offset] == nil {
                        callExternalLoopAliases[offset] = enclosingCallAliases
                    }
                }
            }
            switch instruction {
            case .beginBlock, .endBlock:
                continue

            case .nop:
                lowered.append(.nop)

            case let .label(id):
                lowered.append(.label(labelRemap[id] ?? id))

            case let .jump(target):
                let remappedTarget: Int32
                if let externalTarget = KIRExternalLoopJump.label(for: target) {
                    remappedTarget = KIRExternalLoopJump.marker(for: labelRemap[externalTarget] ?? externalTarget)
                } else {
                    remappedTarget = labelRemap[target] ?? target
                }
                lowered.append(.jump(remappedTarget))

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
                recordClonedLambdaCaptures(
                    source: result, cloned: loweredResult, value: value,
                    aliases: localExprMap, arena: module.arena
                )
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
                guard budget.permitsAdditional(
                    args.count + (result == nil ? 0 : 2) + (thrownResult == nil ? 0 : 1),
                    outputCount: lowered.instructions.count, arena: module.arena
                ) else { return nil }
                let resolvedArgs = args.map { InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap) }
                // Keep nested calls in the caller's pending worklist. Recursively
                // expanding inline and lambda bodies here grows the Swift stack
                // with source nesting depth.
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

            case let .nonLocalReturn(value, target):
                // Non-local return from a nested lambda. Preserve it so the
                // caller's inlineTransform can convert it to a real return.
                hasNonLocalReturn = true
                if let value {
                    lowered.append(.nonLocalReturn(InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap), target: target))
                } else {
                    lowered.append(.nonLocalReturn(nil, target: target))
                }

            case .beginFinallyGuard:
                lowered.append(.beginFinallyGuard)

            case .beginFinallyCleanup, .endFinallyCleanup:
                lowered.append(instruction)

            case let .beginNonLocalReturnScope(value, target, function):
                let slot = InlineExprCloning.cloneOrReuseExpr(value, localExprMap: &localExprMap, in: module.arena)
                lowered.append(.beginNonLocalReturnScope(value: slot, target: labelRemap[target] ?? target, function: function))

            case .endNonLocalReturnScope:
                lowered.append(.endNonLocalReturnScope)

            case let .resumeNonLocalReturn(value):
                lowered.append(.resumeNonLocalReturn(InlineExprAliasing.resolveAlias(of: value, aliases: localExprMap)))

            case .endFinallyGuard:
                lowered.append(.endFinallyGuard)
            }
        }

        if needsMergeLabel {
            lowered.append(.label(exitLabel))
            if ownsNonLocalReturn { lowered.append(.endNonLocalReturnScope) }
        }

        guard budget.permitsOutput(lowered.instructions.count, arena: module.arena) else { return nil }
        return InlineExpansion(
            instructions: lowered.instructions,
            returnedExpr: returnedExpr,
            hasNonLocalReturn: hasNonLocalReturn,
            hasNormalReturn: hasNormalReturn,
            callAncestries: callAncestries,
            callExternalLoopAliases: callExternalLoopAliases
        )
    }

    /// Splice a lambda expansion in place of a call that already owns a local
    /// exception slot, routing the lambda body's throws into that slot so the
    /// surrounding inline try/catch can observe them.
    func appendInlinedLambdaExpansion(
        _ lambdaExpansion: InlineExpansion,
        callThrownResult: KIRExprID?,
        localExprMap: [KIRExprID: KIRExprID],
        labels: inout InlineLabelAllocator,
        callAncestries: inout [Int: [SymbolID]],
        callExternalLoopAliases: inout [Int: [InlineLoopLabelAliases]],
        into lowered: inout KIRLoweringEmitContext
    ) {
        let routedSlot = callThrownResult.map {
            InlineExprAliasing.resolveAlias(of: $0, aliases: localExprMap)
        }
        if let routedSlot {
            lowered.append(.constValue(result: routedSlot, value: .null))
        }
        // Stop at the first uncaught throw. Continuing through the expanded
        // lambda can overwrite the slot before the original invoke's catch
        // dispatch observes it (for example recover inside runCatching).
        let dispatchLabel = routedSlot == nil ? nil : labels.allocateScratchLabel()
        let routed = InlineThrowRerouting.rerouteUnprotectedThrows(
            in: lambdaExpansion.instructions,
            callerThrownResult: routedSlot,
            labels: &labels,
            dispatchLabel: dispatchLabel
        )
        let paths = lambdaExpansion.callPaths
        let aliasPaths = lambdaExpansion.callExternalLoopAliasPaths
        var callIndex = 0
        for instruction in routed.instructions {
            if case .call = instruction {
                callAncestries[lowered.instructions.count] = paths[callIndex]
                callExternalLoopAliases[lowered.instructions.count] = aliasPaths[callIndex]
                callIndex += 1
            }
            lowered.append(instruction)
        }
        if let label = routed.throwDispatchLabel {
            lowered.append(.label(label))
        }
    }
}
