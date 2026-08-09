import Dispatch
import Foundation
@testable import Runtime
import Testing

// MARK: - kotlin.time experimental API edge case coverage (STDLIB-TIME-EXP-001)
//
// Covers: TimeSource.Monotonic, TimeMark, markNow(), elapsedNow(), plus/minus Duration,
// hasPassedNow/hasNotPassedNow, ComparableTimeMark (compare/minus-mark), Clock interface
// stubs (kk_time_source_mark_now), POSIX-backed monotonic clock variants, duration
// overflow/saturation, toString on elapsed duration, and monotonicity invariants.

@Suite(.runtimeIsolation(.gcOnly))
struct RuntimeExperimentalTimeEdgeCaseTests {
    // MARK: - Helpers

    private func stringFromHandle(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return extractString(from: ptr)
    }

    // MARK: - kk_time_source_mark_now (generic Clock interface stub)

    /// kk_time_source_mark_now is the generic Clock.markNow() entry point.
    /// It must return a non-zero handle backed by a valid TimeMark.
    @Test func genericTimeSourceMarkNowReturnsValidHandle() {
        let mark = kk_time_source_mark_now(0)
        #expect(mark != 0, "kk_time_source_mark_now must return a non-zero handle")
    }

    /// The generic entry point and the Monotonic-specific one must agree on source semantics:
    /// both are backed by DispatchTime.now().uptimeNanoseconds, so two consecutive marks
    /// from either entry point should be non-decreasing.
    @Test func genericAndMonotonicMarkNowAreNonDecreasing() {
        let generic = kk_time_source_mark_now(0)
        let monotonic = kk_time_source_monotonic_mark_now(0)
        // elapsed on generic >= 0 means monotonic clock didn't go back between the two calls.
        let elapsed = timeMarkElapsedNow(generic)
        #expect(kk_duration_inWholeNanoseconds(elapsed) >= 0,
            "Elapsed time from generic Clock.markNow() must be >= 0")
        // monotonic mark created after generic should compare >= generic
        let cmp = timeMarkCompare(monotonic, generic)
        #expect(cmp >= 0,
            "Monotonic mark taken after generic mark must not be earlier")
    }

    // MARK: - kk_clock_monotonic_mark_now (POSIX CLOCK_MONOTONIC variant)

    @Test func posixClockMonotonicMarkNowReturnsValidHandle() {
        let mark = kk_clock_monotonic_mark_now()
        #expect(mark != 0, "kk_clock_monotonic_mark_now must return a non-zero handle")
    }

    /// kk_clock_monotonic_mark_now is backed by POSIX CLOCK_MONOTONIC, which does NOT share
    /// the same epoch as DispatchTime.now().uptimeNanoseconds used by timeMarkElapsedNow.
    /// So we cannot call timeMarkElapsedNow on a POSIX mark and expect a meaningful result.
    /// Instead we verify the mark handle itself is valid (non-zero).
    @Test func posixClockMonotonicMarkNowReturnsNonZeroHandle() {
        let mark = kk_clock_monotonic_mark_now()
        #expect(mark != 0,
            "POSIX monotonic mark must yield a non-zero handle")
    }

    @Test func posixClockMonotonicMarkNowIsNonDecreasingAcrossReads() {
        // 20 consecutive POSIX-clock marks must never go backwards.
        var prev = kk_clock_monotonic_mark_now()
        for i in 1...20 {
            let curr = kk_clock_monotonic_mark_now()
            let cmp = timeMarkCompare(curr, prev)
            #expect(cmp >= 0,
                "POSIX monotonic clock went backwards at iteration \(i)")
            prev = curr
        }
    }

    // MARK: - kk_clock_gettime_monotonic_ns (raw nanoseconds)

    @Test func clockGettimeMonotonicNsIsPositive() {
        let ns = kk_clock_gettime_monotonic_ns()
        #expect(ns > 0, "POSIX CLOCK_MONOTONIC ns value must be positive")
    }

    @Test func clockGettimeMonotonicNsIsNonDecreasing() {
        let t1 = kk_clock_gettime_monotonic_ns()
        let t2 = kk_clock_gettime_monotonic_ns()
        #expect(t2 >= t1,
            "kk_clock_gettime_monotonic_ns must be non-decreasing (monotonic)")
    }

    // MARK: - elapsedNow() always non-negative for present/past marks

    @Test func elapsedNowOnPastMarkIsNonNegative() {
        // A mark taken 100ms in the "past" (shifted backward) should have elapsed >= 100ms.
        let mark = kk_time_source_monotonic_mark_now(0)
        let pastMark = timeMarkMinusDuration(mark, durationFromMilliseconds(100))
        let elapsed = timeMarkElapsedNow(pastMark)
        let elapsedMs = durationInWholeMilliseconds(elapsed)
        #expect(elapsedMs >= 100,
            "Elapsed for a mark set 100ms in the past should be >= 100ms")
    }

    @Test func elapsedNowOnFutureMarkIsNegative() {
        // A mark 10 seconds in the future has negative elapsed (not yet reached).
        let mark = kk_time_source_monotonic_mark_now(0)
        let futureMark = timeMarkPlusDuration(mark, durationFromSeconds(10))
        let elapsed = timeMarkElapsedNow(futureMark)
        #expect(kk_duration_inWholeNanoseconds(elapsed) < 0,
            "Elapsed for a far-future mark should be negative")
    }

    // MARK: - Monotonic source: consecutive markNow() never decreases

    @Test func monotonicSourceNeverDecreases() {
        var prev = kk_time_source_monotonic_mark_now(0)
        for i in 1...50 {
            let curr = kk_time_source_monotonic_mark_now(0)
            let diff = timeMarkMinusMark(curr, prev)  // curr - prev
            #expect(kk_duration_inWholeNanoseconds(diff) >= 0,
                "Monotonic source went backwards at iteration \(i)")
            prev = curr
        }
    }

    // MARK: - Duration arithmetic on TimeMark: consistency

    /// (mark + d).elapsedNow() should be approximately (mark.elapsedNow() - d).
    /// We verify the sign relationship: a mark shifted +1 second should have elapsed
    /// roughly 1 second less than the original mark.
    @Test func plusOnSecondReducesElapsedByThatDuration() {
        let mark = kk_time_source_monotonic_mark_now(0)
        // Shift 1 second forward
        let shiftedMark = timeMarkPlusDuration(mark, durationFromSeconds(1))
        // shiftedMark.elapsedNow() should be roughly mark.elapsedNow() - 1s
        // Since the mark is ~1s in the future, elapsedNow should be negative (future).
        // With only nanoseconds elapsed since markNow(), that means approximately -1s.
        let elapsedShifted = timeMarkElapsedNow(shiftedMark)
        let elapsedOriginal = timeMarkElapsedNow(mark)
        let elapsedShiftedNs = kk_duration_inWholeNanoseconds(elapsedShifted)
        let elapsedOriginalNs = kk_duration_inWholeNanoseconds(elapsedOriginal)
        // elapsedShiftedNs ≈ elapsedOriginalNs - 1_000_000_000
        // Allow 50ms slack for test execution time between the two elapsedNow() calls.
        let slackNs = 50_000_000
        let difference = elapsedOriginalNs - elapsedShiftedNs
        #expect(difference >= 1_000_000_000 - slackNs,
            "elapsed(original) - elapsed(original+1s) should be approximately 1s")
        #expect(difference <= 1_000_000_000 + slackNs,
            "elapsed(original) - elapsed(original+1s) should be approximately 1s (upper bound)")
    }

    @Test func minusOnSecondIncreasesElapsedByThatDuration() {
        let mark = kk_time_source_monotonic_mark_now(0)
        // Shift 1 second backward → already 1 second in the past
        let pastMark = timeMarkMinusDuration(mark, durationFromSeconds(1))
        let elapsedPast = timeMarkElapsedNow(pastMark)
        let elapsedOriginal = timeMarkElapsedNow(mark)
        let elapsedPastNs = kk_duration_inWholeNanoseconds(elapsedPast)
        let elapsedOriginalNs = kk_duration_inWholeNanoseconds(elapsedOriginal)
        // elapsedPastNs ≈ elapsedOriginalNs + 1_000_000_000
        let slackNs = 50_000_000
        let difference = elapsedPastNs - elapsedOriginalNs
        #expect(difference >= 1_000_000_000 - slackNs,
            "elapsed(original-1s) - elapsed(original) should be approximately 1s")
        #expect(difference <= 1_000_000_000 + slackNs,
            "elapsed(original-1s) - elapsed(original) should be approximately 1s (upper bound)")
    }

    // MARK: - hasPassedNow / hasNotPassedNow transitions

    /// A mark set 1 second in the past must have already passed.
    @Test func pastMarkHasPassedNow() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let pastMark = timeMarkMinusDuration(mark, durationFromSeconds(1))
        #expect(timeMarkHasPassedNow(pastMark) == 1,
            "A mark 1s in the past must report hasPassedNow() == true")
        #expect(timeMarkHasNotPassedNow(pastMark) == 0,
            "A mark 1s in the past must report hasNotPassedNow() == false")
    }

    /// A mark set 10 seconds in the future must NOT have passed yet.
    @Test func futureMarkHasNotPassedNow() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let futureMark = timeMarkPlusDuration(mark, durationFromSeconds(10))
        #expect(timeMarkHasNotPassedNow(futureMark) == 1,
            "A mark 10s in the future must report hasNotPassedNow() == true")
        #expect(timeMarkHasPassedNow(futureMark) == 0,
            "A mark 10s in the future must report hasPassedNow() == false")
    }

    /// hasPassedNow and hasNotPassedNow must be mutually exclusive for any mark.
    @Test func hasPassedAndHasNotPassedAreMutuallyExclusive() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let pastMark = timeMarkMinusDuration(mark, durationFromMilliseconds(100))
        let futureMark = timeMarkPlusDuration(mark, durationFromSeconds(10))
        // past mark
        #expect(timeMarkHasPassedNow(pastMark) != timeMarkHasNotPassedNow(pastMark),
            "hasPassedNow and hasNotPassedNow must differ for past mark")
        // future mark
        #expect(timeMarkHasPassedNow(futureMark) != timeMarkHasNotPassedNow(futureMark),
            "hasPassedNow and hasNotPassedNow must differ for future mark")
    }

    // MARK: - ComparableTimeMark: compare

    @Test func compareMarkToSelfIsZero() {
        let mark = kk_time_source_monotonic_mark_now(0)
        #expect(timeMarkCompare(mark, mark) == 0,
            "A TimeMark compared to itself must return 0")
    }

    @Test func compareEarlierMarkIsNegative() {
        // earlier < later → compare(earlier, later) < 0
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = timeMarkPlusDuration(earlier, durationFromMilliseconds(100))
        #expect(timeMarkCompare(earlier, later) < 0,
            "compare(earlier, later) should be negative")
    }

    @Test func compareLaterMarkIsPositive() {
        // later > earlier → compare(later, earlier) > 0
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = timeMarkPlusDuration(earlier, durationFromMilliseconds(100))
        #expect(timeMarkCompare(later, earlier) > 0,
            "compare(later, earlier) should be positive")
    }

    @Test func compareAntisymmetry() {
        let a = kk_time_source_monotonic_mark_now(0)
        let b = timeMarkPlusDuration(a, durationFromMilliseconds(50))
        let ab = timeMarkCompare(a, b)
        let ba = timeMarkCompare(b, a)
        #expect((ab < 0 && ba > 0) || (ab > 0 && ba < 0) || (ab == 0 && ba == 0),
            "compare must be antisymmetric: sign(compare(a,b)) == -sign(compare(b,a))")
    }

    // MARK: - ComparableTimeMark: minus-mark (Duration subtraction)

    @Test func minusMarkSameMarkGivesZeroDuration() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let diff = timeMarkMinusMark(mark, mark)
        #expect(kk_duration_inWholeNanoseconds(diff) == 0,
            "mark - mark must equal zero duration")
    }

    @Test func minusMarkLaterMinusEarlierIsPositive() {
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = timeMarkPlusDuration(earlier, durationFromMilliseconds(200))
        let diff = timeMarkMinusMark(later, earlier)
        #expect(durationInWholeMilliseconds(diff) == 200,
            "later - earlier should yield the exact shifted duration")
    }

    @Test func minusMarkEarlierMinusLaterIsNegative() {
        let earlier = kk_time_source_monotonic_mark_now(0)
        let later = timeMarkPlusDuration(earlier, durationFromMilliseconds(300))
        let diff = timeMarkMinusMark(earlier, later)
        #expect(durationInWholeMilliseconds(diff) == -300,
            "earlier - later should yield negative duration")
    }

    // MARK: - Duration overflow / saturation in TimeMark arithmetic

    /// Adding Duration.INFINITE (represented as Int64.max nanoseconds) should saturate,
    /// not crash or wrap around.
    @Test func plusDurationSaturatesAtInt64Max() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let infiniteDuration = durationFromNanoseconds(Int(Int64.max))
        let saturatedMark = timeMarkPlusDuration(mark, infiniteDuration)
        // The result must be a valid handle (non-zero).
        #expect(saturatedMark != 0,
            "Saturated TimeMark from + Duration.INFINITE must still yield a valid handle")
        // elapsedNow on a mark saturated at Int64.max should be a very large negative number
        // or very small positive (depends on system uptime vs Int64.max). Mainly: no crash.
        let elapsed = timeMarkElapsedNow(saturatedMark)
        _ = kk_duration_inWholeNanoseconds(elapsed)  // must not crash
    }

    /// Subtracting Duration.INFINITE should saturate to Int64.min, not crash.
    @Test func minusDurationSaturatesAtInt64Min() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let infiniteDuration = durationFromNanoseconds(Int(Int64.max))
        let saturatedMark = timeMarkMinusDuration(mark, infiniteDuration)
        #expect(saturatedMark != 0,
            "Saturated TimeMark from - Duration.INFINITE must yield a valid handle")
        // A mark in the extreme past must have passed.
        #expect(timeMarkHasPassedNow(saturatedMark) == 1,
            "A mark saturated at Int64.min nanoseconds must report hasPassedNow")
        _ = timeMarkElapsedNow(saturatedMark)  // must not crash
    }

    /// minus-mark on saturated marks: saturation must not produce NaN-like garbage.
    @Test func minusMarkOnSaturatedMarksDoesNotCrash() {
        let a = kk_time_source_monotonic_mark_now(0)
        let inf = durationFromNanoseconds(Int(Int64.max))
        let maxMark = timeMarkPlusDuration(a, inf)
        let minMark = timeMarkMinusDuration(a, inf)
        let diff = timeMarkMinusMark(maxMark, minMark)
        // diff must be a valid duration handle (non-zero); exact value may saturate.
        #expect(diff != 0,
            "minus-mark on saturated TimeMarks must return a valid duration handle")
    }

    // MARK: - TimeMark elapsedNow toString

    /// The Duration returned by elapsedNow() must produce a non-empty string with
    /// a valid time-unit suffix when passed to kk_duration_toString.
    @Test func elapsedNowDurationToStringHasValidSuffix() throws {
        let mark = kk_time_source_monotonic_mark_now(0)
        // Shift the mark 50ms into the past so elapsedNow is clearly positive.
        let pastMark = timeMarkMinusDuration(mark, durationFromMilliseconds(50))
        let elapsed = timeMarkElapsedNow(pastMark)
        let strHandle = kk_duration_toString(elapsed)
        let str = try #require(stringFromHandle(strHandle),
            "kk_duration_toString returned nil handle for elapsed duration")
        let validSuffixes = ["ns", "us", "ms", "s", "m", "h"]
        let hasValidSuffix = validSuffixes.contains { str.hasSuffix($0) }
        #expect(hasValidSuffix,
            "elapsedNow duration toString should end with a time-unit suffix; got: \(str)")
        #expect(!str.isEmpty, "elapsedNow duration toString must not be empty")
    }

    // MARK: - Multiple independent TimeMarks from same source

    @Test func twoMarksFromSameSourceCanSubtractToDuration() {
        let first = kk_time_source_monotonic_mark_now(0)
        let second = kk_time_source_monotonic_mark_now(0)
        // Both are from the same (Monotonic) source, so subtraction is valid.
        let diff = timeMarkMinusMark(second, first)
        // second was taken after first → diff >= 0
        #expect(kk_duration_inWholeNanoseconds(diff) >= 0,
            "second - first from same source must be >= 0")
    }

    @Test func multipleConsecutiveMarksAreStrictlyOrdered() {
        // 10 consecutive marks from Monotonic should be non-decreasing.
        var marks: [Int] = []
        for _ in 0..<10 {
            marks.append(kk_time_source_monotonic_mark_now(0))
        }
        for i in 1..<marks.count {
            let cmp = timeMarkCompare(marks[i], marks[i - 1])
            #expect(cmp >= 0,
                "Consecutive Monotonic marks must be non-decreasing at index \(i)")
        }
    }

    // MARK: - timeMarkPlusDuration / minus_duration round-trip

    @Test func plusMinusRoundTripRestoresOriginalMark() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let d = durationFromMilliseconds(250)
        let shifted = timeMarkPlusDuration(mark, d)
        let restored = timeMarkMinusDuration(shifted, d)
        // restored == mark (same uptimeNanoseconds)
        #expect(timeMarkCompare(restored, mark) == 0,
            "mark + d - d must equal the original mark")
    }

    @Test func minusPlusRoundTripRestoresOriginalMark() {
        let mark = kk_time_source_monotonic_mark_now(0)
        let d = durationFromMilliseconds(250)
        let shifted = timeMarkMinusDuration(mark, d)
        let restored = timeMarkPlusDuration(shifted, d)
        #expect(timeMarkCompare(restored, mark) == 0,
            "mark - d + d must equal the original mark")
    }

    // MARK: - hasPassedNow with zero-offset mark (current moment)

    @Test func zeroShiftMarkIsConsideredPassed() {
        // A mark with no shift from "now" — by the time we check, it's past.
        let mark = kk_time_source_monotonic_mark_now(0)
        // Even with zero elapsed, elapsedNow >= 0 so it has passed.
        let elapsed = timeMarkElapsedNow(mark)
        #expect(kk_duration_inWholeNanoseconds(elapsed) >= 0,
            "A mark taken at 'now' must have non-negative elapsed immediately after")
        #expect(timeMarkHasPassedNow(mark) == 1,
            "A mark taken at the current moment must immediately be considered passed")
    }

    // MARK: - Parallel calls to markNow produce independent handles

    private final class MarkHandlesBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []
        func append(_ v: Int) { lock.lock(); values.append(v); lock.unlock() }
        func snapshot() -> [Int] { lock.lock(); let s = values; lock.unlock(); return s }
    }

    @Test func parallelMarkNowCallsProduceDistinctHandles() async {
        let box = MarkHandlesBox()

        await withTaskGroup(of: Void.self) { group in
            for _ in 0..<4 {
                group.addTask {
                    let handle = kk_time_source_monotonic_mark_now(0)
                    box.append(handle)
                }
            }
        }

        let handles = box.snapshot()
        #expect(handles.count == 4, "All 4 parallel markNow calls should complete")
        // Each mark must produce a distinct allocation handle.
        let unique = Set(handles)
        #expect(unique.count == 4,
            "All parallel markNow calls must produce distinct handles")
    }
}
