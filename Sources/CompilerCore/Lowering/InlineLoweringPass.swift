
struct InlineExpansion {
    let instructions: [KIRInstruction]
    let returnedExpr: KIRExprID?
    /// True when the expansion contains non-local returns that exit the caller.
    let hasNonLocalReturn: Bool
    /// True when the expansion contains normal return terminators (returnValue/returnUnit)
    /// that need to be converted to exit-label jumps in the NLR path.
    let hasNormalReturn: Bool
}

final class InlineLoweringPass: LoweringPass {
    static let name = "InlineLowering"

    func shouldRun(module: KIRModule, ctx: KIRContext) -> Bool {
        module.ensureFeaturesScanned()
        if module.features.contains(.hasInlineFunction) { return true }
        if let imported = ctx.sema?.importedInlineFunctions, !imported.isEmpty {
            return true
        }
        return false
    }

    func run(module: KIRModule, ctx: KIRContext) throws {
        let unitType = ctx.sema?.types.unitType
        var inlineFunctionsBySymbol = Dictionary(uniqueKeysWithValues: module.arena.declarations.compactMap { decl -> (SymbolID, KIRFunction)? in
            guard case let .function(function) = decl, function.isInline else {
                return nil
            }
            return (function.symbol, function)
        })
        if let imported = ctx.sema?.importedInlineFunctions {
            for symbol in imported.keys.sorted(by: { $0.rawValue < $1.rawValue }) where inlineFunctionsBySymbol[symbol] == nil {
                inlineFunctionsBySymbol[symbol] = imported[symbol]
            }
        }
        // Build a lookup of all KIR functions by symbol so that lambda bodies
        // can be resolved during inline expansion.
        var allFunctionsBySymbol: [SymbolID: KIRFunction] = [:]
        for decl in module.arena.declarations {
            if case let .function(function) = decl {
                allFunctionsBySymbol[function.symbol] = function
            }
        }

        // Callees whose body never reaches an object file: auto-inline
        // (`isInlineOnly`) overloads of this module, and every inline function
        // imported from a library (the metadata does not carry `isInlineOnly`,
        // and an artifact omits auto-inline bodies).
        var bodylessInlineSymbols = Set(inlineFunctionsBySymbol.filter { $0.value.isInlineOnly }.keys)
        if let imported = ctx.sema?.importedInlineFunctions {
            bodylessInlineSymbols.formUnion(imported.keys)
        }

        // An inline body — or a lambda body that gets spliced into its caller —
        // can itself call one of those functions. Both snapshots above predate
        // any expansion, so splicing such a body into a caller would leave a
        // call to a symbol that no object file defines. Expand those nested
        // calls inside the snapshots first.
        expandNestedBodylessInlineCalls(
            bodylessInlineSymbols: bodylessInlineSymbols,
            inlineFunctionsBySymbol: &inlineFunctionsBySymbol,
            allFunctionsBySymbol: &allFunctionsBySymbol,
            module: module,
            ctx: ctx,
            unitType: unitType
        )

        let sortedInlineFunctions = inlineFunctionsBySymbol.values.sorted(by: { $0.symbol.rawValue < $1.symbol.rawValue })
        let inlineFunctionsByName = Dictionary(grouping: sortedInlineFunctions, by: \.name)

        module.arena.transformFunctions { [self] function in
            inlineTransform(
                function: function,
                inlineFunctionsBySymbol: inlineFunctionsBySymbol,
                inlineFunctionsByName: inlineFunctionsByName,
                allFunctionsBySymbol: allFunctionsBySymbol,
                module: module,
                ctx: ctx,
                unitType: unitType
            )
        }
        module.recordLowering(Self.name)
    }

