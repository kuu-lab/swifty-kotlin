struct InlineExpansion {
    let instructions: [KIRInstruction]
    let returnedExpr: KIRExprID?
    let hasNonLocalReturn: Bool
    let hasNormalReturn: Bool
    var callAncestries: [Int: [SymbolID]] = [:]
    var callExternalLoopAliases: [Int: [InlineLoopLabelAliases]] = [:]

    var callPaths: [[SymbolID]] {
        instructions.enumerated().compactMap { offset, instruction in
            guard case .call = instruction else { return nil }
            return callAncestries[offset] ?? []
        }
    }

    var callExternalLoopAliasPaths: [[InlineLoopLabelAliases]] {
        instructions.enumerated().compactMap { offset, instruction in
            guard case .call = instruction else { return nil }
            return callExternalLoopAliases[offset] ?? []
        }
    }

    func remappingExternalLoopTargets(using aliases: [InlineLoopLabelAliases]) -> InlineExpansion {
        var mapping: [Int32: Int32] = [:]
        for alias in aliases {
            for (label, remappedLabel) in alias.labels where mapping[label] == nil {
                mapping[label] = remappedLabel
            }
        }
        return InlineExpansion(
            instructions: KIRExternalLoopJump.remappingTargets(in: instructions, mapping: mapping),
            returnedExpr: returnedExpr,
            hasNonLocalReturn: hasNonLocalReturn,
            hasNormalReturn: hasNormalReturn,
            callAncestries: callAncestries,
            callExternalLoopAliases: callExternalLoopAliases
        )
    }

    func remappingCallExternalLoopAliases(using mapping: [Int32: Int32]) -> InlineExpansion {
        var remappedAliases = callExternalLoopAliases
        for (offset, aliases) in remappedAliases {
            remappedAliases[offset] = aliases.map { alias in
                guard alias.needsRelocation else { return alias }
                return InlineLoopLabelAliases(
                    labels: alias.labels.mapValues { mapping[$0] ?? $0 },
                    needsRelocation: false
                )
            }
        }
        return InlineExpansion(
            instructions: instructions,
            returnedExpr: returnedExpr,
            hasNonLocalReturn: hasNonLocalReturn,
            hasNormalReturn: hasNormalReturn,
            callAncestries: callAncestries,
            callExternalLoopAliases: remappedAliases
        )
    }
}

struct InlineLoopLabelAliases {
    var labels: [Int32: Int32]
    var needsRelocation: Bool
}

struct InlinePendingCall {
    var ancestry: [SymbolID]
    var externalLoopAliases: [InlineLoopLabelAliases] = []
}

final class InlineLoweringPass: LoweringPass {
    var lambdaCaptureArgsByExpr: [KIRExprID: [KIRExprID]] = [:]
    var nonLocalReturnTargets: Set<KIRReturnTarget> = []
    var functionInvokeCallees: Set<InternedString> = []
    let stats = InlinePerfStats()

    static let name = "InlineLowering"
    static let requiredStage: KIRStage = .propertyLowered
    static let producedStage: KIRStage = .propertyLowered

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        if module.features.contains(.hasInlineFunction) { return true }
        if let imported = ctx.sema?.importedInlineFunctions, !imported.isEmpty {
            return true
        }
        return module.arena.declarations.contains { declaration in
            guard case let .function(function) = declaration else { return false }
            return function.body.contains { instruction in
                if case .beginNonLocalReturnScope = instruction { return true }
                return false
            }
        }
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        lambdaCaptureArgsByExpr.removeAll(keepingCapacity: true)
        nonLocalReturnTargets = Set(module.arena.declarations.flatMap { declaration -> [KIRReturnTarget] in
            guard case let .function(function) = declaration else { return [] }
            return function.body.compactMap { instruction in
                if case let .nonLocalReturn(_, target) = instruction { return target }
                return nil
            }
        })
        let unitType = ctx.sema?.types.unitType
        _ = stats.takeSplit()
        let index = InlineExpansionIndex(
            module: module,
            importedInlineFunctions: ctx.sema?.importedInlineFunctions ?? ImportedInlineFunctionStore(),
            reifiedEnumValuesCallee: ctx.interner.intern("$reifiedEnumValues")
        )
        index.retainRecursiveAutoInlineBodies(module: module, sema: ctx.sema)
        stats.indexNanos += stats.takeSplit()

