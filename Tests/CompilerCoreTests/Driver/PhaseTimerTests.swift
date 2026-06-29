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

    // MARK: - totalNanos / totalMs

    @Test
    func testTotalNanosAndMs() {
        let timer = PhaseTimer()
        timer.beginPhase("A")
        timer.endPhase()
        timer.beginPhase("B")
        timer.endPhase()
        // totalNanos should be sum of all durations
        #expect(timer.totalNanos > 0)
        #expect(timer.totalMs >= 0)
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
