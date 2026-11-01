#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct TypeCheckAttributionTests {
    private func analyze(
        _ sources: [String],
        frontendFlags: [String] = [],
        timed: Bool
    ) throws -> CompilationContext {
        let paths = sources.indices.map { "/virtual/typecheck-attribution/input\($0).kt" }
        let ctx = makeCompilationContext(
            inputs: paths, frontendFlags: frontendFlags, includeStdlib: false
        )
        for (path, source) in zip(paths, sources) {
            _ = ctx.sourceManager.addFile(path: path, contents: Data(source.utf8))
        }
        try runFrontend(ctx)
        if timed {
            let timer = PhaseTimer()
            ctx.installPhaseTimer(timer)
            timer.beginPhase("Sema")
        }
        try SemaPhase().run(ctx)
        ctx.phaseTimer?.endPhase()
        return ctx
    }

    @Test
    func installsCollectorOnlyWhenPhaseTimerIsActive() throws {
        let sources = [
            """
            package timing
            fun result(): Int = later + identity(2)
            fun identity(x: Int): Int = x
            """,
            """
            package timing
            val later = 40
            """,
        ]
        let untimed = try analyze(sources, timed: false)
        #expect(untimed.typeCheckAttribution == nil)

        let timed = try analyze(sources, timed: true)
        let attribution = try #require(timed.typeCheckAttribution)
        #expect(attribution.value(.exprInferences) > 0)
        #expect(attribution.value(.callSites) > 0)
        #expect(attribution.value(.scopeLookupVisits) > 0)
        #expect(attribution.value(.symbolTableLookups) >= 0)
        #expect(attribution.value(.resolveCallAttempts) > 0)
        #expect(attribution.value(.candidatesEvaluated) >= attribution.value(.viableCandidates))
        #expect(attribution.value(.subtypeChecks) > 0)
        // The collector detaches when the type-check sub-phase ends so later
        // pipeline stages do not pollute the counters.
        let sema = try #require(timed.sema)
        #expect(sema.types.attribution == nil)
        #expect(sema.symbols.attribution == nil)
    }

    @Test
    func collectsUnderParallelBodyWorkers() throws {
        let ctx = try analyze(
            [
                "package p\nfun a(): Int = helperA(1)\nfun helperA(x: Int): Int = x",
                "package q\nfun b(): Int = helperB(2)\nfun helperB(x: Int): Int = x",
            ],
            frontendFlags: ["jobs=4", "sema-parallel"],
            timed: true
        )
        #expect(!ctx.diagnostics.hasError)
        let attribution = try #require(ctx.typeCheckAttribution)
        #expect(attribution.value(.exprInferences) > 0)
        #expect(attribution.value(.callSites) > 0)
    }

    @Test
    func measureScopesOnlyAccumulateAtOutermostLevel() throws {
        let attribution = TypeCheckAttribution()
        try attribution.measure(.resolveCall) {
            try attribution.measure(.resolveCall) {
                // Nested same-scope work is attributed to the outer invocation.
            }
            try attribution.measure(.constraintSolve) {}
        }
        #expect(attribution.nanos(.resolveCall) >= attribution.nanos(.constraintSolve))
        #expect(attribution.nanos(.resolveCall) > 0)
    }

    @Test
    func measureRethrowsAndRecords() {
        enum Failure: Error { case expected }
        let attribution = TypeCheckAttribution()
        #expect(throws: Failure.self) {
            try attribution.measure(.scopeLookup) {
                throw Failure.expected
            }
        }
        #expect(attribution.nanos(.scopeLookup) >= 0)
        // The scope was deactivated even though the body threw, so a fresh
        // measurement still inserts and times.
        attribution.measure(.scopeLookup) {}
        #expect(attribution.nanos(.scopeLookup) > 0)
    }

    @Test
    func nilAttributionRunsBodyWithoutCounters() throws {
        var ran = false
        let result = withAttributionTiming(.scopeLookup, attribution: nil) {
            ran = true
            return 7
        }
        #expect(ran)
        #expect(result == 7)
    }

    @Test
    func summaryReportsEveryBucket() {
        let attribution = TypeCheckAttribution()
        attribution.increment(.exprInferences)
        attribution.increment(.callSites, by: 2)
        attribution.increment(.candidatesEvaluated, by: 6)
        attribution.increment(.resolveCallAttempts, by: 2)
        let summary = attribution.summary()
        for line in [
            "inferExpr visits",
            "call sites checked",
            "scope lookup visits",
            "package-scope queries",
            "member-scope queries",
            "symbol-table fqName lookups",
            "compact-index drains",
            "resolveCall / probeCall attempts",
            "candidates evaluated",
            "viable candidates",
            "generic instantiations",
            "constraint solves",
            "isSubtype checks",
            "scopeLookup:",
            "deferredScopeCandidates:",
            "resolveCall:",
            "constraintSolve:",
        ] {
            #expect(summary.contains(line), "missing \(line)")
        }
        #expect(summary.contains("avg 3.0/attempt"))
    }
}
#endif
