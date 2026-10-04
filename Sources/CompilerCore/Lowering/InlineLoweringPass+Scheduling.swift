/// Dependency scheduling for the inline pass: the bounded loops that decide
/// when snapshots are re-expanded and when a caller is re-scanned.
///
/// `expandNestedBodylessInlineCalls` drives the bodyless-snapshot rounds;
/// `inlineTransform` re-scans one caller body until no inline call remains.
/// Both consume `InlineExpansionIndex` for all snapshot tables, dependency
/// queries, and deterministic ordering -- this file owns only the round
/// bounds and the re-expansion / re-scan control.
extension InlineLoweringPass {
    /// Bound on the bodyless-snapshot rounds. Each round re-expands the
    /// *original* body against the improved callee snapshots, so a body is
    /// never spliced twice; the cap keeps delegation chains from expanding
    /// without limit.
    private static let maxBodylessExpansionRounds = 4

    /// Rewrite the bodies that later get spliced into callers so they no longer
    /// call functions whose body never reaches codegen. The index's pending
    /// set is computed from the *current* snapshot bodies, while each round
    /// still re-expands the frozen originals, so a body is never spliced
    /// twice.
    func expandNestedBodylessInlineCalls(
        index: InlineExpansionIndex,
        module: KIRModule,
        ctx: KIRContext,
        unitType: TypeID?
    ) {
        guard !index.bodylessInlineSymbols.isEmpty else { return }
        for _ in 0 ..< Self.maxBodylessExpansionRounds {
            let pending = index.pendingBodylessCallers(interner: ctx.interner)
            guard !pending.isEmpty else { return }
            // The by-name fallback table is fixed for the whole round: within
            // a round each expansion still sees the newest snapshots in the
            // by-symbol tables, but name candidates come from the table as it
            // stood when the round began.
            let byName = index.inlineFunctionsByName
            for symbol in pending {
                guard let original = index.originalBodies[symbol] else { continue }
                let expanded = inlineTransform(
                    function: original,
                    index: index,
                    inlineFunctionsByName: byName,
                    module: module,
                    ctx: ctx,
                    unitType: unitType
                )
                index.recordExpansion(of: symbol, to: expanded)
            }
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
    /// are held to before their fixed rounds can be removed.
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
        expansionLimits: InlineExpansionBudget.Limits = .init()
    ) -> KIRFunction {
        var updated = function
        var body = function.body
        var locations = function.instructionLocations
        let budget = InlineExpansionBudget(arena: module.arena, limits: expansionLimits)
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
                budget: budget
            )
            body = expansion.body
            locations = expansion.locations
            pending = expansion.pending
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
}
