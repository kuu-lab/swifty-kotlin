import Dispatch
import Foundation

// MARK: - kotlin.time experimental time runtime (STDLIB-TIME-180)
// MARK: - Platform time conversion runtime (STDLIB-TIME-181)

final class RuntimeJavaInstantBox {
    let epochSeconds: Int64
    let nanoOfSecond: Int32

    init(epochSeconds: Int64, nanoOfSecond: Int32) {
        self.epochSeconds = epochSeconds
        self.nanoOfSecond = nanoOfSecond
    }
}

final class RuntimeJavaDurationBox {
    let seconds: Int64
    let nanoAdjustment: Int32

    init(seconds: Int64, nanoAdjustment: Int32) {
        self.seconds = seconds
        self.nanoAdjustment = nanoAdjustment
    }
}

final class RuntimeJSDateBox {
    let epochMilliseconds: Double

    init(epochMilliseconds: Double) {
        self.epochMilliseconds = epochMilliseconds
    }
}

final class RuntimeTimeMarkBox {
    let uptimeNanoseconds: Int64

    init(uptimeNanoseconds: Int64) {
        self.uptimeNanoseconds = uptimeNanoseconds
    }
}

final class RuntimeTestTimeSourceBox {
    var nanoseconds: Int64 = 0
}

private func runtimeKotlinInstantBox(from raw: Int) -> RuntimeInstantBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInstantBox.self)
}

private func runtimeKotlinDurationBox(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

private func runtimeJSDateBox(from raw: Int) -> RuntimeJSDateBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJSDateBox.self)
}

private func runtimeTimeMarkBox(from raw: Int) -> RuntimeTimeMarkBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeTimeMarkBox.self)
}

private func runtimeTestTimeSourceBox(from raw: Int) -> RuntimeTestTimeSourceBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeTestTimeSourceBox.self)
}

private func runtimeDurationBoxForTime(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

private func runtimeEpochMilliseconds(
    epochSeconds: Int64,
    nanoOfSecond: Int32
) -> Double {
    Double(epochSeconds) * 1_000 + Double(nanoOfSecond) / 1_000_000
}

private func runtimeInstantFromEpochMilliseconds(_ epochMilliseconds: Double) -> RuntimeInstantBox {
    if !epochMilliseconds.isFinite {
        let sentinelSeconds: Int64 = epochMilliseconds.sign == .minus ? Int64.min : Int64.max
        return RuntimeInstantBox(epochSeconds: sentinelSeconds, nanoOfSecond: 0)
    }

    let totalSeconds = floor(epochMilliseconds / 1_000)
    let remainingMilliseconds = epochMilliseconds - (totalSeconds * 1_000)
    let nanos = Int32(remainingMilliseconds * 1_000_000)
    let clampedSeconds = totalSeconds < Double(Int64.min)
        ? Int64.min
        : (totalSeconds > Double(Int64.max) ? Int64.max : Int64(totalSeconds))
    return RuntimeInstantBox(epochSeconds: clampedSeconds, nanoOfSecond: nanos)
}

private func runtimeJavaDurationComponents(from nanoseconds: Int64) -> (seconds: Int64, nanoAdjustment: Int32) {
    // Use floor division so that nanoAdjustment is always in [0, 999_999_999].
    // For positive values, truncation == floor; for negative values we adjust.
    let seconds: Int64
    if nanoseconds >= 0 {
        seconds = nanoseconds / 1_000_000_000
    } else {
        // Guard against Int64.min overflow before subtracting 999_999_999.
        let (adjusted, overflow) = nanoseconds.subtractingReportingOverflow(999_999_999)
        seconds = overflow ? Int64.min / 1_000_000_000 : adjusted / 1_000_000_000
    }
    let nanoAdjustment = Int32(nanoseconds - seconds * 1_000_000_000)
    return (seconds, nanoAdjustment)
}

private func runtimeSaturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow {
        return rhs < 0 ? Int64.min : Int64.max
    }
    return result
}

private func runtimeMonotonicNowNanoseconds() -> Int64 {
    let now = DispatchTime.now().uptimeNanoseconds
    return now <= UInt64(Int64.max) ? Int64(now) : Int64.max
}

private func runtimeNegSaturating(_ value: Int64) -> Int64 {
    value == Int64.min ? Int64.max : -value
}