    /// Rewrite the bodies that later get spliced into callers so they no longer
    /// call functions whose body never reaches codegen. Every round re-expands
    /// the *original* body against the improved callee snapshots, so a body is
    /// never spliced twice. Bounded to keep delegation chains from expanding
    /// without limit.
    private func expandNestedBodylessInlineCalls(
        bodylessInlineSymbols: Set<SymbolID>,
        inlineFunctionsBySymbol: inout [SymbolID: KIRFunction],
        allFunctionsBySymbol: inout [SymbolID: KIRFunction],
        module: KIRModule,
        ctx: KIRContext,
        unitType: TypeID?
    ) {
        guard !bodylessInlineSymbols.isEmpty else { return }
        var originals = allFunctionsBySymbol
        for (symbol, function) in inlineFunctionsBySymbol.sorted(by: { $0.key.rawValue < $1.key.rawValue })
            where originals[symbol] == nil
        {
            originals[symbol] = function
        }
        var expandedBySymbol: [SymbolID: KIRFunction] = [:]

        for _ in 0 ..< 4 {
            // Expanding a snapshot appends expressions to the module arena. A
            // Dictionary's per-instance iteration order must not choose IDs.
            let pending = originals.values
                .filter { function in
                    let current = expandedBySymbol[function.symbol] ?? function
                    return current.body.contains { instruction in
                        guard case let .call(symbol, _, _, _, _, _, _, _) = instruction,
                              let symbol, symbol != function.symbol
                        else {
                            return false
                        }
                        return bodylessInlineSymbols.contains(symbol)
                    }
                }
                .sorted(by: { lhs, rhs in
                    let lhsName = ctx.interner.resolve(lhs.name)
                    let rhsName = ctx.interner.resolve(rhs.name)
                    if lhsName != rhsName { return lhsName < rhsName }
                    if lhs.params.count != rhs.params.count { return lhs.params.count < rhs.params.count }
                    if let lhsRange = lhs.sourceRange, let rhsRange = rhs.sourceRange {
                        if lhsRange.start.file.rawValue != rhsRange.start.file.rawValue {
                            return lhsRange.start.file.rawValue < rhsRange.start.file.rawValue
                        }
                        if lhsRange.start.offset != rhsRange.start.offset {
                            return lhsRange.start.offset < rhsRange.start.offset
                        }
                        if lhsRange.end.offset != rhsRange.end.offset {
                            return lhsRange.end.offset < rhsRange.end.offset
                        }
                    } else if lhs.sourceRange != nil {
                        return false
                    } else if rhs.sourceRange != nil {
                        return true
                    }
                    return lhs.symbol.rawValue < rhs.symbol.rawValue
                })
            guard !pending.isEmpty else { return }
            let sortedInlineFunctions = inlineFunctionsBySymbol.values.sorted(by: { $0.symbol.rawValue < $1.symbol.rawValue })
            let byName = Dictionary(grouping: sortedInlineFunctions, by: \.name)
            for function in pending {
                let expanded = inlineTransform(
                    function: function,
                    inlineFunctionsBySymbol: inlineFunctionsBySymbol,
                    inlineFunctionsByName: byName,
                    allFunctionsBySymbol: allFunctionsBySymbol,
                    module: module,
                    ctx: ctx,
                    unitType: unitType
                )
                expandedBySymbol[function.symbol] = expanded
                if inlineFunctionsBySymbol[function.symbol] != nil {
                    inlineFunctionsBySymbol[function.symbol] = expanded
                }
                if allFunctionsBySymbol[function.symbol] != nil {
                    allFunctionsBySymbol[function.symbol] = expanded
                }
            }
        }
    }

    /// Upper bound on how many times a function body is re-scanned for inline
    /// calls. Nested expansions terminate well below this; the cap only keeps
    /// mutually recursive inline functions from looping forever.
    private static let maxInlineExpansionRounds = 8

    private func inlineTransform(
        function: KIRFunction,
        inlineFunctionsBySymbol: [SymbolID: KIRFunction],
        inlineFunctionsByName: [InternedString: [KIRFunction]],
        allFunctionsBySymbol: [SymbolID: KIRFunction],
        module: KIRModule,
        ctx: KIRContext,
        unitType: TypeID?
    ) -> KIRFunction {
        var updated = function
        var body = function.body
        var locations = function.instructionLocations
        // An expanded inline body can itself call another inline function
        // (`Grouping.fold` delegating to `foldTo`). Those calls only become
        // visible once the outer body is spliced in, and inline functions are
        // not emitted as standalone symbols, so a call left behind here would
        // dangle at link time. Re-scan until no inline call remains.
        for _ in 0 ..< Self.maxInlineExpansionRounds {
            let expansion = expandInlineCalls(
                in: body,
                callerLocations: locations,
                function: function,
                inlineFunctionsBySymbol: inlineFunctionsBySymbol,
                inlineFunctionsByName: inlineFunctionsByName,
                allFunctionsBySymbol: allFunctionsBySymbol,
                module: module,
                ctx: ctx,
                unitType: unitType
            )
            body = expansion.body
            locations = expansion.locations
            if !expansion.didExpand {
                break
            }
        }

        updated.replaceBody(body, locations: locations)
        if updated.body.isEmpty {
            updated.replaceBody([.returnUnit], locations: [nil])
        }
        return updated
    }

