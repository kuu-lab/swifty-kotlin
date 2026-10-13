#if canImport(Testing)
@testable import CompilerCore
import Testing

@Suite
struct PhaseTimerTests {
    // MARK: - PhaseRecord

    @Test
    func testPhaseRecordDurationNanos() {
        let record = PhaseTimer.PhaseRecord(
            name: "Lex",
            startTime: 1000,
            endTime: 5000
        )
        #expect(record.durationNanos == 4000)
    }

    @Test
    func testPhaseRecordDurationMs() {
        let record = PhaseTimer.PhaseRecord(
            name: "Lex",
            startTime: 0,
            endTime: 2_000_000
        )
        #expect(abs(record.durationMs - 2.0) <= 0.001)
    }

    @Test
    func testPhaseRecordSubRecords() {
        let sub = PhaseTimer.PhaseRecord(name: "clang", startTime: 100, endTime: 200)
        let record = PhaseTimer.PhaseRecord(
            name: "Link",
            startTime: 0,
            endTime: 1000,
            subRecords: [sub]
        )
        #expect(record.subRecords.count == 1)
        #expect(record.subRecords[0].name == "clang")
    }

    @Test
    func testAccumulatedRecordDurationExcludesGaps() {
        let record = PhaseTimer.PhaseRecord(
            name: "imports.lazyMaterialize", startTime: 100, endTime: 1000, accumulatedDurationNanos: 300
        )
        #expect(record.durationNanos == 300)
        #expect(record.durationMs == 0.0003)
    }

    // MARK: - Recording phases

    @Test
    func testBeginEndPhaseRecordsEntry() {
        let timer = PhaseTimer()
        timer.beginPhase("TestPhase")
        timer.endPhase()
        #expect(timer.phaseRecords.count == 1)
        #expect(timer.phaseRecords[0].name == "TestPhase")
    }

    @Test
    func testEndPhaseWithoutBeginIsNoOp() {
        let timer = PhaseTimer()
        timer.endPhase()
        #expect(timer.phaseRecords.count == 0)
    }

    @Test
    func testMultiplePhasesRecorded() {
        let timer = PhaseTimer()
        timer.beginPhase("Lex")
        timer.endPhase()
        timer.beginPhase("Parse")
        timer.endPhase()
        timer.beginPhase("Sema")
        timer.endPhase()
        #expect(timer.phaseRecords.count == 3)
        #expect(timer.phaseRecords.map(\.name) == ["Lex", "Parse", "Sema"])
    }

    @Test
    func testRecordSubPhase() {
        let timer = PhaseTimer()
        timer.beginPhase("Link")
        timer.recordSubPhase("clang", startTime: 100, endTime: 500)
        timer.recordSubPhase("ld", startTime: 500, endTime: 900)
        timer.endPhase()
        #expect(timer.phaseRecords.count == 1)
        #expect(timer.phaseRecords[0].subRecords.count == 2)
        #expect(timer.phaseRecords[0].subRecords[0].name == "clang")
        #expect(timer.phaseRecords[0].subRecords[1].name == "ld")
    }

    @Test
    func testNestedScopesKeepFullLabelsAndTopLevelTotal() {
        let timer = PhaseTimer()
        timer.beginPhase("Sema")
        withSubPhaseTiming("runValidationPasses", timer: timer) {
            withSubPhaseTiming("validateExperimentalVersionOverloadingOptIn", timer: timer) {
                timer.recordSubPhase("detail", startTime: 100, endTime: 200)
            }
        }
        timer.endPhase()
        let phase = timer.phaseRecords[0]
        let validation = phase.subRecords[0]
        #expect(validation.name == "runValidationPasses")
        #expect(validation.subRecords[0].subRecords[0].name == "detail")
        #expect(validation.durationNanos <= phase.durationNanos)
        #expect(timer.totalNanos == phase.durationNanos)
        #expect(timer.summary().contains("    validateExperimentalVersionOverloadingOptIn"))
        #expect(timer.summary().contains("      detail"))
    }

    @Test
    func testThrowingScopeRecordsTimeAndRestoresNesting() {
        enum Failure: Error { case expected }
        let timer = PhaseTimer()
        timer.beginPhase("Codegen")
        do {
            try withSubPhaseTiming("emit", timer: timer) {
                try withSubPhaseTiming("failing", timer: timer) {
                    throw Failure.expected
                }
            }
            Issue.record("Expected scope to throw")
        } catch {}
        withSubPhaseTiming("next", timer: timer) {}
        timer.endPhase()
        #expect(timer.phaseRecords[0].subRecords.map(\.name) == ["emit", "next"])
        #expect(timer.phaseRecords[0].subRecords[0].subRecords[0].name == "failing")
    }

