/// Dependency scheduling for snapshots and bounded re-scanning of callers.
extension InlineLoweringPass {
    /// Visit frozen snapshots in callee-before-caller order, including bodies
    /// reached through lambda arguments. Each original is transformed at most
    /// once; a back edge is not revisited, leaving cycles to the residue check.
    func expandNestedBodylessInlineCalls(
        index: InlineExpansionIndex,
        module: KIRModule,
        ctx: KIRContext,
        unitType: TypeID?
    ) {
        guard !index.bodylessInlineSymbols.isEmpty else { return }
        func ordered(_ symbols: Set<SymbolID>) -> [SymbolID] {
            symbols.compactMap { index.originalBodies[$0] }.sorted {
                InlineExpansionIndex.snapshotExpansionOrder(
                    $0, $1, interner: ctx.interner
                )
            }.map(\.symbol)
        }

        var visited: Set<SymbolID> = []
        var postorder: [SymbolID] = []
        var callers: [SymbolID: Set<SymbolID>] = [:]
        var affected: Set<SymbolID> = []
        var worklist = ordered(Set(index.originalBodies.keys)).reversed().map { ($0, false) }
        while let (symbol, finishing) = worklist.popLast() {
            if finishing {
                postorder.append(symbol)
                continue
            }
            guard visited.insert(symbol).inserted,
                  let original = index.originalBodies[symbol] else { continue }
            var dependencies: Set<SymbolID> = []
            for instruction in original.body {
                guard case let .call(callSymbol, callee, arguments, _, _, _, _, _) = instruction else {
                    continue
                }
                // Resolving reachable descriptors here discovers their own
                // dependencies before expansion, without parsing unused imports.
                if let target = index.inlineTarget(
                    callSymbol: callSymbol, callee: callee,
                    inlineFunctionsByName: index.inlineFunctionsByName
                ) {
                    dependencies.insert(target.symbol)
                    if index.isBodyless(target.symbol) {
                        affected.insert(symbol)
                    }
                }
                for argument in arguments {
                    if let lambda = resolveLambdaFunction(
                        argExpr: argument, arena: module.arena,
                        allFunctionsBySymbol: index.allFunctionsBySymbol,
                        callerBody: original.body
                    ) {
                        dependencies.insert(lambda.symbol)
                    }
                }
            }
            for dependency in dependencies {
                callers[dependency, default: []].insert(symbol)
            }
            worklist.append((symbol, true))
            worklist.append(contentsOf: ordered(dependencies).reversed().map { ($0, false) })
        }

        // Ordinary chains with no bodyless dependency are handled in callers.
        var pending = ordered(affected)
        while let symbol = pending.popLast() {
            for caller in ordered(callers[symbol] ?? []) where affected.insert(caller).inserted {
                pending.append(caller)
            }
        }
        for symbol in postorder where affected.contains(symbol) {
            guard let original = index.originalBodies[symbol] else { continue }
            let expanded = inlineTransform(
                function: original,
                index: index,
                inlineFunctionsByName: index.inlineFunctionsByName,
                module: module,
                ctx: ctx,
                unitType: unitType,
                preserveNonLocalReturns: true
            )
            index.recordExpansion(of: symbol, to: expanded)
        }
    }

