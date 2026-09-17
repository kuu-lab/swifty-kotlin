
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

    // MARK: - Lambda Inlining

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