private func runtimeTimeMarkElapsedNanoseconds(_ mark: RuntimeTimeMarkBox) -> Int64 {
    runtimeSaturatingAdd(runtimeMonotonicNowNanoseconds(), runtimeNegSaturating(mark.uptimeNanoseconds))
}

private func runtimeDurationHandle(fromNanoseconds nanoseconds: Int64) -> Int {
    registerRuntimeObject(RuntimeDurationBox(nanoseconds: nanoseconds))
}

@_cdecl("kk_instant_to_java_instant")
public func kk_instant_to_java_instant(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_java_instant received invalid Instant handle")
    }
    return registerRuntimeObject(
        RuntimeJavaInstantBox(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond)
    )
}

@_cdecl("kk_duration_to_java_duration")
public func kk_duration_to_java_duration(_ durationRaw: Int) -> Int {
    guard let duration = runtimeKotlinDurationBox(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_to_java_duration received invalid Duration handle")
    }
    let components = runtimeJavaDurationComponents(from: duration.nanoseconds)
    return registerRuntimeObject(
        RuntimeJavaDurationBox(seconds: components.seconds, nanoAdjustment: components.nanoAdjustment)
    )
}

@_cdecl("kk_instant_to_js_date")
public func kk_instant_to_js_date(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_js_date received invalid Instant handle")
    }
    return registerRuntimeObject(
        RuntimeJSDateBox(epochMilliseconds: runtimeEpochMilliseconds(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond))
    )
}

/// Maps a java.util.concurrent.TimeUnit ordinal to the matching kotlin.time.DurationUnit ordinal.
///
/// Kotlin/JVM: timeUnit.toDurationUnit()
///
/// Both enums share identical entry ordering
/// (0=NANOSECONDS, 1=MICROSECONDS, 2=MILLISECONDS, 3=SECONDS, 4=MINUTES, 5=HOURS, 6=DAYS),
/// so the conversion is a 1:1 ordinal mapping. The explicit switch mirrors Kotlin's
/// exhaustive `when` and traps any out-of-range ordinal (compiler/runtime enum mismatch).
@_cdecl("kk_time_unit_to_duration_unit")
public func kk_time_unit_to_duration_unit(_ timeUnitOrdinal: Int) -> Int {
    switch timeUnitOrdinal {
    case 0: return 0 // NANOSECONDS
    case 1: return 1 // MICROSECONDS
    case 2: return 2 // MILLISECONDS
    case 3: return 3 // SECONDS
    case 4: return 4 // MINUTES
    case 5: return 5 // HOURS
    case 6: return 6 // DAYS
    default:
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_unit_to_duration_unit received unknown TimeUnit ordinal \(timeUnitOrdinal)")
    }
}

// MARK: - DurationUnit <-> TimeUnit conversion (STDLIB-TIME-FN-012)

/// Bridges `kotlin.time.DurationUnit.toTimeUnit()` to
/// `java.util.concurrent.TimeUnit`. Both enums share identical entry order
/// (NANOSECONDS=0, MICROSECONDS=1, MILLISECONDS=2, SECONDS=3, MINUTES=4,
/// HOURS=5, DAYS=6), so the conversion is an ordinal identity. The incoming
/// `unitOrdinal` is a DurationUnit ordinal lowered to a raw machine word; the
/// returned value is the matching TimeUnit ordinal.
@_cdecl("kk_duration_unit_to_time_unit")
public func kk_duration_unit_to_time_unit(_ unitOrdinal: Int) -> Int {
    guard (0...6).contains(unitOrdinal) else {
        assertionFailure("KSwiftK: unknown DurationUnit ordinal \(unitOrdinal) – compiler/runtime enum mismatch?")
        return unitOrdinal
    }
    return unitOrdinal
}

@_cdecl("kk_time_source_mark_now")
public func kk_time_source_mark_now(_ receiver: Int) -> Int {
    let mark = RuntimeTimeMarkBox(uptimeNanoseconds: runtimeMonotonicNowNanoseconds())
    return registerRuntimeObject(mark)
}

@_cdecl("kk_time_source_monotonic_mark_now")
public func kk_time_source_monotonic_mark_now(_ receiver: Int) -> Int {
    kk_time_source_mark_now(receiver)
}

