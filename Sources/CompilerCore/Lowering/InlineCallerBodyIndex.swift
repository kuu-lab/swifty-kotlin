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

struct InlineCallerBodyIndex {
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

    func producerCount(of expr: KIRExprID) -> Int {
        producerCountByExpr[expr] ?? 0
    }

    func symbolRefBound(to expr: KIRExprID) -> SymbolID? {
        symbolRefByExpr[expr]
    }

    func callSites(producing expr: KIRExprID) -> [CallSite] {
        callSitesByResult[expr] ?? []
    }
}
