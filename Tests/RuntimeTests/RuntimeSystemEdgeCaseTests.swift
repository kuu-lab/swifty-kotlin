#if canImport(Testing)
import Dispatch
import Foundation
@testable import Runtime
import Testing

// MARK: - kotlin.system edge case coverage (STDLIB-SYSTEM-003)
//
// Covers: measureTimeMillis, measureTimeMicros, measureNanoTime,
// top-level getTimeMicros/getTimeMillis/getTimeNanos,
// System.currentTimeMillis/System.nanoTime,
// processStartNanos, and exitProcess signature check.
//
// NOTE: exitProcess is not invoked in tests because it calls exit() which is
// process-terminating (Nothing semantics). Compile-time visibility is verified
// by referencing the function pointer type without calling it.

// MARK: - Shared thunks

/// Noop thunk – returns immediately.
private let systemNoopThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in 0 }

/// Thunk that simulates a thrown exception via sentinel value.
private let systemThrowingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    outThrown?.pointee = 0xDEAD
    return 0
}

/// Thunk that sleeps ~10ms (short, deterministic).
private let system10msThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    Thread.sleep(forTimeInterval: 0.010)
    return 0
}

/// Thunk that captures closureRaw for passthrough verification.
private let systemCaptureLock = NSLock()
nonisolated(unsafe) private var _systemCapturedRaw: Int = 0
private var systemCapturedRaw: Int {
    get { systemCaptureLock.lock(); defer { systemCaptureLock.unlock() }; return _systemCapturedRaw }
    set { systemCaptureLock.lock(); defer { systemCaptureLock.unlock() }; _systemCapturedRaw = newValue }
}

private let systemCaptureThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { raw, _ in
    systemCapturedRaw = raw
    return 0
}

// MARK: - RuntimeSystemEdgeCaseTests

@Suite(.serialized)
struct RuntimeSystemEdgeCaseTests {

