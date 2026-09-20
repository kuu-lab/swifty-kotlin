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

    /// Upper bound on how many times a function body is re-scanned for inline
    /// calls. Nested expansions terminate well below this; the cap only keeps
    /// mutually recursive inline functions from looping forever.
    private static let maxInlineExpansionRounds = 8

    /// Rewrite the bodies that later get spliced into callers so they no longer
    /// call functions whose body never reaches codegen. The index's pending
    /// set is computed from the *current* snapshot bodies, while each round
    /// still re-expands the frozen originals, so a body is never spliced
    /// twice.
    func expandNestedBodylessInlineCalls(
        index: inout InlineExpansionIndex,
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

    func inlineTransform(
        function: KIRFunction,
        index: InlineExpansionIndex,
        inlineFunctionsByName: [InternedString: [KIRFunction]],
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
                index: index,
                inlineFunctionsByName: inlineFunctionsByName,
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
}