@_cdecl("kk_time_source_as_clock")
public func kk_time_source_as_clock(_ sourceRaw: Int, _ originRaw: Int) -> Int {
    guard let origin = runtimeKotlinInstantBox(from: originRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_source_as_clock received invalid Instant handle")
    }
    return registerRuntimeObject(RuntimeTimeSourceClockBox(
        origin: origin,
        baseUptimeNanoseconds: runtimeMonotonicNowNanoseconds()
    ))
}

@_cdecl("kk_time_mark_elapsed_now")
public func kk_time_mark_elapsed_now(_ markRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_elapsed_now received invalid TimeMark handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeTimeMarkElapsedNanoseconds(mark))
}

@_cdecl("kk_time_mark_has_passed_now")
public func kk_time_mark_has_passed_now(_ markRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_has_passed_now received invalid TimeMark handle")
    }
    return runtimeTimeMarkElapsedNanoseconds(mark) >= 0 ? 1 : 0
}

@_cdecl("kk_time_mark_has_not_passed_now")
public func kk_time_mark_has_not_passed_now(_ markRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_has_not_passed_now received invalid TimeMark handle")
    }
    return runtimeTimeMarkElapsedNanoseconds(mark) < 0 ? 1 : 0
}

@_cdecl("kk_time_mark_plus_duration")
public func kk_time_mark_plus_duration(_ markRaw: Int, _ durationRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw),
          let duration = runtimeDurationBoxForTime(from: durationRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_plus_duration received invalid handle")
    }
    let shifted = RuntimeTimeMarkBox(
        uptimeNanoseconds: runtimeSaturatingAdd(mark.uptimeNanoseconds, duration.nanoseconds)
    )
    return registerRuntimeObject(shifted)
}

@_cdecl("kk_time_mark_minus_duration")
public func kk_time_mark_minus_duration(_ markRaw: Int, _ durationRaw: Int) -> Int {
    guard let mark = runtimeTimeMarkBox(from: markRaw),
          let duration = runtimeDurationBoxForTime(from: durationRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_minus_duration received invalid handle")
    }
    let shifted = RuntimeTimeMarkBox(
        uptimeNanoseconds: runtimeSaturatingAdd(mark.uptimeNanoseconds, runtimeNegSaturating(duration.nanoseconds))
    )
    return registerRuntimeObject(shifted)
}

@_cdecl("kk_time_mark_minus_mark")
public func kk_time_mark_minus_mark(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeTimeMarkBox(from: lhsRaw),
          let rhs = runtimeTimeMarkBox(from: rhsRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_minus_mark received invalid TimeMark handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeSaturatingAdd(lhs.uptimeNanoseconds, runtimeNegSaturating(rhs.uptimeNanoseconds)))
}

@_cdecl("kk_time_mark_compare")
public func kk_time_mark_compare(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeTimeMarkBox(from: lhsRaw),
          let rhs = runtimeTimeMarkBox(from: rhsRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_time_mark_compare received invalid TimeMark handle")
    }
    if lhs.uptimeNanoseconds < rhs.uptimeNanoseconds { return -1 }
    if lhs.uptimeNanoseconds > rhs.uptimeNanoseconds { return 1 }
    return 0
}

// MARK: - TestTimeSource runtime (STDLIB-TIME-TYPE-009)

@_cdecl("kk_test_time_source_new")
public func kk_test_time_source_new() -> Int {
    return registerRuntimeObject(RuntimeTestTimeSourceBox())
}

@_cdecl("kk_test_time_source_plus_assign")
public func kk_test_time_source_plus_assign(_ sourceRaw: Int, _ durationRaw: Int) -> Int {
    guard let source = runtimeTestTimeSourceBox(from: sourceRaw),
          let duration = runtimeDurationBoxForTime(from: durationRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_test_time_source_plus_assign received invalid handle")
    }
    source.nanoseconds = runtimeSaturatingAdd(source.nanoseconds, duration.nanoseconds)
    return 0
}

@_cdecl("kk_test_time_source_mark_now")
public func kk_test_time_source_mark_now(_ sourceRaw: Int) -> Int {
    guard let source = runtimeTestTimeSourceBox(from: sourceRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_test_time_source_mark_now received invalid TestTimeSource handle")
    }
    return registerRuntimeObject(RuntimeTimeMarkBox(uptimeNanoseconds: source.nanoseconds))
}