    private func expandInlineCalls(
        in callerBody: [KIRInstruction],
        callerLocations: [SourceRange?],
        function: KIRFunction,
        inlineFunctionsBySymbol: [SymbolID: KIRFunction],
        inlineFunctionsByName: [InternedString: [KIRFunction]],
        allFunctionsBySymbol: [SymbolID: KIRFunction],
        module: KIRModule,
        ctx: KIRContext,
        unitType: TypeID?
    ) -> (body: [KIRInstruction], locations: [SourceRange?], didExpand: Bool) {
        // Every label this round introduces into the caller comes from here,
        // starting above the labels the caller body already uses.
        var labels = InlineLabelAllocator(callerBody: callerBody)

        var loweredBody = KIRLoweringEmitContext()
        loweredBody.instructions.reserveCapacity(callerBody.count)
        var aliases: [KIRExprID: KIRExprID] = [:]
        var didExpand = false

        for (index, originalInstruction) in callerBody.enumerated() {
            loweredBody.currentSourceRange = index < callerLocations.count
                ? callerLocations[index]
                : nil
            let instruction = InlineExprAliasing.rewriteInstruction(originalInstruction, aliases: aliases)
            if let defined = InlineExprAliasing.definedResult(in: instruction) {
                aliases.removeValue(forKey: defined)
            }

            guard case let .call(symbol, callee, arguments, result, _, callerThrownResult, _, _) = instruction else {
                loweredBody.append(instruction)
                continue
            }

            let resolvedArguments = arguments.map { InlineExprAliasing.resolveAlias(of: $0, aliases: aliases) }
            if ["kk_function_invoke", "kk_function_invoke_0", "kk_function_invoke_2", "kk_function_invoke_3", "kk_function_invoke_4", "kk_suspend_function_invoke", "kk_suspend_function_invoke_0", "kk_suspend_function_invoke_2"].contains(ctx.interner.resolve(callee)),
               let callableExpr = resolvedArguments.first,
               let lambdaFunction = resolveLambdaFunction(
                   argExpr: callableExpr,
                   arena: module.arena,
                   allFunctionsBySymbol: allFunctionsBySymbol,
                   callerBody: callerBody
               )
            {
                let captureArgs = (module.arena.lambdaCaptureArgsBySymbol[lambdaFunction.symbol] ?? [])
                    .map { InlineExprAliasing.resolveAlias(of: $0, aliases: aliases) }
                // A lambda spliced into an already-inlined generic body reads
                // its arguments from erased (type-parameter) slots, so unbox
                // them for the lambda's own concrete parameter types.
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
                    allFunctionsBySymbol: allFunctionsBySymbol,
                    ctx: ctx,
                    labels: &labels
                ) {
                    let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
                        in: labels.relocate(lambdaExpansion.instructions),
                        callerThrownResult: callerThrownResult,
                        labels: &labels
                    )
                    loweredBody.append(contentsOf: reroutedInstructions)
                    didExpand = true
                    if let throwDispatchLabel {
                        loweredBody.append(.label(throwDispatchLabel))
                    }
                    if let result {
                        // The lambda may return through a non-local return on
                        // every path, in which case `returnedExpr` refers to a
                        // slot no emitted instruction defines. Read it only
                        // when a definition actually survives in the body.
                        if let lambdaReturn = lambdaExpansion.returnedExpr.map({ InlineExprAliasing.resolveAlias(of: $0, aliases: aliases) }),
                           exprIsDefined(lambdaReturn, in: loweredBody.instructions)
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
                    continue
                }
            }

            // The name fallback only applies to calls whose callee symbol is
            // unknown here. A call with a *known* callee symbol that isn't a
            // compiled inline/regular function in this module must not be
            // redirected to a same-named inline overload from an unrelated
            // receiver type (e.g. `Mutex.withLock` vs `Lock.withLock`, or a
            // synthetic/runtime-dispatched member such as the generic
            // `Iterable<T>.iterator()` used inside `reduce` vs an unrelated
            // bundled `Map<K, V>.iterator()` -- see KSP-1011). A known symbol
            // that resolves to neither table is exactly as "not ours to
            // rename" as one resolving to a known non-inline function: its
            // own resolution (external link / virtual dispatch) still
            // applies once this pass is done with it.
            let inlineTarget: KIRFunction? = if let symbol, let target = inlineFunctionsBySymbol[symbol] {
                target
            } else if symbol != nil {
                nil
            } else if let byName = inlineFunctionsByName[callee], byName.count == 1 {
                byName[0]
            } else {
                nil
            }

            guard let inlineTarget, inlineTarget.symbol != function.symbol else {
                loweredBody.append(instruction)
                continue
            }
            // An imported inline body was ABI-lowered when its library was
            // built, so its erased (type-parameter / Any) parameters keep the
            // boxed representation chosen there; this expansion cannot
            // re-specialize them. Box primitive arguments that flow into an
            // erased parameter so the splice honours that representation.
            let expansionArguments = InlineErasedLambdaABI.usesErasedLambdaABI(inlineTarget, ctx: ctx)
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
                allFunctionsBySymbol: allFunctionsBySymbol,
                module: module,
                ctx: ctx,
                callerBody: callerBody,
                labels: &labels
            )
            guard let expansion else {
                loweredBody.append(instruction)
                continue
            }
            didExpand = true