    @Test
    func testSystemMeasurementRuntimeSignaturesAreFixed() {
        let _: () -> Int = kk_system_currentTimeMillis
        let _: () -> Int = kk_system_nanoTime
        let _: () -> Int = kk_system_getTimeMicros
        let _: () -> Int = kk_system_getTimeMillis
        let _: () -> Int = kk_system_getTimeNanos
        let _: () -> Int = kk_system_process_start_nanos
        let _: (Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_system_measureTimeMillis
        let _: (Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_system_measureTimeMicros
        let _: (Int, Int, UnsafeMutablePointer<Int>?) -> Int = kk_system_measureNanoTime
    }

    // MARK: - kk_system_currentTimeMillis

    @Test
    func testCurrentTimeMillisIsPositive() {
        let ms = kk_system_currentTimeMillis()
        #expect(ms > 0, "currentTimeMillis must be positive (Unix epoch since 1970)")
    }

    @Test
    func testCurrentTimeMillisIsReasonableEpoch() {
        // 2020-01-01 00:00:00 UTC in ms = 1_577_836_800_000
        let ms = kk_system_currentTimeMillis()
        #expect(ms > 1_577_836_800_000, "currentTimeMillis should be after 2020-01-01")
    }

    @Test
    func testCurrentTimeMillisNonDecreasingAcrossConsecutiveCalls() {
        // Wall clock may not be strictly monotonic (NTP), but should be
        // non-decreasing at millisecond granularity across two rapid calls.
        let t1 = kk_system_currentTimeMillis()
        let t2 = kk_system_currentTimeMillis()
        // Allow equal (same millisecond tick) but not backwards.
        #expect(t2 >= t1, "Consecutive currentTimeMillis calls must not decrease")
    }

    @Test
    func testCurrentTimeMillisReturnsDifferentValuesAfterSleep() {
        let before = kk_system_currentTimeMillis()
        Thread.sleep(forTimeInterval: 0.020) // 20ms — well above 1ms resolution
        let after = kk_system_currentTimeMillis()
        #expect(after > before, "currentTimeMillis should advance after a 20ms sleep")
    }

    // MARK: - kk_system_nanoTime (monotonic)

    @Test
    func testNanoTimeIsPositive() {
        let t = kk_system_nanoTime()
        #expect(t > 0, "nanoTime must be positive")
    }

    @Test
    func testNanoTimeIsStrictlyMonotonicAcrossConsecutiveCalls() {
        // mach_absolute_time is strictly monotonic; two successive reads should differ.
        let t1 = kk_system_nanoTime()
        let t2 = kk_system_nanoTime()
        // t2 >= t1 is the hard requirement. t2 > t1 is expected on any real hardware.
        #expect(t2 >= t1, "nanoTime must be non-decreasing (monotonic)")
    }

    @Test
    func testNanoTimeAdvancesMeasurably() {
        let t1 = kk_system_nanoTime()
        Thread.sleep(forTimeInterval: 0.010) // 10ms
        let t2 = kk_system_nanoTime()
        let delta = t2 - t1
        // Expect at least 5ms worth of nanoseconds to account for scheduling jitter.
        #expect(delta > 5_000_000, "nanoTime should advance by > 5ms after a 10ms sleep")
    }

    @Test
    func testNanoTimeIsConsistentWithMonotonicClock() {
        // Verify nanoTime is backed by monotonic clock by checking many successive readings.
        var previous = kk_system_nanoTime()
        for _ in 0..<100 {
            let current = kk_system_nanoTime()
            #expect(current >= previous, "nanoTime went backwards — not monotonic")
            previous = current
        }
    }

    // MARK: - kk_system_getTimeMicros

    @Test
    func testGetTimeMicrosIsPositive() {
        #expect(kk_system_getTimeMicros() > 0, "getTimeMicros must be positive")
    }

    @Test
    func testGetTimeMicrosIsNonDecreasingAcrossConsecutiveCalls() {
        let first = kk_system_getTimeMicros()
        let second = kk_system_getTimeMicros()
        #expect(second >= first, "getTimeMicros must be monotonic at microsecond granularity")
    }

    @Test
    func testGetTimeMicrosAdvancesAfterSleep() {
        let before = kk_system_getTimeMicros()
        Thread.sleep(forTimeInterval: 0.010)
        let after = kk_system_getTimeMicros()
        #expect(after - before > 5_000, "getTimeMicros should advance by > 5ms after a 10ms sleep")
    }

    // MARK: - kk_system_getTimeMillis

    @Test
    func testGetTimeMillisIsPositive() {
        #expect(kk_system_getTimeMillis() > 0, "getTimeMillis must be positive")
    }

    @Test
    func testGetTimeMillisIsReasonableEpoch() {
        let millis = kk_system_getTimeMillis()
        #expect(millis > 1_500_000_000_000, "getTimeMillis should be after 2017")
        #expect(millis < 2_500_000_000_000, "getTimeMillis should be before 2049")
    }

    @Test
    func testGetTimeMillisNonDecreasingAcrossConsecutiveCalls() {
        let first = kk_system_getTimeMillis()
        let second = kk_system_getTimeMillis()
        #expect(second >= first, "getTimeMillis should not go backwards across adjacent calls")
    }

    @Test
    func testGetTimeMillisReturnsDifferentValuesAfterSleep() {
        let before = kk_system_getTimeMillis()
        Thread.sleep(forTimeInterval: 0.030)
        let after = kk_system_getTimeMillis()
        #expect(after > before, "getTimeMillis should advance after a short sleep")
    }

    // MARK: - kk_system_getTimeNanos

    @Test
    func testGetTimeNanosIsPositive() {
        #expect(kk_system_getTimeNanos() > 0, "getTimeNanos must be positive")
    }

    @Test
    func testGetTimeNanosIsConsistentWithMonotonicClock() {
        let before = kk_system_nanoTime()
        let value = kk_system_getTimeNanos()
        let after = kk_system_nanoTime()
        #expect(value >= before, "getTimeNanos should use the monotonic nanoTime clock")
        #expect(value <= after, "getTimeNanos should not exceed a later nanoTime read")
    }

    @Test
    func testGetTimeNanosIsStrictlyMonotonicAcrossConsecutiveCalls() {
        let first = kk_system_getTimeNanos()
        let second = kk_system_getTimeNanos()
        #expect(second > first, "getTimeNanos should normally advance between consecutive calls")
    }

    @Test
    func testGetTimeNanosAdvancesMeasurably() {
        let before = kk_system_getTimeNanos()
        Thread.sleep(forTimeInterval: 0.010)
        let after = kk_system_getTimeNanos()
        #expect(after - before > 5_000_000, "getTimeNanos should advance by > 5ms after a 10ms sleep")
    }

    // MARK: - kk_system_process_start_nanos (stability)

    @Test
    func testProcessStartNanosIsStableAcrossManyCalls() {
        let baseline = kk_system_process_start_nanos()
        for _ in 0..<20 {
            #expect(kk_system_process_start_nanos() == baseline, "processStartNanos must be immutable after initialisation")
        }
    }

    @Test
    func testProcessStartNanosIsBeforeCurrentNanoTime() {
        let start = kk_system_process_start_nanos()
        let now = kk_system_nanoTime()
        #expect(start <= now, "processStartNanos must not be in the future")
    }

    @Test
    func testProcessStartNanosIsNonNegative() {
        #expect(kk_system_process_start_nanos() >= 0)
    }

    // MARK: - kk_system_measureTimeMillis

    @Test
    func testMeasureTimeMillisZeroWorkIsNonNegative() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        #expect(ms >= 0, "measureTimeMillis for zero-work block must be >= 0")
    }

    @Test
    func testMeasureTimeMillisWithSleepIsPlausible() {
        // 10ms sleep should produce >= 5ms (allowing scheduling jitter) and < 500ms
        let fnPtr = unsafeBitCast(system10msThunk, to: Int.self)
        var thrown: Int = 0
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        #expect(ms >= 5, "measureTimeMillis should capture at least ~5ms of a 10ms sleep")
        #expect(ms < 500, "measureTimeMillis should not exceed 500ms for a 10ms sleep")
    }

    @Test
    func testMeasureTimeMillisExceptionReturnsZero() {
        // Kotlin spec: if block throws, exception propagates and no return value.
        // Runtime maps this as: outThrown is set, return value is 0.
        let fnPtr = unsafeBitCast(systemThrowingThunk, to: Int.self)
        var thrown: Int = 0
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        #expect(thrown != 0, "Exception sentinel must be propagated via outThrown")
        #expect(thrown == 0xDEAD, "outThrown must carry the exact exception value")
        #expect(ms == 0, "Return value must be 0 when block throws")
    }

    @Test
    func testMeasureTimeMillisOutThrownResetBeforeInvocation() {
        // Verify outThrown is cleared to 0 before the block runs.
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0xBEEF  // garbage pre-fill
        let ms = kk_system_measureTimeMillis(fnPtr, 0, &thrown)
        #expect(thrown == 0, "outThrown must be cleared for a non-throwing block")
        #expect(ms >= 0)
    }

    @Test
    func testMeasureTimeMillisClosureRawPassthrough() {
        systemCapturedRaw = 0
        let fnPtr = unsafeBitCast(systemCaptureThunk, to: Int.self)
        var thrown: Int = 0
        _ = kk_system_measureTimeMillis(fnPtr, 42, &thrown)
        #expect(thrown == 0)
        #expect(systemCapturedRaw == 42, "measureTimeMillis must forward closureRaw to the thunk")
    }

    @Test
    func testMeasureTimeMillisNilOutThrownDoesNotCrash() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        let ms = kk_system_measureTimeMillis(fnPtr, 0, nil)
        #expect(ms >= 0)
    }

