#if canImport(Testing)
@testable import CompilerCore
import Foundation
import Testing
@testable import CompilerTestSupport

@Suite
struct SemaPhaseTimingTests {
    private func analyze(_ sources: [String], jobs: Int, timed: Bool) throws -> CompilationContext {
        let paths = sources.indices.map { "/virtual/sema-timing/input\($0).kt" }
        let ctx = makeCompilationContext(
            inputs: paths, frontendFlags: ["jobs=\(jobs)"], includeStdlib: false
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

    // Normalize by source position: parallel BuildAST may allocate ExprIDs in
    // a different order, but timing must preserve every inferred expression type.
    private func expressionTypes(_ ctx: CompilationContext) throws -> [String] {
        let ast = try #require(ctx.ast)
        let sema = try #require(ctx.sema)
        return sema.bindings.exprTypes.compactMap { exprID, type in
            guard let range = ast.arena.exprRange(exprID) else { return nil }
            return "\(range.start.file.rawValue):\(range.start.offset):\(range.end.offset):\(sema.types.renderType(type))"
        }.sorted()
    }

    @Test(arguments: [1, 4])
    func recordsIntervalsWithoutChangingCrossFileInference(jobs: Int) throws {
        let sources = [
            """
            package timing
            fun result(): Int = later + identity(2)
            fun identity(x: Int): Int = x
            """,
            """
            package timing
            val later = 40
            tailrec fun recurse(x: Int): Int = if (x == 0) x else recurse(x - 1)
            """,
        ]
        let baseline = try analyze(sources, jobs: jobs, timed: false)
        let timed = try analyze(sources, jobs: jobs, timed: true)
        #expect(!baseline.diagnostics.hasError)
        #expect(baseline.phaseTimer == nil)
        #expect(timed.diagnostics.diagnostics == baseline.diagnostics.diagnostics)
        let baselineTypes = try expressionTypes(baseline)
        #expect(!baselineTypes.isEmpty)
        #expect(try expressionTypes(timed) == baselineTypes)

        let timer = try #require(timed.phaseTimer)
        let phase = try #require(timer.phaseRecords.first)
        #expect(phase.name == "Sema")
        #expect(phase.subRecords.map(\.name) == [
            "DataFlowSema", "TypeCheckSema",
        ])
        let dataFlow = try #require(phase.subRecords.first { $0.name == "DataFlowSema" })
        #expect(dataFlow.subRecords.map(\.name) == [
            "buildBundledIndex", "loadImports", "predeclareBundledHeaders",
            "mergeImportedStdlibSymbolsIntoBundledIndex", "registerSyntheticDelegateStubs",
            "applyImportedLibraryDeferredWork", "sema-setup", "collectAllHeaders",
            "runValidationPasses", "runBodyAnalysis",
        ])
        let validation = try #require(dataFlow.subRecords.first { $0.name == "runValidationPasses" })
        #expect(validation.subRecords.first?.name == "bindInheritanceEdges")
        #expect(validation.subRecords.last?.name == "attachCompilerMetadataAnnotations")
        let typeCheck = try #require(phase.subRecords.first { $0.name == "TypeCheckSema" })
        #expect(typeCheck.subRecords.map(\.name) == ["type-check"])

        func expectContainedIntervals(_ parent: PhaseTimer.PhaseRecord) {
            for interval in parent.subRecords {
                #expect(interval.startTime >= parent.startTime)
                #expect(interval.endTime <= parent.endTime)
                #expect(interval.startTime <= interval.endTime)
                expectContainedIntervals(interval)
            }
        }
        expectContainedIntervals(phase)
        for (previous, next) in zip(phase.subRecords, phase.subRecords.dropFirst()) {
            #expect(previous.endTime <= next.startTime)
        }
        // sema-setup includes the earlier preparation scopes, so it overlaps
        // those siblings but finishes before header collection starts.
        let setup = try #require(dataFlow.subRecords.first { $0.name == "sema-setup" })
        for preparation in dataFlow.subRecords.prefix(while: { $0.name != "sema-setup" }) {
            #expect(preparation.startTime >= setup.startTime)
            #expect(preparation.endTime <= setup.endTime)
        }
        let headers = try #require(dataFlow.subRecords.first { $0.name == "collectAllHeaders" })
        #expect(setup.endTime <= headers.startTime)
    }

    @Test
    func preservesDiagnosticsForRejectedCode() throws {
        let sources = [
            "fun duplicate(x: Int, x: Int): Int = x",
            "tailrec fun notRecursive(): Int = 1",
            "fun badReturn(): Int = \"wrong\"",
        ]
        let baseline = try analyze(sources, jobs: 1, timed: false)
        let timed = try analyze(sources, jobs: 1, timed: true)
        #expect(baseline.diagnostics.hasError)
        #expect(baseline.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-TYPE-0002" })
        #expect(baseline.diagnostics.diagnostics.contains { $0.code == "KSWIFTK-SEMA-TAILREC" })
        #expect(timed.diagnostics.diagnostics == baseline.diagnostics.diagnostics)
    }

    @Test
    func recordsFailedIntervalAndRethrows() {
        enum Failure: Error { case expected }
        let ctx = makeCompilationContext(inputs: [], includeStdlib: false)
        let timer = PhaseTimer()
        ctx.installPhaseTimer(timer)
        timer.beginPhase("Sema")
        #expect(throws: Failure.self) {
            try withSemaSubPhaseTiming("failed-work", ctx: ctx) {
                throw Failure.expected
            }
        }
        timer.endPhase()
        #expect(timer.phaseRecords.first?.subRecords.map(\.name) == ["failed-work"])
    }
}
#endif