    /// Emits one deterministic diagnostic per leftover call that names a
    /// bodyless callee -- `isInlineOnly` declarations and imported inline
    /// symbols whose bodies are never emitted, so an unexpanded call would
    /// dangle at link time. Non-mandatory calls (to regular `inline`
    /// functions or non-expansion targets) are legal to leave behind and are
    /// not reported. A callee on or reaching a bodyless call cycle can never
    /// converge, so its callers are diagnosed as recursion; any other residue
    /// means the expansion budget ran out.
    ///
    /// This runs after both expansion phases and scans the module's
    /// post-expansion bodies in declaration order. The residue verdict is
    /// the contract `expandNestedBodylessInlineCalls` and `inlineTransform`
    /// are held to regardless of their scheduling strategy.
    func diagnoseMandatoryInlineResidue(
        module: KIRModule,
        index: InlineExpansionIndex,
        ctx: KIRContext
    ) {
        let byName = index.inlineFunctionsByName
        let recursive = index.recursiveBodylessCallees()
        for decl in module.arena.declarations {
            guard case let .function(function) = decl else {
                continue
            }
            for (offset, instruction) in function.body.enumerated() {
                guard case let .call(callSymbol, callee, _, _, _, _, _, _) = instruction,
                      index.isMandatoryExpansionCall(
                          callSymbol: callSymbol,
                          callee: callee,
                          inlineFunctionsByName: byName,
                          interner: ctx.interner,
                          externalLinkName: { ctx.sema?.symbols.externalLinkName(for: $0) }
                      )
                else {
                    continue
                }
                // The reified enum intrinsic is specialized by the next pass,
                // after tokens have propagated through every inline expansion.
                if let callSymbol,
                   ctx.sema?.wellKnownSymbols.enumIntrinsic(for: callSymbol) == .enumValues {
                    continue
                }
                let calleeName = ctx.interner.resolve(callee)
                let callerName = ctx.interner.resolve(function.name)
                let cause: String = if let callSymbol, recursive.contains(callSymbol) {
                    "the callee is recursive, so inline expansion cannot terminate"
                } else {
                    "inline expansion reached its limit"
                }
                ctx.diagnostics.error(
                    "KSWIFTK-INL-0001",
                    "call to '\(calleeName)' in '\(callerName)' was not expanded: \(cause); "
                        + "the callee has no emitted body",
                    range: (offset < function.instructionLocations.count
                            ? function.instructionLocations[offset] : nil) ?? function.sourceRange
                )
            }
        }
    }

    func inlineTransform(
        function: KIRFunction,
        index: InlineExpansionIndex,
        inlineFunctionsByName: [InternedString: [SymbolID]],
        module: KIRModule,
        ctx: KIRContext,
        unitType: TypeID?,
        expansionLimits: InlineExpansionBudget.Limits = .init(),
        preserveNonLocalReturns: Bool = false
    ) -> KIRFunction {
        var updated = function
        var body = function.body
        var locations = function.instructionLocations
        let budget = InlineExpansionBudget(arena: module.arena, limits: expansionLimits)
        if function.isInline { budget.inlineSymbols.insert(function.symbol) }
        var pending: [Int: [SymbolID]] = [:]
        for (offset, instruction) in body.enumerated() {
            if case .call = instruction { pending[offset] = [function.symbol] }
        }
        while !pending.isEmpty, budget.consumeWork(body.count, arena: module.arena) {
            let expansion = expandInlineCalls(
                in: body,
                callerLocations: locations,
                function: function,
                index: index,
                inlineFunctionsByName: inlineFunctionsByName,
                module: module,
                ctx: ctx,
                unitType: unitType,
                pending: pending,
                budget: budget,
                preserveNonLocalReturns: preserveNonLocalReturns
            )
            body = expansion.body
            locations = expansion.locations
            pending = expansion.pending
            if !expansion.didExpand {
                break
            }
        }

        if !preserveNonLocalReturns {
            if function.isInline, body.contains(where: {
                if case .beginNonLocalReturnScope = $0 { return true }
                return false
            }) {
                module.inlineBodiesBeforeFinallyLowering[function.symbol] = body
            }
            let resolved = resolveNonLocalReturnScopes(
                body, locations: locations, arena: module.arena,
                unitType: unitType, returnType: function.returnType
            )
            body = resolved.body
            locations = resolved.locations
        }
        updated.replaceBody(body, locations: locations)
        if updated.body.isEmpty {
            updated.replaceBody([.returnUnit], locations: [nil])
        }
        return updated
    }
}
