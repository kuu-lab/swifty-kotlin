#if canImport(Testing)
import Foundation
@testable import Runtime
import Testing

// MARK: - kotlin.system edge case coverage (STDLIB-SYSTEM-003)
//
// Covers the __kk_system_* OS bridges (KSP-617): getTimeMicros/getTimeMillis/
// getTimeNanos, currentTimeMillis/nanoTime, processStartNanos, and the
// exitProcess signature check. measureTime* live in bundled Kotlin source and
// no longer have a runtime entry point.
//
// NOTE: exitProcess is not invoked in tests because it calls exit() which is
// process-terminating (Nothing semantics). Compile-time visibility is verified
// by referencing the function pointer type without calling it.

// MARK: - RuntimeSystemEdgeCaseTests

@Suite(.serialized)
struct RuntimeSystemEdgeCaseTests {

    @Test
    func testSystemMeasurementRuntimeSignaturesAreFixed() {
        let _: () -> Int = __kk_system_currentTimeMillis
        let _: () -> Int = __kk_system_nanoTime
        let _: () -> Int = __kk_system_getTimeMicros
        let _: () -> Int = __kk_system_getTimeMillis
        let _: () -> Int = __kk_system_getTimeNanos
        let _: () -> Int = __kk_system_process_start_nanos
    }

    // MARK: - __kk_system_currentTimeMillis

    @Test
    func testCurrentTimeMillisIsPositive() {
        let ms = __kk_system_currentTimeMillis()
        #expect(ms > 0, "currentTimeMillis must be positive (Unix epoch since 1970)")
    }

    @Test
    func testCurrentTimeMillisIsReasonableEpoch() {
        // 2020-01-01 00:00:00 UTC in ms = 1_577_836_800_000
        let ms = __kk_system_currentTimeMillis()
        #expect(ms > 1_577_836_800_000, "currentTimeMillis should be after 2020-01-01")
    }

    @Test
    func testCurrentTimeMillisNonDecreasingAcrossConsecutiveCalls() {
        // Wall clock may not be strictly monotonic (NTP), but should be
        // non-decreasing at millisecond granularity across two rapid calls.
        let t1 = __kk_system_currentTimeMillis()
        let t2 = __kk_system_currentTimeMillis()
        // Allow equal (same millisecond tick) but not backwards.
        #expect(t2 >= t1, "Consecutive currentTimeMillis calls must not decrease")
    }

    @Test
    func testCurrentTimeMillisReturnsDifferentValuesAfterSleep() {
        let before = __kk_system_currentTimeMillis()
        Thread.sleep(forTimeInterval: 0.020) // 20ms — well above 1ms resolution
        let after = __kk_system_currentTimeMillis()
        #expect(after > before, "currentTimeMillis should advance after a 20ms sleep")
    }

    // MARK: - __kk_system_nanoTime (monotonic)

    @Test
    func testNanoTimeIsPositive() {
        let t = __kk_system_nanoTime()
        #expect(t > 0, "nanoTime must be positive")
    }

    @Test
    func testNanoTimeIsStrictlyMonotonicAcrossConsecutiveCalls() {
        // mach_absolute_time is strictly monotonic; two successive reads should differ.
        let t1 = __kk_system_nanoTime()
        let t2 = __kk_system_nanoTime()
        // t2 >= t1 is the hard requirement. t2 > t1 is expected on any real hardware.
        #expect(t2 >= t1, "nanoTime must be non-decreasing (monotonic)")
    }

    @Test
    func testNanoTimeAdvancesMeasurably() {
        let t1 = __kk_system_nanoTime()
        Thread.sleep(forTimeInterval: 0.010) // 10ms
        let t2 = __kk_system_nanoTime()
        let delta = t2 - t1
        // Expect at least 5ms worth of nanoseconds to account for scheduling jitter.
        #expect(delta > 5_000_000, "nanoTime should advance by > 5ms after a 10ms sleep")
    }

    @Test
    func testNanoTimeIsConsistentWithMonotonicClock() {
        // Verify nanoTime is backed by monotonic clock by checking many successive readings.
        var previous = __kk_system_nanoTime()
        for _ in 0..<100 {
            let current = __kk_system_nanoTime()
            #expect(current >= previous, "nanoTime went backwards — not monotonic")
            previous = current
        }
    }

    // MARK: - __kk_system_getTimeMicros