@_cdecl("kk_test_time_source_read")
public func kk_test_time_source_read(_ sourceRaw: Int) -> Int {
    guard let source = runtimeTestTimeSourceBox(from: sourceRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_test_time_source_read received invalid TestTimeSource handle")
    }
    return Int(source.nanoseconds)
}

// MARK: - Native: Foundation Date bridge (STDLIB-TIME-181)

/// Converts a kotlin.time.Instant to a Foundation.Date (Native/macOS bridge).
///
/// Kotlin/Native: instant.toNSDate()
@_cdecl("kk_instant_to_foundation_date")
public func kk_instant_to_foundation_date(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_foundation_date received invalid Instant handle")
    }
    let timeInterval = Double(instant.epochSeconds) + Double(instant.nanoOfSecond) / 1_000_000_000
    // Represent Foundation.Date as epoch milliseconds in a JS-style box for interop.
    return registerRuntimeObject(RuntimeJSDateBox(epochMilliseconds: timeInterval * 1_000))
}

/// Converts a Foundation.Date (represented as epoch-millisecond JS box) to a kotlin.time.Instant.
///
/// Kotlin/Native: nsDate.toKotlinInstant()
@_cdecl("kk_foundation_date_to_kotlin_instant")
public func kk_foundation_date_to_kotlin_instant(_ dateRaw: Int) -> Int {
    guard let jsDate = runtimeJSDateBox(from: dateRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_foundation_date_to_kotlin_instant received invalid NSDate handle")
    }
    return registerRuntimeObject(runtimeInstantFromEpochMilliseconds(jsDate.epochMilliseconds))
}

// MARK: - Native: clock_gettime bridge (STDLIB-TIME-181)

/// Returns monotonic time in nanoseconds using POSIX clock_gettime(CLOCK_MONOTONIC).
///
/// Kotlin/Native: TimeSource.Monotonic.markNow() lower-level primitive.
@_cdecl("kk_clock_gettime_monotonic_ns")
public func kk_clock_gettime_monotonic_ns() -> Int {
    var ts = timespec()
    clock_gettime(CLOCK_MONOTONIC, &ts)
    let ns = runtimeSaturatingAdd(
        saturatingMultiply(Int64(ts.tv_sec), 1_000_000_000),
        Int64(ts.tv_nsec)
    )
    // Clamp to Int range (platform word size).
    if ns > Int64(Int.max) { return Int.max }
    if ns < Int64(Int.min) { return Int.min }
    return Int(ns)
}

/// Returns a TimeMark backed by POSIX CLOCK_MONOTONIC instead of DispatchTime.
///
/// Kotlin/Native: TimeSource.Monotonic.markNow() (native clock variant)
@_cdecl("kk_clock_monotonic_mark_now")
public func kk_clock_monotonic_mark_now() -> Int {
    var ts = timespec()
    clock_gettime(CLOCK_MONOTONIC, &ts)
    let ns = runtimeSaturatingAdd(
        saturatingMultiply(Int64(ts.tv_sec), 1_000_000_000),
        Int64(ts.tv_nsec)
    )
    return registerRuntimeObject(RuntimeTimeMarkBox(uptimeNanoseconds: ns))
}

// MARK: - Type-safe epoch conversion helpers (STDLIB-TIME-181)

/// Returns the epoch-millisecond representation of a kotlin.time.Instant as a Long.
///
/// Kotlin: instant.toEpochMilliseconds()
@_cdecl("kk_instant_to_epoch_millis")
public func kk_instant_to_epoch_millis(_ instantRaw: Int) -> Int {
    guard let instant = runtimeKotlinInstantBox(from: instantRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_instant_to_epoch_millis received invalid Instant handle")
    }
    let millis = runtimeEpochMilliseconds(epochSeconds: instant.epochSeconds, nanoOfSecond: instant.nanoOfSecond)
    return Int(millis)
}

/// Creates a kotlin.time.Instant from separate epoch-seconds and nanoOfSecond components.
///
/// Kotlin: Instant.fromEpochSeconds(epochSeconds, nanoOfSecond)
@_cdecl("kk_instant_from_epoch_seconds")
public func kk_instant_from_epoch_seconds(_ epochSeconds: Int, _ nanoOfSecond: Int) -> Int {
    return registerRuntimeObject(
        RuntimeInstantBox(epochSeconds: Int64(epochSeconds), nanoOfSecond: Int32(nanoOfSecond))
    )
}