    @Test
    func testDisabledTimingDoesNotEvaluateLabelAndRunsBodyOnce() {
        var labelEvaluations = 0
        var bodyCalls = 0
        func label() -> String {
            labelEvaluations += 1
            return "unused"
        }
        let value = withSubPhaseTiming(label(), timer: nil) {
            bodyCalls += 1
            return 42
        }
        #expect(value == 42)
        #expect(bodyCalls == 1)
        #expect(labelEvaluations == 0)
    }

    @Test
    func testAccumulationExcludesRecursiveOverlapAndResetsBetweenPhases() {
        let timer = PhaseTimer()
        timer.beginPhase("Sema")
        withSubPhaseTiming("analysis", timer: timer) {
            for _ in 0 ..< 3 {
                withSubPhaseTiming("imports.lazyMaterialize", timer: timer, accumulating: true) {
                    withSubPhaseTiming("imports.lazyMaterialize", timer: timer, accumulating: true) {}
                }
            }
        }
        timer.endPhase()
        let phase = timer.phaseRecords[0]
        #expect(phase.subRecords.map(\.name) == ["analysis", "imports.lazyMaterialize"])
        #expect(phase.subRecords[1].durationNanos <= phase.subRecords[0].durationNanos)
        #expect(timer.totalNanos == phase.durationNanos)
        timer.beginPhase("BuildKIR")
        timer.endPhase()
        #expect(timer.phaseRecords[1].subRecords.isEmpty)
    }

    @Test
    func testFailedSubprocessStillRecordsTiming() {
        let timer = PhaseTimer()
        timer.beginPhase("Link")
        #expect(throws: CommandRunnerError.self) {
            try CommandRunner.run(executable: "/bin/sh", arguments: ["-c", "exit 1"],
                                  phaseTimer: timer, subPhaseName: "Link/swiftc")
        }
        timer.endPhase()
        #expect(timer.phaseRecords[0].subRecords.map(\.name) == ["Link/swiftc"])
        #expect(timer.phaseRecords[0].subRecords[0].durationNanos <= timer.totalNanos)
    }

    // MARK: - totalNanos / totalMs

    @Test
    func measuredSubPhasePreservesResultAndRecordsFailures() throws {
        enum ProbeError: Error, Equatable { case expected }
        let timer = PhaseTimer()
        timer.beginPhase("Codegen")
        let answer = PhaseTimer.measureSubPhase("success", timer: timer) { 42 }
        #expect(answer == 42)
        #expect(throws: ProbeError.expected) {
            try PhaseTimer.measureSubPhase("failure", timer: timer) { throw ProbeError.expected }
        }
        timer.endPhase()
        let phase = try #require(timer.phaseRecords.first)
        #expect(phase.subRecords.map(\.name) == ["success", "failure"])
        for record in phase.subRecords {
            #expect(record.startTime >= phase.startTime)
            #expect(record.endTime <= phase.endTime)
        }
        #expect(timer.totalNanos == phase.durationNanos)
        #expect(PhaseTimer.measureSubPhase("disabled", timer: nil) { 7 } == 7)
    }

    @Test
    func testTotalNanosAndMs() {
        let timer = PhaseTimer()
        timer.beginPhase("A")
        timer.endPhase()
        timer.beginPhase("B")
        timer.endPhase()
        // Empty intervals may have zero duration at the clock's resolution.
        #expect(timer.phaseRecords.count == 2)
        let expectedNanos = timer.phaseRecords.reduce(UInt64(0)) { $0 + $1.durationNanos }
        #expect(timer.totalNanos == expectedNanos)
        #expect(timer.totalMs == Double(expectedNanos) / 1_000_000.0)
    }

    @Test
    func testTotalNanosEmptyIsZero() {
        let timer = PhaseTimer()
        #expect(timer.totalNanos == 0)
        #expect(timer.totalMs == 0)
    }

    // MARK: - printSummary

    @Test
    func testPrintSummaryDoesNotCrash() {
        let timer = PhaseTimer()
        timer.beginPhase("Lex")
        timer.endPhase()
        timer.beginPhase("Link")
        timer.recordSubPhase("clang", startTime: 100, endTime: 500)
        timer.endPhase()
        // Just ensure it doesn't crash
        timer.printSummary()
    }
}
#endif