    @Test
    func testGetTimeMicrosIsPositive() {
        #expect(__kk_system_getTimeMicros() > 0, "getTimeMicros must be positive")
    }

    @Test
    func testGetTimeMicrosIsNonDecreasingAcrossConsecutiveCalls() {
        let first = __kk_system_getTimeMicros()
        let second = __kk_system_getTimeMicros()
        #expect(second >= first, "getTimeMicros must be monotonic at microsecond granularity")
    }

    @Test
    func testGetTimeMicrosAdvancesAfterSleep() {
        let before = __kk_system_getTimeMicros()
        Thread.sleep(forTimeInterval: 0.010)
        let after = __kk_system_getTimeMicros()
        #expect(after - before > 5_000, "getTimeMicros should advance by > 5ms after a 10ms sleep")
    }

    // MARK: - __kk_system_getTimeMillis

    @Test
    func testGetTimeMillisIsPositive() {
        #expect(__kk_system_getTimeMillis() > 0, "getTimeMillis must be positive")
    }

    @Test
    func testGetTimeMillisIsReasonableEpoch() {
        let millis = __kk_system_getTimeMillis()
        #expect(millis > 1_500_000_000_000, "getTimeMillis should be after 2017")
        #expect(millis < 2_500_000_000_000, "getTimeMillis should be before 2049")
    }

    @Test
    func testGetTimeMillisNonDecreasingAcrossConsecutiveCalls() {
        let first = __kk_system_getTimeMillis()
        let second = __kk_system_getTimeMillis()
        #expect(second >= first, "getTimeMillis should not go backwards across adjacent calls")
    }

    @Test
    func testGetTimeMillisReturnsDifferentValuesAfterSleep() {
        let before = __kk_system_getTimeMillis()
        Thread.sleep(forTimeInterval: 0.030)
        let after = __kk_system_getTimeMillis()
        #expect(after > before, "getTimeMillis should advance after a short sleep")
    }

    // MARK: - __kk_system_getTimeNanos

    @Test
    func testGetTimeNanosIsPositive() {
        #expect(__kk_system_getTimeNanos() > 0, "getTimeNanos must be positive")
    }

    @Test
    func testGetTimeNanosIsConsistentWithMonotonicClock() {
        let before = __kk_system_nanoTime()
        let value = __kk_system_getTimeNanos()
        let after = __kk_system_nanoTime()
        #expect(value >= before, "getTimeNanos should use the monotonic nanoTime clock")
        #expect(value <= after, "getTimeNanos should not exceed a later nanoTime read")
    }

    @Test
    func testGetTimeNanosIsStrictlyMonotonicAcrossConsecutiveCalls() {
        let first = __kk_system_getTimeNanos()
        let second = __kk_system_getTimeNanos()
        #expect(second > first, "getTimeNanos should normally advance between consecutive calls")
    }

    @Test
    func testGetTimeNanosAdvancesMeasurably() {
        let before = __kk_system_getTimeNanos()
        Thread.sleep(forTimeInterval: 0.010)
        let after = __kk_system_getTimeNanos()
        #expect(after - before > 5_000_000, "getTimeNanos should advance by > 5ms after a 10ms sleep")
    }

    // MARK: - __kk_system_process_start_nanos (stability)

    @Test
    func testProcessStartNanosIsStableAcrossManyCalls() {
        let baseline = __kk_system_process_start_nanos()
        for _ in 0..<20 {
            #expect(__kk_system_process_start_nanos() == baseline, "processStartNanos must be immutable after initialisation")
        }
    }

    @Test
    func testProcessStartNanosIsBeforeCurrentNanoTime() {
        let start = __kk_system_process_start_nanos()
        let now = __kk_system_nanoTime()
        #expect(start <= now, "processStartNanos must not be in the future")
    }

    @Test
    func testProcessStartNanosIsNonNegative() {
        #expect(__kk_system_process_start_nanos() >= 0)
    }

    // MARK: - exitProcess compile-time visibility

    @Test
    func testExitProcessSymbolIsVisible() {
        // We cannot call exit() in a test (it terminates the process).
        // Verify the symbol is accessible at compile time by referencing its type.
        // The type `(Int) -> Never` matches Kotlin's Nothing semantics.
        let _: (Int) -> Never = __kk_system_exitProcess
        // If this line compiles, the symbol is correctly exported.
    }
}
#endif