    @Test
    func testMeasureTimeMillisConsecutiveCallsAreIndependent() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown1: Int = 0
        var thrown2: Int = 0
        let ms1 = kk_system_measureTimeMillis(fnPtr, 0, &thrown1)
        let ms2 = kk_system_measureTimeMillis(fnPtr, 0, &thrown2)
        #expect(thrown1 == 0)
        #expect(thrown2 == 0)
        // Both should be non-negative; exact values may differ.
        #expect(ms1 >= 0)
        #expect(ms2 >= 0)
    }

    // MARK: - kk_system_measureTimeMicros

    @Test
    func testMeasureTimeMicrosZeroWorkIsNonNegative() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0
        let us = kk_system_measureTimeMicros(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        #expect(us >= 0, "measureTimeMicros for zero-work block must be >= 0")
    }

    @Test
    func testMeasureTimeMicrosWithSleepIsPlausible() {
        // 10ms sleep should produce >= 5ms (allowing scheduling jitter) and < 500ms
        let fnPtr = unsafeBitCast(system10msThunk, to: Int.self)
        var thrown: Int = 0
        let us = kk_system_measureTimeMicros(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        #expect(us >= 5_000, "measureTimeMicros should capture at least ~5ms of a 10ms sleep")
        #expect(us < 500_000, "measureTimeMicros should not exceed 500ms for a 10ms sleep")
    }

    @Test
    func testMeasureTimeMicrosExceptionReturnsZero() {
        // Kotlin spec: if block throws, exception propagates and no return value.
        // Runtime maps this as: outThrown is set, return value is 0.
        let fnPtr = unsafeBitCast(systemThrowingThunk, to: Int.self)
        var thrown: Int = 0
        let us = kk_system_measureTimeMicros(fnPtr, 0, &thrown)
        #expect(thrown != 0, "Exception sentinel must be propagated via outThrown")
        #expect(thrown == 0xDEAD, "outThrown must carry the exact exception value")
        #expect(us == 0, "Return value must be 0 when block throws")
    }

    @Test
    func testMeasureTimeMicrosOutThrownResetBeforeInvocation() {
        // Verify outThrown is cleared to 0 before the block runs.
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0xBEEF  // garbage pre-fill
        let us = kk_system_measureTimeMicros(fnPtr, 0, &thrown)
        #expect(thrown == 0, "outThrown must be cleared for a non-throwing block")
        #expect(us >= 0)
    }

    @Test
    func testMeasureTimeMicrosClosureRawPassthrough() {
        systemCapturedRaw = 0
        let fnPtr = unsafeBitCast(systemCaptureThunk, to: Int.self)
        var thrown: Int = 0
        _ = kk_system_measureTimeMicros(fnPtr, 123, &thrown)
        #expect(thrown == 0)
        #expect(systemCapturedRaw == 123, "measureTimeMicros must forward closureRaw to the thunk")
    }

    @Test
    func testMeasureTimeMicrosNilOutThrownDoesNotCrash() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        let us = kk_system_measureTimeMicros(fnPtr, 0, nil)
        #expect(us >= 0)
    }

    // MARK: - kk_system_measureNanoTime

    @Test
    func testMeasureNanoTimeZeroWorkIsNonNegative() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        #expect(ns >= 0, "measureNanoTime for zero-work block must be >= 0")
    }

    @Test
    func testMeasureNanoTimeWithSleepIsPlausible() {
        // 10ms sleep -> expect >= 5_000_000 ns (5ms) and < 500_000_000 ns (500ms)
        let fnPtr = unsafeBitCast(system10msThunk, to: Int.self)
        var thrown: Int = 0
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        #expect(ns >= 5_000_000, "measureNanoTime should capture >= 5ms of a 10ms sleep")
        #expect(ns < 500_000_000, "measureNanoTime should not exceed 500ms for a 10ms sleep")
    }

    @Test
    func testMeasureNanoTimeExceptionReturnsZero() {
        let fnPtr = unsafeBitCast(systemThrowingThunk, to: Int.self)
        var thrown: Int = 0
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        #expect(thrown != 0, "Exception sentinel must be propagated via outThrown")
        #expect(thrown == 0xDEAD)
        #expect(ns == 0, "Return value must be 0 when block throws")
    }

    @Test
    func testMeasureNanoTimeOutThrownResetBeforeInvocation() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0xBEEF
        let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        #expect(thrown == 0, "outThrown must be cleared for a non-throwing block")
        #expect(ns >= 0)
    }

    @Test
    func testMeasureNanoTimeClosureRawPassthrough() {
        systemCapturedRaw = 0
        let fnPtr = unsafeBitCast(systemCaptureThunk, to: Int.self)
        var thrown: Int = 0
        _ = kk_system_measureNanoTime(fnPtr, 99, &thrown)
        #expect(thrown == 0)
        #expect(systemCapturedRaw == 99, "measureNanoTime must forward closureRaw to the thunk")
    }

    @Test
    func testMeasureNanoTimeNilOutThrownDoesNotCrash() {
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        let ns = kk_system_measureNanoTime(fnPtr, 0, nil)
        #expect(ns >= 0)
    }

    @Test
    func testMeasureNanoTimeIsMonotonicRelativeToNanoTime() {
        // measureNanoTime elapsed must be <= actual wall-clock delta + slack.
        let before = kk_system_nanoTime()
        let fnPtr = unsafeBitCast(system10msThunk, to: Int.self)
        var thrown: Int = 0
        let measured = kk_system_measureNanoTime(fnPtr, 0, &thrown)
        let after = kk_system_nanoTime()
        #expect(thrown == 0)
        let wall = after - before
        // measured <= wall (plus a 2ms slack for measurement overhead)
        let slackNs = 2_000_000
        #expect(measured <= wall + slackNs, "measureNanoTime elapsed should not exceed enclosing wall-clock time")
    }

    @Test
    func testMeasureNanoTimeExceedsMillisPrecision() {
        // nanoTime should provide sub-millisecond precision; verify it's not
        // constrained to millisecond granularity like measureTimeMillis.
        let fnPtr = unsafeBitCast(systemNoopThunk, to: Int.self)
        var thrown: Int = 0
        var hasSubMillisecond = false
        for _ in 0..<20 {
            let ns = kk_system_measureNanoTime(fnPtr, 0, &thrown)
            if ns > 0 && ns < 1_000_000 { // 0 < ns < 1ms
                hasSubMillisecond = true
                break
            }
        }
        #expect(hasSubMillisecond, "measureNanoTime should occasionally return sub-millisecond values for a noop block")
    }

    // MARK: - exitProcess compile-time visibility

    @Test
    func testExitProcessSymbolIsVisible() {
        // We cannot call exit() in a test (it terminates the process).
        // Verify the symbol is accessible at compile time by referencing its type.
        // The type `(Int) -> Never` matches Kotlin's Nothing semantics.
        let _: (Int) -> Never = kk_system_exitProcess
        // If this line compiles, the symbol is correctly exported.
    }
}
#endif
