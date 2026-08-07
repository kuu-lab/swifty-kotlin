import Dispatch
import Foundation
@testable import Runtime
import Testing

// Runtime テストの下限時間（短縮候補・フレークに注意）: 本ファイルの ~50ms sleep（measureTime）、
// RuntimeFlowTests の usleep、RuntimeChannelTests / RuntimeMutexTests の期待待ち 2s 前後、
// RuntimeReadWriteLockTests のセマフォ待ち 2s など。

// MARK: - C-callable thunks for kk_measureTime tests

/// A no-op closure thunk that returns 0 immediately.
private let noopThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    0
}

/// A closure thunk that sleeps ~50ms before returning.
private let sleep50msThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
    Thread.sleep(forTimeInterval: 0.05)
    return 0
}

/// Global to capture closureRaw value passed to the thunk.
/// Access is single-threaded in tests; disable concurrency-safety check.
private let capturedClosureRawLock = NSLock()
nonisolated(unsafe) private var _capturedClosureRaw: Int = 0

private var capturedClosureRaw: Int {
    get {
        capturedClosureRawLock.lock()
        defer { capturedClosureRawLock.unlock() }
        return _capturedClosureRaw
    }
    set {
        capturedClosureRawLock.lock()
        defer { capturedClosureRawLock.unlock() }
        _capturedClosureRaw = newValue
    }
}

/// A closure thunk that captures its closureRaw value into a global for verification.
private let captureClosureRawThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { closureRaw, _ in
    capturedClosureRaw = closureRaw
    return 0
}

/// A closure thunk that simulates a thrown exception by writing to outThrown.
private let throwingThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, outThrown in
    // Simulate a thrown exception with a sentinel value.
    outThrown?.pointee = 0xDEAD
    return 0
}

private func resetRuntimeDurationTestState() {
    capturedClosureRaw = 0
}

@Suite(.runtimeIsolation(.gcOnly, resetAdditionalState: resetRuntimeDurationTestState))
struct RuntimeDurationTests {
    private final class DurationResultsBox: @unchecked Sendable {
        private let lock = NSLock()
        private var values: [Int] = []

        func append(_ value: Int) {
            lock.lock()
            values.append(value)
            lock.unlock()
        }

        func snapshot() -> [Int] {
            lock.lock()
            let snapshot = values
            lock.unlock()
            return snapshot
        }
    }

    // MARK: - Helper