        // An inline body — or a lambda body that gets spliced into its caller —
        // can itself call a bodyless function. The snapshots predate any
        // expansion, so splicing such a body into a caller would leave a
        // call to a symbol that no object file defines. Expand those nested
        // calls inside the snapshots first.
        expandNestedBodylessInlineCalls(
            index: index,
            module: module,
            ctx: ctx,
            unitType: unitType
        )
        stats.nestedBodylessNanos += stats.takeSplit()

        let inlineFunctionsByName = index.inlineFunctionsByName

        module.arena.transformFunctions { [self] function in
            inlineTransform(
                function: function,
                index: index,
                inlineFunctionsByName: inlineFunctionsByName,
                module: module,
                ctx: ctx,
                unitType: unitType
            )
        }
        stats.transformNanos += stats.takeSplit()
        diagnoseMandatoryInlineResidue(module: module, index: index, ctx: ctx)
        stats.residueNanos += stats.takeSplit()
        stats.printIfEnabled()
        module.recordLowering(Self.name)
    }

    func expandInlineCalls(
        in callerBody: [KIRInstruction],
        callerLocations: [SourceRange?],
        function: KIRFunction,
        index: InlineExpansionIndex,
        inlineFunctionsByName: [InternedString: [SymbolID]],
        module: KIRModule,
        ctx: KIRContext,
        unitType: TypeID?,
        pending: [Int: InlinePendingCall],
        budget: InlineExpansionBudget) -> (body: [KIRInstruction], locations: [SourceRange?], didExpand: Bool, pending: [Int: InlinePendingCall]) {
        stats.expandRounds += 1
        stats.expandRoundInstructions += callerBody.count
        var labels = InlineLabelAllocator(callerBody: callerBody)
        if labels.hasOverflowed {
            ctx.diagnostics.error(
                "KSWIFTK-KIR-0003",
                "Inline label allocator overflow in function '\(ctx.interner.resolve(function.name))'",
                range: function.sourceRange
            )
            return (callerBody, callerLocations, false, [:])
        }

        var loweredBody = KIRLoweringEmitContext()
        loweredBody.instructions.reserveCapacity(callerBody.count)
        var aliases: [KIRExprID: KIRExprID] = [:]
        var didExpand = false
        var nextPending: [Int: InlinePendingCall] = [:]
        let callerBodyIndex = InlineCallerBodyIndex(body: callerBody, stats: stats)
        var emittedDefinedExprs = InlineDefinedExprIndex(stats: stats)

        for (instructionIndex, originalInstruction) in callerBody.enumerated() {
            let outputStart = loweredBody.instructions.count
            let pendingCall = pending[instructionIndex]
            let ancestry = pendingCall?.ancestry
            var expandedSymbol: SymbolID?
            var emittedCallAncestries: [Int: [SymbolID]] = [:]
            var emittedCallExternalLoopAliases: [Int: [InlineLoopLabelAliases]] = [:]
            var retryInvoke = false
            defer {
                if let ancestry {
                    for offset in outputStart ..< loweredBody.instructions.count {
                        guard case .call = loweredBody.instructions[offset] else { continue }
                        if let expandedSymbol {
                            let path = emittedCallAncestries[offset] ?? (ancestry + [expandedSymbol])
                            if budget.consumeWork(path.count, arena: module.arena) {
                                nextPending[offset] = InlinePendingCall(
                                    ancestry: path,
                                    externalLoopAliases: emittedCallExternalLoopAliases[offset]
                                        ?? pendingCall?.externalLoopAliases
                                        ?? []
                                )
                            }
                        } else if retryInvoke {
                            nextPending[offset] = pendingCall
                        }
                    }
                }
            }
            loweredBody.currentSourceRange = instructionIndex < callerLocations.count
                ? callerLocations[instructionIndex]
                : nil
            let instruction = InlineExprAliasing.rewriteInstruction(originalInstruction, aliases: aliases)
            if let defined = InlineExprAliasing.definedResult(in: instruction) {
                aliases.removeValue(forKey: defined)
            }

            guard case let .call(symbol, callee, arguments, result, _, callerThrownResult, _, _) = instruction else {
                loweredBody.append(instruction)
                continue
            }

            guard let ancestry,
                  budget.consumeWork(ancestry.count, arena: module.arena),
                  budget.permitsOutput(loweredBody.instructions.count, arena: module.arena) else {
                loweredBody.append(instruction)
                continue
            }
            budget.ancestry = ancestry

            let resolvedArguments = arguments.map { InlineExprAliasing.resolveAlias(of: $0, aliases: aliases) }
            retryInvoke = functionInvokeCallees.contains(callee)
            if retryInvoke,
               let callableExpr = resolvedArguments.first,
               let lambdaFunction = resolveLambdaFunction(
                   argExpr: callableExpr,
                   arena: module.arena,
                   allFunctionsBySymbol: index.allFunctionsBySymbol,
                   callerBodyIndex: callerBodyIndex,
                   ctx: ctx
               )
            {
                guard !ancestry.contains(lambdaFunction.symbol) else {
                    loweredBody.append(instruction)
                    retryInvoke = false
                    continue
                }
                let captureArgs = lambdaCaptureArguments(
                    for: callableExpr, symbol: lambdaFunction.symbol,
                    aliases: aliases, arena: module.arena, ctx: ctx, into: &loweredBody
                )
                guard budget.permitsAdditional(
                    captureArgs.count + resolvedArguments.count,
                    outputCount: loweredBody.instructions.count, arena: module.arena
                ) else {
                    loweredBody.append(instruction)
                    retryInvoke = false
                    continue
                }
                let fullArgs = InlineErasedLambdaABI.unboxErasedLambdaArguments(
                    arguments: captureArgs + Array(resolvedArguments.dropFirst()),
                    lambdaFunction: lambdaFunction,
                    module: module,
                    ctx: ctx,
                    into: &loweredBody
                )
                if let lambdaExpansion = expandLambdaBody(
                    lambdaFunction: lambdaFunction,
                    arguments: fullArgs,
                    module: module,
                    ctx: ctx,
                    labels: &labels,
                    expansionBudget: budget,
                    externalLoopAliases: pendingCall?.externalLoopAliases ?? []
                ) {
                    let expandedLambda = lambdaExpansion.remappingExternalLoopTargets(
                        using: pendingCall?.externalLoopAliases ?? []
                    )
                    if let callerThrownResult {
                        loweredBody.append(.constValue(result: callerThrownResult, value: .null))
                    }
                    var relocation: [Int32: Int32] = [:]
                    let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
                        in: labels.relocate(expandedLambda.instructions, labelMapping: &relocation),
                        callerThrownResult: callerThrownResult,
                        labels: &labels
                    )
                    let relocatedLambda = expandedLambda.remappingCallExternalLoopAliases(using: relocation)
                    let paths = relocatedLambda.callPaths
                    let aliasPaths = relocatedLambda.callExternalLoopAliasPaths
                    var callIndex = 0
                    for instruction in reroutedInstructions {
                        if case .call = instruction {
                            emittedCallAncestries[loweredBody.instructions.count] = paths[callIndex]
                            emittedCallExternalLoopAliases[loweredBody.instructions.count] = aliasPaths[callIndex]
                            callIndex += 1
                        }
                        loweredBody.append(instruction)
                    }
                    didExpand = true
                    expandedSymbol = lambdaFunction.symbol
                    if let throwDispatchLabel {
                        loweredBody.append(.label(throwDispatchLabel))
                    }
                    if let result {
                        // The lambda may return through a non-local return on
                        // every path, in which case `returnedExpr` refers to a
                        // slot no emitted instruction defines. Read it only
                        // when a definition actually survives in the body.
                        if let lambdaReturn = lambdaExpansion.returnedExpr.map({ InlineExprAliasing.resolveAlias(of: $0, aliases: aliases) }),
                           emittedDefinedExprs.contains(lambdaReturn, in: loweredBody.instructions)
                        {
                            let finalExpr = InlineErasedLambdaABI.boxErasedLambdaResultIfNeeded(
                                returnedExpr: lambdaReturn,
                                result: result,
                                module: module,
                                ctx: ctx,
                                into: &loweredBody
                            )
                            loweredBody.append(.copy(from: finalExpr, to: result))
                        } else if let unitType = unitType {
                            let unitExpr = module.arena.appendExpr(.unit, type: unitType)
                            loweredBody.append(.copy(from: unitExpr, to: result))
                        } else {
                            let unitExpr = module.arena.appendExpr(.unit, type: nil)
                            loweredBody.append(.copy(from: unitExpr, to: result))
                        }
                    }
                    if labels.hasOverflowed {
                        ctx.diagnostics.error(
                            "KSWIFTK-KIR-0003",
                            "Inline label allocator overflow in function '\(ctx.interner.resolve(function.name))'",
                            range: function.sourceRange
                        )
                        return (callerBody, callerLocations, false, [:])
                    }
                    continue
                }
            }

            // Reified enumValues carries a token rather than value arguments.
            // Keep it intact for specialization after all nested inline calls;
            // expanding the bundled placeholder would inline its throw body.
            if let symbol, ctx.sema?.wellKnownSymbols.enumIntrinsic(for: symbol) == .enumValues,
               arguments.count == 1 {
                loweredBody.append(instruction)
                continue
            }

            let inlineTarget = index.inlineTarget(
                callSymbol: symbol,
                callee: callee,
                inlineFunctionsByName: inlineFunctionsByName
            )

            guard let inlineTarget, !ancestry.contains(inlineTarget.symbol) else {
                loweredBody.append(instruction)
                continue
            }
            // An imported inline body was ABI-lowered when its library was
            // built, so its erased (type-parameter / Any) parameters keep the
            // boxed representation chosen there; this expansion cannot
            // re-specialize them. Box primitive arguments that flow into an
            // erased parameter so the splice honours that representation.
            // Body-derived facts are shared across every site of this callee
            // instead of being rescanned per expansion (KUU-3777).
            let calleeFacts = index.facts(for: inlineTarget, sema: ctx.sema)
            let usesErasedABI = calleeFacts.usesErasedLambdaABI
            guard !usesErasedABI || budget.permitsAdditional(
                arguments.count, outputCount: loweredBody.instructions.count, arena: module.arena
            ) else {
                loweredBody.append(instruction)
                continue
            }
            let expansionArguments = usesErasedABI
                ? InlineErasedLambdaABI.boxPrimitiveArgumentsForErasedParameters(
                    arguments: arguments,
                    inlineTarget: inlineTarget,
                    module: module,
                    ctx: ctx,
                    into: &loweredBody
                )
                : arguments
            let expansion = expandInlineCall(
                inlineTarget: inlineTarget,
                arguments: expansionArguments,
                allFunctionsBySymbol: index.allFunctionsBySymbol,
                module: module,
                ctx: ctx,
                callerBodyIndex: callerBodyIndex,
                calleeFacts: calleeFacts,
                labels: &labels,
                expansionBudget: budget,
                externalLoopAliases: pendingCall?.externalLoopAliases ?? []
            )
            guard let expansion else {
                loweredBody.append(instruction)
                continue
            }
            didExpand = true
            expandedSymbol = inlineTarget.symbol

            var relocation: [Int32: Int32] = [:]
            let remappedInstructions = labels.relocate(expansion.instructions, labelMapping: &relocation)
            let relocatedExpansion = expansion.remappingCallExternalLoopAliases(using: relocation)

            if let callerThrownResult {
                loweredBody.append(.constValue(result: callerThrownResult, value: .null))
            }

            // Redirect any throw inside the expansion that isn't already routed to
            // a local exception slot, so it reaches the caller's enclosing try
            // (see `InlineThrowRerouting`) instead of silently escaping the
            // caller via codegen's unrouted-throw auto-propagation.
            let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
                in: remappedInstructions,
                callerThrownResult: callerThrownResult,
                labels: &labels
            )
            let callPaths = relocatedExpansion.callPaths
            let callAliasPaths = relocatedExpansion.callExternalLoopAliasPaths
            var callIndex = 0

            if expansion.hasNonLocalReturn {

                let hasFallthroughPath = expansion.hasNormalReturn
                let exitLabel: Int32? = hasFallthroughPath ? labels.allocateCallerLabel() : nil

                var afterTerminator = false

                for expandedInstruction in reroutedInstructions {
                    let callPath: [SymbolID]?
                    let callAliases: [InlineLoopLabelAliases]?
                    if case .call = expandedInstruction {
                        callPath = callPaths[callIndex]
                        callAliases = callAliasPaths[callIndex]
                        callIndex += 1
                    } else {
                        callPath = nil
                        callAliases = nil
                    }
                    if afterTerminator {
                        switch expandedInstruction {
                        case .beginNonLocalReturnScope, .endNonLocalReturnScope,
                             .beginFinallyCleanup, .endFinallyCleanup, .beginFinallyGuard, .endFinallyGuard:
                            loweredBody.append(expandedInstruction)
                        default:
                            break
                        }
                        if case .label = expandedInstruction {
                            afterTerminator = false
                            loweredBody.append(expandedInstruction)
                        }
                        continue
                    }

                    switch expandedInstruction {
                    case let .nonLocalReturn(value, target):
                        loweredBody.append(.nonLocalReturn(value.map {
                            InlineExprAliasing.resolveAlias(of: $0, aliases: aliases)
                        }, target: target))
                        afterTerminator = true
                    case .resumeNonLocalReturn:
                        loweredBody.append(expandedInstruction)
                        afterTerminator = true
                    case .label:
                        loweredBody.append(expandedInstruction)
                    case .returnValue, .returnUnit:
                        if let exitLabel {
                            loweredBody.append(.jump(exitLabel))
                        }
                        afterTerminator = true
                    case .returnIfEqual:
                        if let exitLabel, case let .returnIfEqual(lhs, rhs) = expandedInstruction {
                            loweredBody.append(.jumpIfEqual(lhs: lhs, rhs: rhs, target: exitLabel))
                        }
                    default:
                        if let callPath {
                            emittedCallAncestries[loweredBody.instructions.count] = callPath
                            emittedCallExternalLoopAliases[loweredBody.instructions.count] = callAliases ?? []
                        }
                        loweredBody.append(expandedInstruction)
                    }
                }

                if let exitLabel {
                    loweredBody.append(.label(exitLabel))
                }
            } else {
                let filtered = reroutedInstructions.filter { inst in
                    switch inst {
                    case .returnValue, .returnUnit:
                        return false
                    default:
                        return true
                    }
                }
                for instruction in filtered {
                    if case .call = instruction {
                        emittedCallAncestries[loweredBody.instructions.count] = callPaths[callIndex]
                        emittedCallExternalLoopAliases[loweredBody.instructions.count] = callAliasPaths[callIndex]
                        callIndex += 1
                    }
                    loweredBody.append(instruction)
                }
            }

            if let throwDispatchLabel {
                loweredBody.append(.label(throwDispatchLabel))
            }

            // Copy the expansion's returned expression into the call result so the
            // result register remains valid across basic-block merges (e.g. safe-call
            // null branches). Aliasing it globally would leak the non-null branch's
            // value into the null branch.
            if let result {
                // An expansion whose every path returns non-locally leaves
                // `returnedExpr` (e.g. the merge slot) without a surviving
                // definition — the dead-code filter above drops its writers.
                // Fall back to unit instead of reading an undefined slot.
                if let returnedExpr = expansion.returnedExpr.map({ InlineExprAliasing.resolveAlias(of: $0, aliases: aliases) }),
                   emittedDefinedExprs.contains(returnedExpr, in: loweredBody.instructions)
                {
                    let finalExpr = InlineErasedLambdaABI.unboxErasedInlineResultIfNeeded(
                        returnedExpr: returnedExpr,
                        result: result,
                        inlineTarget: inlineTarget,
                        module: module,
                        ctx: ctx,
                        into: &loweredBody
                    )
                    loweredBody.append(.copy(from: finalExpr, to: result))
                } else {
                    let unitExpr = module.arena.appendExpr(.unit, type: unitType)
                    loweredBody.append(.copy(from: unitExpr, to: result))
                }
            }
            if labels.hasOverflowed {
                ctx.diagnostics.error(
                    "KSWIFTK-KIR-0003",
                    "Inline label allocator overflow in function '\(ctx.interner.resolve(function.name))'",
                    range: function.sourceRange
                )
                return (callerBody, callerLocations, false, [:])
            }
        }

        if labels.hasOverflowed {
            ctx.diagnostics.error(
                "KSWIFTK-KIR-0003",
                "Inline label allocator overflow in function '\(ctx.interner.resolve(function.name))'",
                range: function.sourceRange
            )
            return (callerBody, callerLocations, false, [:])
        }

        guard budget.permitsOutput(loweredBody.instructions.count, arena: module.arena) else {
            return (callerBody, callerLocations, false, [:])
        }
        return (loweredBody.instructions, loweredBody.instructionLocations, didExpand, nextPending)
    }
}