            // Move the expansion's labels into the caller's label namespace so
            // the caller's own labels and the inlined callee's cannot collide.
            let remappedInstructions = labels.relocate(expansion.instructions)

            // Redirect any throw inside the expansion that isn't already routed to
            // a local exception slot, so it reaches the caller's enclosing try
            // (see `InlineThrowRerouting`) instead of silently escaping the
            // caller via codegen's unrouted-throw auto-propagation.
            let (reroutedInstructions, throwDispatchLabel) = InlineThrowRerouting.rerouteUnprotectedThrows(
                in: remappedInstructions,
                callerThrownResult: callerThrownResult,
                labels: &labels
            )

            if expansion.hasNonLocalReturn {
                // The expansion contains non-local returns from lambdas.
                // Rewrite each nonLocalReturn into a real return from the caller.
                // If there is a potential fallthrough path (i.e., the expansion has
                // any normal return terminator), emit an exit label and jump to it
                // so normal control flow continues past the expansion site.

                let hasFallthroughPath = expansion.hasNormalReturn
                let exitLabel: Int32? = hasFallthroughPath ? labels.allocateCallerLabel() : nil

                // Track whether we just emitted a terminator so we can skip
                // unreachable instructions until the next label.
                var afterTerminator = false

                for expandedInstruction in reroutedInstructions {
                    // Skip unreachable instructions after a terminator until
                    // the next label starts a new block.
                    if afterTerminator {
                        if case .label = expandedInstruction {
                            afterTerminator = false
                            loweredBody.append(expandedInstruction)
                        }
                        continue
                    }

                    switch expandedInstruction {
                    case let .nonLocalReturn(value):
                        // Convert to a real return from the caller.
                        if let value {
                            loweredBody.append(.returnValue(InlineExprAliasing.resolveAlias(of: value, aliases: aliases)))
                        } else {
                            loweredBody.append(.returnUnit)
                        }
                        afterTerminator = true
                    case .label:
                        // A label starts a new block, so we are no longer after a terminator.
                        loweredBody.append(expandedInstruction)
                    case .returnValue, .returnUnit:
                        // The inline body's own return: jump to exit label instead,
                        // so normal control flow continues in the caller.
                        if let exitLabel {
                            loweredBody.append(.jump(exitLabel))
                        }
                        afterTerminator = true
                    case .returnIfEqual:
                        // returnIfEqual is a conditional normal return from the inline body.
                        // In the NLR path, convert it to a conditional jump to the exit label
                        // to avoid prematurely returning from the caller.
                        if let exitLabel, case let .returnIfEqual(lhs, rhs) = expandedInstruction {
                            loweredBody.append(.jumpIfEqual(lhs: lhs, rhs: rhs, target: exitLabel))
                        }
                        // returnIfEqual is conditional, so it does NOT set afterTerminator.
                    default:
                        loweredBody.append(expandedInstruction)
                    }
                }

                // Only emit the exit label when there is a fallthrough path
                // (avoids unreachable labeled blocks when the expansion always
                // executes nonLocalReturn).
                if let exitLabel {
                    loweredBody.append(.label(exitLabel))
                }
            } else {
                // No non-local returns -- strip returnValue/returnUnit from the
                // expansion (they are only needed for the NLR path exit-label
                // mechanism) and use the original simple expansion path.
                // Labels have already been relocated above.
                let filtered = reroutedInstructions.filter { inst in
                    switch inst {
                    case .returnValue, .returnUnit:
                        return false
                    default:
                        return true
                    }
                }
                loweredBody.append(contentsOf: filtered)
            }

            // If any throw inside the expansion was redirected to the caller's
            // exception slot, land here so the pre-existing caller instructions
            // that follow (from the original call site's throw-aware wrapping)
            // can pick it up and dispatch to the enclosing try's catch/finally.
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
                   exprIsDefined(returnedExpr, in: loweredBody.instructions)
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
        }

        return (loweredBody.instructions, loweredBody.instructionLocations, didExpand)
    }

    /// Whether any instruction in `instructions` defines `expr` — including
    /// `copy` destinations and `thrownResult` slots, matching the register-def
    /// notion used by `KIRVerifier`'s undefined-read check.
    func exprIsDefined(_ expr: KIRExprID, in instructions: [KIRInstruction]) -> Bool {
        instructions.contains { instruction in
            switch instruction {
            case let .constValue(result, _):
                result == expr
            case let .binary(_, _, _, result), let .unary(_, _, result),
                 let .nullAssert(_, result), let .loadGlobal(result, _):
                result == expr
            case let .call(_, _, _, result, _, thrownResult, _, _):
                result == expr || thrownResult == expr
            case let .virtualCall(_, _, _, _, result, _, thrownResult, _):
                result == expr || thrownResult == expr
            case let .copy(_, to):
                to == expr
            default:
                false
            }
        }
    }
}