    /// Extract the Swift String from a duration toString handle.
    /// Note: Uses UnsafeMutableRawPointer because extractString(from:) requires it.
    private func stringFromHandle(_ raw: Int) -> String? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return extractString(from: ptr)
    }

    private func stringHandle(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    // KSP-471: Duration construction/inWhole* helpers (durationFrom*, durationInWhole*)
    // live in RuntimeTestIsolationSupport.swift, shared across Runtime test files.

    // MARK: - Factory: durationFromNanoseconds

    @Test func testFromNanosecondsStoresExactValue() {
        let handle = durationFromNanoseconds(500)
        #expect(kk_duration_inWholeNanoseconds(handle) == 500)
    }

    @Test func testFromNanosecondsZero() {
        let handle = durationFromNanoseconds(0)
        #expect(kk_duration_inWholeNanoseconds(handle) == 0)
    }

    @Test func testFromNanosecondsNegative() {
        let handle = durationFromNanoseconds(-1000)
        #expect(kk_duration_inWholeNanoseconds(handle) == -1000)
    }

    // MARK: - Factory: durationFromMicroseconds

    @Test func testFromMicrosecondsConvertsToNanoseconds() {
        let handle = durationFromMicroseconds(3)
        #expect(kk_duration_inWholeNanoseconds(handle) == 3000)
    }

    @Test func testFromMicrosecondsZero() {
        let handle = durationFromMicroseconds(0)
        #expect(kk_duration_inWholeNanoseconds(handle) == 0)
    }

    // MARK: - Factory: durationFromMilliseconds

    @Test func testFromMillisecondsConvertsToNanoseconds() {
        let handle = durationFromMilliseconds(5)
        #expect(kk_duration_inWholeNanoseconds(handle) == 5_000_000)
    }

    @Test func testFromMillisecondsRoundTrip() {
        let handle = durationFromMilliseconds(42)
        #expect(durationInWholeMilliseconds(handle) == 42)
    }

    @Test func testFromMillisecondsZero() {
        let handle = durationFromMilliseconds(0)
        #expect(durationInWholeMilliseconds(handle) == 0)
    }

    @Test func testFromMillisecondsNegative() {
        let handle = durationFromMilliseconds(-100)
        #expect(durationInWholeMilliseconds(handle) == -100)
    }

    // MARK: - Factory: durationFromSeconds

    @Test func testFromSecondsConvertsToNanoseconds() {
        let handle = durationFromSeconds(2)
        #expect(kk_duration_inWholeNanoseconds(handle) == 2_000_000_000)
    }

    @Test func testFromSecondsRoundTrip() {
        let handle = durationFromSeconds(7)
        #expect(durationInWholeSeconds(handle) == 7)
    }

    @Test func testFromSecondsZero() {
        let handle = durationFromSeconds(0)
        #expect(durationInWholeSeconds(handle) == 0)
    }

    @Test func testFromSecondsNegative() {
        let handle = durationFromSeconds(-3)
        #expect(durationInWholeSeconds(handle) == -3)
    }

    // MARK: - Factory: durationFromMinutes

    @Test func testFromMinutesConvertsToNanoseconds() {
        let handle = durationFromMinutes(1)
        #expect(kk_duration_inWholeNanoseconds(handle) == 60_000_000_000)
    }

    @Test func testFromMinutesRoundTripSeconds() {
        let handle = durationFromMinutes(2)
        #expect(durationInWholeSeconds(handle) == 120)
    }

    @Test func testFromMinutesZero() {
        let handle = durationFromMinutes(0)
        #expect(kk_duration_inWholeNanoseconds(handle) == 0)
    }

    // MARK: - Factory: durationFromHours

    @Test func testFromHoursConvertsToNanoseconds() {
        let handle = durationFromHours(1)
        let expected = Int(3600) * 1_000_000_000
        #expect(kk_duration_inWholeNanoseconds(handle) == expected)
    }

    @Test func testFromHoursRoundTripSeconds() {
        let handle = durationFromHours(2)
        #expect(durationInWholeSeconds(handle) == 7200)
    }

    @Test func testFromHoursZero() {
        let handle = durationFromHours(0)
        #expect(kk_duration_inWholeNanoseconds(handle) == 0)
    }

    // MARK: - inWholeHours

    @Test func testInWholeHoursFromHoursRoundTrip() {
        let handle = durationFromHours(3)
        #expect(durationInWholeHours(handle) == 3)
    }

    @Test func testInWholeHoursFromMinutes() {
        let handle = durationFromMinutes(150)
        #expect(durationInWholeHours(handle) == 2)
    }

    @Test func testInWholeHoursFromSeconds() {
        let handle = durationFromSeconds(7200)
        #expect(durationInWholeHours(handle) == 2)
    }

    @Test func testInWholeHoursTruncatesSubHour() {
        // 90 minutes = 1.5 hours -> inWholeHours should return 1
        let handle = durationFromMinutes(90)
        #expect(durationInWholeHours(handle) == 1)
    }

    @Test func testInWholeHoursSubHourReturnsZero() {
        let handle = durationFromMinutes(59)
        #expect(durationInWholeHours(handle) == 0)
    }

    @Test func testInWholeHoursZero() {
        let handle = durationFromHours(0)
        #expect(durationInWholeHours(handle) == 0)
    }

    @Test func testInWholeHoursNegative() {
        let handle = durationFromHours(-5)
        #expect(durationInWholeHours(handle) == -5)
    }

    // MARK: - Duration companion constants

    @Test func testDurationZeroAndInfiniteConstants() {
        let zero = kk_duration_zero()
        let infinite = kk_duration_infinite()

        #expect(kk_duration_inWholeNanoseconds(zero) == 0)
        #expect(kk_duration_isInfinite(zero) == 0)
        #expect(kk_duration_isInfinite(infinite) == 1)
    }

    // MARK: - Double receiver factories

    @Test func testDoubleReceiverSecondsConvertsFractionalDuration() {
        let handle = durationFromSecondsDouble(kk_double_to_bits(1.5))
        #expect(durationInWholeMilliseconds(handle) == 1_500)
    }

    @Test func testDoubleReceiverDaysConvertsFractionalDuration() {
        let handle = durationFromDaysDouble(kk_double_to_bits(1.25))
        #expect(durationInWholeHours(handle) == 30)
    }

    // MARK: - Numeric.toDuration(unit)

    @Test func testNumericToDurationUsesDurationUnitOrdinals() {
        let seconds = kk_duration_toDuration_int(2, 3)
        let milliseconds = kk_duration_toDuration_long(1500, 2)
        let minutes = kk_duration_toDuration_double(kk_double_to_bits(1.5), 4)

        #expect(durationInWholeSeconds(seconds) == 2)
        #expect(durationInWholeMilliseconds(milliseconds) == 1500)
        #expect(durationInWholeSeconds(minutes) == 90)
    }

    // MARK: - Duration / Duration -> Double

    @Test func testDurationDivisionReturnsDoubleBits() {
        let lhs = durationFromSeconds(3)
        let rhs = durationFromSeconds(2)
        let resultBits = kk_duration_div_duration(lhs, rhs)
        #expect(kk_bits_to_double(resultBits) == 1.5)
    }

    // MARK: - inWholeDays

    @Test func testInWholeDaysRoundTrip() {
        let handle = durationFromDays(2)
        #expect(durationInWholeDays(handle) == 2)
    }

    // MARK: - Saturation on overflow

    @Test func testFromSecondsLargeValueSaturates() {
        // Int64.max / 1_000_000_000 = 9_223_372_036, so 9_223_372_037 will overflow.
        let handle = durationFromSeconds(9_223_372_037)
        let ns = kk_duration_inWholeNanoseconds(handle)
        // The result must be saturated to Int64.max.
        #expect(ns == Int(Int64.max))
    }

    @Test func testFromMillisecondsLargeNegativeValueSaturates() {
        // Int64.min / 1_000_000 = -9_223_372_036_854, so -9_223_372_036_855 will overflow.
        let handle = durationFromMilliseconds(-9_223_372_036_855)
        let ns = kk_duration_inWholeNanoseconds(handle)
        // The result must be saturated to Int64.min.
        #expect(ns == Int(Int64.min))
    }

    // MARK: - inWholeMicroseconds

    @Test func testInWholeMicrosecondsFromSeconds() {
        let handle = durationFromSeconds(3)
        #expect(durationInWholeMicroseconds(handle) == 3_000_000)
    }

    @Test func testInWholeMicrosecondsFromMilliseconds() {
        let handle = durationFromMilliseconds(2500)
        #expect(durationInWholeMicroseconds(handle) == 2_500_000)
    }

    @Test func testInWholeMicrosecondsRoundTrip() {
        let handle = durationFromMicroseconds(42)
        #expect(durationInWholeMicroseconds(handle) == 42)
    }

    @Test func testInWholeMicrosecondsTruncatesSubMicrosecond() {
        // 1500 ns = 1.5 us -> inWholeMicroseconds should return 1
        let handle = durationFromNanoseconds(1500)
        #expect(durationInWholeMicroseconds(handle) == 1)
    }

    @Test func testInWholeMicrosecondsSubMicrosecondReturnsZero() {
        // 999 ns < 1 us -> inWholeMicroseconds should return 0
        let handle = durationFromNanoseconds(999)
        #expect(durationInWholeMicroseconds(handle) == 0)
    }

    // MARK: - inWholeMilliseconds truncation

    @Test func testInWholeMillisecondsTruncatesSubMillisecond() {
        // 1_500_000 ns = 1.5 ms -> inWholeMilliseconds should return 1
        let handle = durationFromNanoseconds(1_500_000)
        #expect(durationInWholeMilliseconds(handle) == 1)
    }

    @Test func testInWholeMillisecondsSubMillisecondReturnsZero() {
        // 999_999 ns < 1 ms -> inWholeMilliseconds should return 0
        let handle = durationFromNanoseconds(999_999)
        #expect(durationInWholeMilliseconds(handle) == 0)
    }

    // MARK: - inWholeSeconds truncation

    @Test func testInWholeSecondsTruncatesSubSecond() {
        // 1500 ms = 1.5 s -> inWholeSeconds should return 1
        let handle = durationFromMilliseconds(1500)
        #expect(durationInWholeSeconds(handle) == 1)
    }

    @Test func testInWholeSecondsSubSecondReturnsZero() {
        let handle = durationFromMilliseconds(999)
        #expect(durationInWholeSeconds(handle) == 0)
    }

    // MARK: - toString formatting

    @Test func testToStringZeroSeconds() {
        let handle = durationFromNanoseconds(0)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "0s")
    }

    @Test func testToStringWholeSeconds() {
        let handle = durationFromSeconds(5)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "5s")
    }

    @Test func testToStringNegativeWholeSeconds() {
        let handle = durationFromSeconds(-3)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "-3s")
    }

    @Test func testToStringWholeMilliseconds() {
        let handle = durationFromMilliseconds(42)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "42ms")
    }

    @Test func testToStringWholeMicroseconds() {
        let handle = durationFromMicroseconds(7)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "7us")
    }

    @Test func testToStringNanoseconds() {
        let handle = durationFromNanoseconds(123)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "123ns")
    }

    @Test func testToStringOneMinuteRendersAsSeconds() {
        let handle = durationFromMinutes(1)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "1m")
    }

    @Test func testToStringOneHourRendersAsSeconds() {
        let handle = durationFromHours(1)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "1h")
    }

    // MARK: - parse

    @Test func testParseAcceptsIsoAndDefaultFormats() {
        var thrown = 0
        let iso = kk_duration_parse(stringHandle("PT1H30M"), &thrown)
        #expect(thrown == 0)
        #expect(durationInWholeMinutes(iso) == 90)

        let defaultFormat = kk_duration_parse(stringHandle("1h 30m"), &thrown)
        #expect(thrown == 0)
        #expect(durationInWholeMinutes(defaultFormat) == 90)
    }

    @Test func testParseAcceptsSingleUnitDecimalFormat() {
        var thrown = 0
        let parsed = kk_duration_parse(stringHandle("1.5h"), &thrown)
        #expect(thrown == 0)
        #expect(durationInWholeMinutes(parsed) == 90)
    }

    @Test func testParseInvalidStringSetsThrownChannel() {
        var thrown = 0
        let parsed = kk_duration_parse(stringHandle("1 hour 30 minutes"), &thrown)
        #expect(parsed == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }

    @Test func testParseOrNullReturnsDurationOrNullSentinel() {
        let valid = kk_duration_parseOrNull(stringHandle("PT0.120300S"))
        #expect(durationInWholeMicroseconds(valid) == 120_300)

        let invalid = kk_duration_parseOrNull(stringHandle("1 hour 30 minutes"))
        #expect(invalid == runtimeNullSentinelInt)
    }

    @Test func testParseIsoStringRejectsDefaultFormat() {
        var thrown = 0
        let parsed = kk_duration_parseIsoString(stringHandle("1h 30m"), &thrown)
        #expect(parsed == runtimeNullSentinelInt)
        #expect(thrown != 0)
    }

    @Test func testParseIsoStringOrNullAcceptsOnlyIsoFormat() {
        let valid = kk_duration_parseIsoStringOrNull(stringHandle("P1DT2H3M4.005S"))
        #expect(durationInWholeSeconds(valid) == 93_784)

        let invalid = kk_duration_parseIsoStringOrNull(stringHandle("1h 30m"))
        #expect(invalid == runtimeNullSentinelInt)
    }

    // MARK: - Multiple independent durations

    @Test func testMultipleDurationsAreIndependent() {
        let h1 = durationFromSeconds(10)
        let h2 = durationFromMilliseconds(500)
        #expect(durationInWholeSeconds(h1) == 10)
        #expect(durationInWholeMilliseconds(h2) == 500)
    }

    // MARK: - RuntimeDurationBox accessor chain

    @Test func testDurationBoxAccessorChainEndToEnd() {
        // Verify the direct RuntimeDurationBox path by constructing one
        // manually and confirming the accessor chain works end-to-end.
        let box = RuntimeDurationBox(nanoseconds: 42_000_000)
        let handle = registerRuntimeObject(box)
        #expect(durationInWholeMilliseconds(handle) == 42)
        #expect(durationInWholeSeconds(handle) == 0)
        #expect(kk_duration_inWholeNanoseconds(handle) == 42_000_000)
    }

    @Test func testDurationBoxLargeValueDoesNotCrash() {
        // Verify that a box with Int64.max nanoseconds does not crash accessors.
        let box = RuntimeDurationBox(nanoseconds: Int64.max)
        let handle = registerRuntimeObject(box)
        let ms = durationInWholeMilliseconds(handle)
        let s = durationInWholeSeconds(handle)
        #expect(ms > 0)
        #expect(s > 0)
    }

    // MARK: - inWholeMinutes

    @Test func testInWholeMinutesFromMinutesRoundTrip() {
        let handle = durationFromMinutes(5)
        #expect(durationInWholeMinutes(handle) == 5)
    }

    @Test func testInWholeMinutesTruncatesSubMinute() {
        // 90 seconds = 1.5 minutes -> inWholeMinutes should return 1
        let handle = durationFromSeconds(90)
        #expect(durationInWholeMinutes(handle) == 1)
    }

    @Test func testInWholeMinutesSubMinuteReturnsZero() {
        let handle = durationFromSeconds(59)
        #expect(durationInWholeMinutes(handle) == 0)
    }

    @Test func testInWholeMinutesFromHours() {
        let handle = durationFromHours(2)
        #expect(durationInWholeMinutes(handle) == 120)
    }

    @Test func testInWholeMinutesNegative() {
        let handle = durationFromMinutes(-3)
        #expect(durationInWholeMinutes(handle) == -3)
    }

    // MARK: - Saturation edge cases

    @Test func testFromMicrosecondsLargePositiveSaturates() {
        // Int64.max / 1_000 overflows, should saturate
        let handle = durationFromMicroseconds(Int(Int64.max / 999))
        let ns = kk_duration_inWholeNanoseconds(handle)
        #expect(ns == Int(Int64.max))
    }

    @Test func testFromMinutesLargePositiveSaturates() {
        // Very large minutes value should saturate
        let handle = durationFromMinutes(Int(Int64.max / 1_000_000_000))
        let ns = kk_duration_inWholeNanoseconds(handle)
        #expect(ns == Int(Int64.max))
    }

    @Test func testFromHoursLargePositiveSaturates() {
        // Very large hours value should saturate
        let handle = durationFromHours(Int(Int64.max / 1_000_000_000))
        let ns = kk_duration_inWholeNanoseconds(handle)
        #expect(ns == Int(Int64.max))
    }

    // MARK: - toString edge cases

    @Test func testToStringSubMicrosecondRendersAsNanoseconds() {
        let handle = durationFromNanoseconds(1_500)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "1.5us")
    }

    @Test func testToStringExactlyOneMicrosecond() {
        let handle = durationFromMicroseconds(1)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "1us")
    }

    @Test func testToStringExactlyOneNanosecond() {
        let handle = durationFromNanoseconds(1)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "1ns")
    }

    @Test func testToStringNegativeMilliseconds() {
        let handle = durationFromMilliseconds(-7)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "-7ms")
    }

    @Test func testToStringNegativeNanoseconds() {
        let handle = durationFromNanoseconds(-123)
        let result = kk_duration_toString(handle)
        #expect(stringFromHandle(result) == "-123ns")
    }

    // MARK: - toString multi-component formatting (JVM kotlin-stdlib parity)
    // Expected values were captured by compiling and running the equivalent
    // Kotlin snippets against JVM kotlinc 2.4.0 (kotlin-stdlib Duration.toString()).

    @Test func testToStringCombinesMinutesAndSeconds() {
        // 90 seconds -> "1m 30s"
        let handle = durationFromSeconds(90)
        #expect(stringFromHandle(kk_duration_toString(handle)) == "1m 30s")
    }

    @Test func testToStringCombinesHoursAndMinutes() {
        let handle = kk_duration_plus(durationFromHours(2), durationFromMinutes(5))
        #expect(stringFromHandle(kk_duration_toString(handle)) == "2h 5m")
    }

    @Test func testToStringSecondsComponentCarriesSubsecondFraction() {
        // 1h + 30m + 340ms -> seconds component is 0 but nanoseconds carry the fraction: "1h 30m 0.34s"
        let handle = kk_duration_plus(
            kk_duration_plus(durationFromHours(1), durationFromMinutes(30)),
            durationFromMilliseconds(340)
        )
        #expect(stringFromHandle(kk_duration_toString(handle)) == "1h 30m 0.34s")
    }

    @Test func testToStringRollsUpDaysPastTwentyFourHours() {
        // 25 hours -> "1d 1h"
        let handle = durationFromHours(25)
        #expect(stringFromHandle(kk_duration_toString(handle)) == "1d 1h")
    }

    @Test func testToStringKeepsIntermediateZeroComponent() {
        // 1 day + 5 minutes -> hours stays visible between nonzero days and minutes: "1d 0h 5m"
        let handle = kk_duration_plus(durationFromDays(1), durationFromMinutes(5))
        #expect(stringFromHandle(kk_duration_toString(handle)) == "1d 0h 5m")
    }

    @Test func testToStringNegativeMultiComponentIsParenthesized() {
        let handle = kk_duration_unary_minus(
            kk_duration_plus(durationFromHours(1), durationFromMinutes(30))
        )
        #expect(stringFromHandle(kk_duration_toString(handle)) == "-(1h 30m)")
    }

    @Test func testToStringInfiniteDuration() {
        #expect(stringFromHandle(kk_duration_toString(kk_duration_infinite())) == "Infinity")
    }

    @Test func testToStringNegativeInfiniteDuration() {
        let negInfinite = kk_duration_unary_minus(kk_duration_infinite())
        #expect(stringFromHandle(kk_duration_toString(negInfinite)) == "-Infinity")
    }

    @Test func testToStringFractionalSecondsPadsToNineDigits() {
        // 1s + 4500ns -> 7 significant fractional digits round up to 9: "1.000004500s"
        let handle = kk_duration_plus(durationFromSeconds(1), durationFromNanoseconds(4_500))
        #expect(stringFromHandle(kk_duration_toString(handle)) == "1.000004500s")
    }

    @Test func testToStringFractionalSecondsPadsToSixDigits() {
        // 1s + 500_000ns -> 4 significant fractional digits round up to 6: "1.000500s"
        let handle = kk_duration_plus(durationFromSeconds(1), durationFromNanoseconds(500_000))
        #expect(stringFromHandle(kk_duration_toString(handle)) == "1.000500s")
    }

    @Test func testToStringFractionalSecondsKeepsTwoDigitsAsIs() {
        // 30s + 340ms -> 2 significant fractional digits stay untrimmed: "30.34s"
        let handle = kk_duration_plus(durationFromSeconds(30), durationFromMilliseconds(340))
        #expect(stringFromHandle(kk_duration_toString(handle)) == "30.34s")
    }

    // MARK: - kk_measureTime: basic timing

    @Test func testMeasureTimeReturnsNonZeroDuration() {
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        #expect(thrown == 0, "No exception should be thrown")
        #expect(result != 0, "Should return a valid duration handle")
        // Even a no-op should take >= 0 nanoseconds
        let ns = kk_duration_inWholeNanoseconds(result)
        #expect(ns >= 0)
    }

    @Test func testMeasureTimeElapsedIsPlausible() {
        // A 50ms sleep should produce a duration roughly in [40ms, 500ms]
        let fnPtr = unsafeBitCast(sleep50msThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        let ms = durationInWholeMilliseconds(result)
        #expect(ms >= 40, "Should be at least ~40ms")
        #expect(ms < 500, "Should not exceed 500ms")
    }

    @Test func testMeasureTimeNoopIsFast() {
        // A no-op closure should complete in well under 100ms
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        #expect(thrown == 0)
        let ms = durationInWholeMilliseconds(result)
        #expect(ms < 100, "No-op should complete in < 100ms")
    }

    // MARK: - kk_measureTime: exception propagation

    @Test func testMeasureTimeReturnsZeroOnException() {
        let fnPtr = unsafeBitCast(throwingThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        #expect(thrown != 0, "Exception sentinel should be propagated")
        #expect(thrown == 0xDEAD, "Should propagate the exact exception value")
        #expect(result == 0, "Duration handle should be 0 on exception")
    }

    @Test func testMeasureTimeOutThrownInitializedToZero() {
        // Verify outThrown is cleared before invocation
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0xBEEF // pre-fill with garbage
        let result = kk_measureTime(fnPtr, 0, &thrown)
        #expect(thrown == 0, "outThrown should be reset to 0 for non-throwing closure")
        #expect(result != 0)
    }

    // MARK: - kk_measureTime: closureRaw passthrough

    @Test func testMeasureTimePassesClosureRawToThunk() {
        // The captureClosureRawThunk stores its closureRaw argument into a global.
        // We verify kk_measureTime forwards the closureRaw value correctly.
        capturedClosureRaw = 0
        let fnPtr = unsafeBitCast(captureClosureRawThunk, to: Int.self)
        var thrown: Int = 0
        let sentinel = 42
        let result = kk_measureTime(fnPtr, sentinel, &thrown)
        #expect(thrown == 0)
        #expect(capturedClosureRaw == sentinel, "closureRaw should be forwarded to the thunk")
        // The duration should still be valid (non-zero handle)
        #expect(result != 0)
        let ns = kk_duration_inWholeNanoseconds(result)
        #expect(ns >= 0)
    }

    // MARK: - kk_measureTime: nullable outThrown

    @Test func testMeasureTimeNilOutThrownDoesNotCrash() {
        // kk_measureTime accepts a nullable outThrown pointer.
        // Passing nil should not crash even for a non-throwing closure.
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        let result = kk_measureTime(fnPtr, 0, nil)
        #expect(result != 0)
        let ns = kk_duration_inWholeNanoseconds(result)
        #expect(ns >= 0)
    }

    // MARK: - kk_measureTime: result is a proper Duration

    @Test func testMeasureTimeResultWorksWithDurationAccessors() {
        // Verify the returned handle is a valid RuntimeDurationBox
        // that works with all duration accessor functions.
        let fnPtr = unsafeBitCast(sleep50msThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        #expect(thrown == 0)

        // All accessors should work without crashing
        let ns = kk_duration_inWholeNanoseconds(result)
        let ms = durationInWholeMilliseconds(result)
        let s = durationInWholeSeconds(result)
        let min = durationInWholeMinutes(result)

        #expect(ns > 0)
        #expect(ms >= 40)
        #expect(s >= 0)
        #expect(min >= 0)
    }

    @Test func testMeasureTimeResultWorksWithToString() throws {
        // The toString of a measured duration should produce a non-empty string
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)
        #expect(thrown == 0)

        let strHandle = kk_duration_toString(result)
        let str = try #require(
            stringFromHandle(strHandle),
            "toString returned nil for a valid duration handle"
        )
        // The string should end with a time unit suffix.
        // Check longest suffixes first to avoid "s" matching "ns"/"us"/"ms".
        let validSuffixes = ["ns", "us", "ms", "s"]
        let hasValidSuffix = validSuffixes.contains { str.hasSuffix($0) }
        #expect(hasValidSuffix, "toString should end with a time unit suffix, got: \(str)")
    }

    // MARK: - kk_measureTime: consecutive calls

    @Test func testMeasureTimeConsecutiveCallsProduceIndependentDurations() {
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown1: Int = 0
        var thrown2: Int = 0
        let result1 = kk_measureTime(fnPtr, 0, &thrown1)
        let result2 = kk_measureTime(fnPtr, 0, &thrown2)
        #expect(thrown1 == 0)
        #expect(thrown2 == 0)
        // Both should be valid, independent duration handles
        #expect(result1 != 0)
        #expect(result2 != 0)
        // They should be distinct handles (different allocations)
        #expect(result1 != result2)
    }

    // MARK: - kk_measureTime: advanced testing (TEST-001)

    @Test func testMeasureTimeParallelExecutionIndependence() {
        // Test that concurrent measurements don't interfere with each other
        let resultsBox = DurationResultsBox()
        let group = DispatchGroup()

        for i in 0..<4 {
            group.enter()
            DispatchQueue.global(qos: .userInitiated).async {
                let fnPtr = unsafeBitCast(sleep50msThunk, to: Int.self)
                var thrown: Int = 0
                let result = kk_measureTime(fnPtr, i, &thrown)
                let thrownValue = thrown

                #expect(thrownValue == 0, "Thread \(i): No exception should be thrown")
                #expect(result != 0, "Thread \(i): Should return valid duration")
                resultsBox.append(result)
                group.leave()
            }
        }

        #expect(group.wait(timeout: .now() + 2.0) == .success, "Parallel measurements should complete")
        let results = resultsBox.snapshot()
        #expect(results.count == 4, "All 4 parallel measurements should complete")

        // Verify all results are distinct handles
        let uniqueResults = Set(results)
        #expect(uniqueResults.count == 4, "All parallel measurements should produce distinct handles")

        // Verify all measurements are in reasonable range
        for result in results {
            let ms = durationInWholeMilliseconds(result)
            #expect(ms >= 40, "Parallel measurement should be at least ~40ms")
            #expect(ms < 500, "Parallel measurement should not exceed 500ms")
        }
    }

    @Test func testMeasureTimeHighPrecisionTiming() {
        // Test sub-millisecond precision capabilities
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0

        // Run multiple measurements to check precision
        var measurements: [Int64] = []
        for _ in 0..<10 {
            let result = kk_measureTime(fnPtr, 0, &thrown)
            #expect(thrown == 0)
            let ns = kk_duration_inWholeNanoseconds(result)
            measurements.append(Int64(ns))
        }

        // Even no-ops should show some variation in nanosecond precision
        let uniqueValues = Set(measurements)
        #expect(uniqueValues.count > 1, "Multiple measurements should show timing variation")

        // All measurements should be reasonable (not negative, not excessively large)
        for ns in measurements {
            #expect(ns >= 0, "Nanosecond measurement should not be negative")
            #expect(ns < 1_000_000, "No-op should complete within 1ms")
        }
    }

    @Test func testMeasureTimeComplexExceptionScenarios() {
        // Test nested exception scenarios and exception preservation

        // First test: exception with closureRaw value
        let fnPtr = unsafeBitCast(throwingThunk, to: Int.self)
        var thrown: Int = 0
        let sentinel = 0xBEEF
        let result = kk_measureTime(fnPtr, sentinel, &thrown)

        #expect(thrown == 0xDEAD, "Exception should be preserved regardless of closureRaw")
        #expect(result == 0, "Duration should be zero on exception")

        // Second test: verify outThrown is properly reset after exception
        var thrown2: Int = 0xDEAD // Pre-fill with garbage
        let result2 = kk_measureTime(fnPtr, sentinel, &thrown2)
        #expect(thrown2 == 0xDEAD, "Exception should overwrite pre-filled value")
        #expect(result2 == 0, "Duration should be zero on second exception")

        // Third test: verify normal operation after exception
        var thrown3: Int = 0xDEAD // Pre-fill with garbage
        let noopPtr = unsafeBitCast(noopThunk, to: Int.self)
        let result3 = kk_measureTime(noopPtr, sentinel, &thrown3)
        #expect(thrown3 == 0, "Normal operation should reset outThrown to zero")
        #expect(result3 != 0, "Normal operation should return valid duration")
    }

    @Test func testMeasureTimeLongDurationOverflowHandling() {
        // Test behavior with very long durations that might approach Int64 limits
        let longSleepThunk: @convention(c) (Int, UnsafeMutablePointer<Int>?) -> Int = { _, _ in
            // Sleep for 2 seconds to create a substantial duration
            Thread.sleep(forTimeInterval: 2.0)
            return 0
        }

        let fnPtr = unsafeBitCast(longSleepThunk, to: Int.self)
        var thrown: Int = 0
        let result = kk_measureTime(fnPtr, 0, &thrown)

        #expect(thrown == 0, "Long sleep should not throw exception")
        #expect(result != 0, "Long duration should return valid handle")

        let ns = kk_duration_inWholeNanoseconds(result)
        #expect(ns > 1_000_000_000, "Should be at least 1 second")
        #expect(ns < Int(Int64.max), "Should not overflow Int64")

        // Verify the duration can be safely used with all accessors
        let ms = durationInWholeMilliseconds(result)
        let s = durationInWholeSeconds(result)
        #expect(ms > 1000, "Milliseconds should be > 1000")
        #expect(s >= 2, "Seconds should be >= 2")
    }

    @Test func testMeasureTimeSystemClockStability() {
        // Test measurement stability under rapid successive calls
        let fnPtr = unsafeBitCast(noopThunk, to: Int.self)
        var thrown: Int = 0

        var durations: [Int64] = []
        let startTime = DispatchTime.now().uptimeNanoseconds

        // Perform rapid measurements
        for i in 0..<50 {
            let result = kk_measureTime(fnPtr, i, &thrown)
            #expect(thrown == 0, "Measurement \(i) should not throw")
            let ns = kk_duration_inWholeNanoseconds(result)
            durations.append(Int64(ns))
        }

        let endTime = DispatchTime.now().uptimeNanoseconds
        let totalTestTime = endTime - startTime

        // These are independent duration samples, not timestamps. Validate that
        // the aggregate measured time stays within the enclosing wall-clock time
        // with a small allowance for clock sampling overhead.
        let measuredTotal = durations.reduce(0, +)
        let aggregateSlackNs: Int64 = 20_000_000
        #expect((durations.min() ?? -1) >= 0, "Measured durations should never be negative")
        #expect(
            measuredTotal <= Int64(totalTestTime) + aggregateSlackNs,
            "Aggregate measured durations should stay close to enclosing wall-clock time"
        )

        // Verify total test time is reasonable
        #expect(totalTestTime < 10_000_000_000, "50 rapid measurements should complete within 10 seconds")
    }

    // MARK: - Long factory: durationFromDaysLong (TEST-TIME-020)

    @Test func testDurationFromDaysLongNormalValues() {
        #expect(durationInWholeDays(durationFromDaysLong(5)) == 5)
        #expect(durationInWholeDays(durationFromDaysLong(0)) == 0)
        #expect(durationInWholeDays(durationFromDaysLong(-3)) == -3)
    }

    // MARK: - Long factory: durationFromHoursLong (TEST-TIME-020)

    @Test func testDurationFromHoursLongNormalValues() {
        #expect(durationInWholeHours(durationFromHoursLong(5)) == 5)
        #expect(durationInWholeHours(durationFromHoursLong(0)) == 0)
        #expect(durationInWholeHours(durationFromHoursLong(-2)) == -2)
    }

    // MARK: - Long factory: durationFromMinutesLong (TEST-TIME-020)

    @Test func testDurationFromMinutesLongNormalValues() {
        #expect(durationInWholeMinutes(durationFromMinutesLong(5)) == 5)
        #expect(durationInWholeMinutes(durationFromMinutesLong(0)) == 0)
        #expect(durationInWholeMinutes(durationFromMinutesLong(-10)) == -10)
    }

    // MARK: - Long factory: durationFromMicrosecondsLong (TEST-TIME-020)

    @Test func testDurationFromMicrosecondsLongNormalValues() {
        #expect(durationInWholeMicroseconds(durationFromMicrosecondsLong(5)) == 5)
        #expect(durationInWholeMicroseconds(durationFromMicrosecondsLong(0)) == 0)
        #expect(durationInWholeMicroseconds(durationFromMicrosecondsLong(-100)) == -100)
    }

    // MARK: - Long.MAX_VALUE saturation (TEST-TIME-020)

    @Test func testDurationLongMaxValueSaturatesToInfinite() {
        // Long.MAX_VALUE = Int64.max; all factories with a multiplier > 1 overflow to INFINITE
        let longMax = Int(Int64.max)
        #expect(kk_duration_isInfinite(durationFromDaysLong(longMax)) == 1)
        #expect(kk_duration_isInfinite(durationFromHoursLong(longMax)) == 1)
        #expect(kk_duration_isInfinite(durationFromMinutesLong(longMax)) == 1)
        #expect(kk_duration_isInfinite(durationFromMicrosecondsLong(longMax)) == 1)
    }
}
