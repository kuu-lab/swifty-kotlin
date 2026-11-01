/// Incremental "is this expression defined" index over an append-only
/// instruction buffer — the `KIRLoweringEmitContext`s that
/// `expandInlineCalls` and `expandInlineCall` grow while splicing bodies.
/// Each query absorbs only the instructions appended since the last query,
/// so a run of queries costs O(emitted total) instead of O(emitted) per
/// expanded call site (KUU-3777). The defining-instruction notion matches
/// `exprIsDefined` and `resolveLambdaFunction`'s producer count: `copy`
/// destinations, call/virtualCall `result` + `thrownResult`,
/// `beginNonLocalReturnScope` slots carrying a function, and the simple
/// `definedResult` cases.
struct InlineDefinedExprIndex {
    private var scannedCount = 0
    private var definedExprs: Set<KIRExprID> = []
    let stats: InlinePerfStats?

    init(stats: InlinePerfStats? = nil) {
        self.stats = stats
    }

    mutating func contains(_ expr: KIRExprID, in instructions: [KIRInstruction]) -> Bool {
        stats?.definedQueries += 1
        while scannedCount < instructions.count {
            Self.forEachDefinedExpr(of: instructions[scannedCount]) { definedExprs.insert($0) }
            scannedCount += 1
            stats?.definedScans += 1
        }
        return definedExprs.contains(expr)
    }

    /// The single place that enumerates which expressions an instruction
    /// defines, shared by this index and `InlineCallerBodyIndex` so the two
    /// cannot drift apart.
    static func forEachDefinedExpr(
        of instruction: KIRInstruction,
        _ body: (KIRExprID) -> Void
    ) {
        switch instruction {
        case let .constValue(result, _),
             let .binary(_, _, _, result),
             let .unary(_, _, result),
             let .nullAssert(_, result),
             let .loadGlobal(result, _):
            body(result)
        case let .call(_, _, _, result, _, thrownResult, _, _),
             let .virtualCall(_, _, _, _, result, _, thrownResult, _):
            if let result { body(result) }
            if let thrownResult { body(thrownResult) }
        case let .copy(_, to):
            body(to)
        case let .beginNonLocalReturnScope(value, _, function):
            if function != nil { body(value) }
        default:
            break
        }
    }
}

/// One O(body) scan answering the caller-body lookups that
/// `resolveLambdaFunction` used to repeat per call site (KUU-3777): producer
/// counts under the shared register-def notion, the first
/// `constValue(.symbolRef)` binding per expression, and the calls producing
/// each result for the `kk_function_create` factory path. Built once per
/// frozen body — `expandInlineCalls` builds it per round and the snapshot
/// scheduler once per body — so every query is O(1) instead of another full
/// body scan.
struct InlineCallerBodyIndex {
    /// A `.call` instruction reduced to the pieces the factory lookup needs.
    struct CallSite {
        let callee: InternedString
        let arguments: [KIRExprID]
    }

    private var producerCountByExpr: [KIRExprID: Int] = [:]
    private var symbolRefByExpr: [KIRExprID: SymbolID] = [:]
    private var callSitesByResult: [KIRExprID: [CallSite]] = [:]

    init(body: [KIRInstruction], stats: InlinePerfStats? = nil) {
        stats?.resolveLambdaScans += body.count
        for instruction in body {
            InlineDefinedExprIndex.forEachDefinedExpr(of: instruction) { defined in
                producerCountByExpr[defined, default: 0] += 1
            }
            switch instruction {
            case let .constValue(result, .symbolRef(symbol)):
                // First binding wins, matching the original body-order scan.
                if symbolRefByExpr[result] == nil {
                    symbolRefByExpr[result] = symbol
                }
            case let .call(_, callee, arguments, result, _, _, _, _):
                if let result {
                    callSitesByResult[result, default: []].append(
                        CallSite(callee: callee, arguments: arguments)
                    )
                }
            default:
                break
            }
        }
    }

    /// How many instructions write `expr`, under the same register-def
    /// notion `resolveLambdaFunction` counted inline. A count above one
    /// keeps the dispatch dynamic (KUU-3222).
    func producerCount(of expr: KIRExprID) -> Int {
        producerCountByExpr[expr] ?? 0
    }

    /// The symbol bound to `expr` by the body's first
    /// `constValue(result: expr, .symbolRef)` — the fallback
    /// `lambdaSymbolRef` used after the arena lookup.
    func symbolRefBound(to expr: KIRExprID) -> SymbolID? {
        symbolRefByExpr[expr]
    }

    /// The `.call` instructions whose `result` is `expr`, in body order —
    /// candidates for the `kk_function_create`/`kk_suspend_function_create`
    /// factory lookup.
    func callSites(producing expr: KIRExprID) -> [CallSite] {
        callSitesByResult[expr] ?? []
    }
}
