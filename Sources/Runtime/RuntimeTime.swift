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

private func runtimeKotlinInstantBox(from raw: Int) -> RuntimeInstantBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeInstantBox.self)
}

private func runtimeJSDateBox(from raw: Int) -> RuntimeJSDateBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeJSDateBox.self)
}

private func runtimeTimeMarkBox(from raw: Int) -> RuntimeTimeMarkBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    return tryCast(ptr, to: RuntimeTimeMarkBox.self)
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
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_to_java_duration received invalid Duration handle")
    }
    let components = runtimeJavaDurationComponents(from: nanoseconds)
    return registerRuntimeObject(
        RuntimeJavaDurationBox(seconds: components.seconds, nanoAdjustment: components.nanoAdjustment)
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

@_cdecl("__kk_time_source_mark_now")
public func __kk_time_source_mark_now(_ receiver: Int) -> Int {
    Int(runtimeMonotonicNowNanoseconds())
}

@_cdecl("__kk_time_source_monotonic_mark_now")
public func __kk_time_source_monotonic_mark_now(_ receiver: Int) -> Int {
    __kk_time_source_mark_now(receiver)
}

@_cdecl("__kk_time_source_as_clock")
public func __kk_time_source_as_clock(_ sourceRaw: Int, _ originRaw: Int) -> Int {
    kk_time_source_as_clock(sourceRaw, originRaw)
}

// MARK: - TimeMark reading bridges (KSP-648 / KSP-649)
//
// elapsedNow / hasPassedNow / hasNotPassedNow / plus / minus / minus-mark / compareTo now
// live in Sources/CompilerCore/Stdlib/kotlin/time/TimeMark.kt. Only the mark reading itself
// (which touches RuntimeTimeMarkBox internals and the monotonic clock) stays native.

private let valueTimeMarkRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.time.TimeSource.Monotonic.ValueTimeMark")
private let abstractLongTimeMarkRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.time.AbstractLongTimeMark")
private let abstractDoubleTimeMarkRuntimeTypeID: Int64 = runtimeStableNominalTypeID(fqName: "kotlin.time.AbstractDoubleTimeMark")

private func runtimeTimeSourceUnitScale(_ ordinal: Int) -> Int64 {
    switch ordinal {
    case 0: return 1
    case 1: return 1_000
    case 2: return 1_000_000
    case 3: return 1_000_000_000
    case 4: return 60_000_000_000
    case 5: return 3_600_000_000_000
    case 6: return 86_400_000_000_000
    default: return 1
    }
}

private func runtimeTimeSaturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow {
        return lhs >= 0 ? Int64.max : Int64.min
    }
    return result
}

private func runtimeTimeSaturatingMultiply(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.multipliedReportingOverflow(by: rhs)
    if overflow {
        return (lhs < 0) == (rhs < 0) ? Int64.max : Int64.min
    }
    return result
}

private func runtimeAbstractLongTimeMarkReadingNanos(_ markRaw: Int) -> Int? {
    guard let mark = runtimeArrayBox(from: markRaw), mark.count >= 5,
          let source = runtimeArrayBox(from: mark[3]) else {
        return nil
    }
    let unit = kk_unbox_int(source[2])
    let scale = runtimeTimeSourceUnitScale(unit)
    let startedAt = Int64(mark[2])
    let offset = Int64(kk_duration_inWholeNanoseconds(mark[4]))
    return Int(runtimeTimeSaturatingAdd(runtimeTimeSaturatingMultiply(startedAt, scale), offset))
}

private func runtimeAbstractDoubleTimeMarkReadingNanos(_ markRaw: Int) -> Int? {
    guard let mark = runtimeArrayBox(from: markRaw), mark.count >= 5,
          let source = runtimeArrayBox(from: mark[3]) else {
        return nil
    }
    let unit = kk_unbox_int(source[2])
    let scale = Double(runtimeTimeSourceUnitScale(unit))
    let value = Double(bitPattern: UInt64(bitPattern: Int64(mark[2])))
    let scaled = value * scale
    let startedAtNanos: Int64
    if value.isNaN {
        startedAtNanos = 0
    } else if !scaled.isFinite || scaled >= Double(Int64.max) {
        startedAtNanos = scaled.sign == .minus ? Int64.min : Int64.max
    } else if scaled <= Double(Int64.min) {
        startedAtNanos = Int64.min
    } else {
        startedAtNanos = Int64(scaled.rounded())
    }
    let offset = Int64(kk_duration_inWholeNanoseconds(mark[4]))
    return Int(runtimeTimeSaturatingAdd(startedAtNanos, offset))
}

@_cdecl("__kk_time_mark_reading_nanos")
public func __kk_time_mark_reading_nanos(_ markRaw: Int) -> Int {
    if let mark = runtimeTimeMarkBox(from: markRaw) {
        return Int(mark.uptimeNanoseconds)
    }
    guard let box = runtimeArrayBox(from: markRaw),
          box.count > 0
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_time_mark_reading_nanos received invalid TimeMark handle")
    }
    // ValueTimeMark is a boxed value class (RuntimeObjectBox) whose single
    // property 'reading' is stored at field offset 2 after the header words.
    if box.count == 3,
       runtimeObjectTypeID(rawValue: markRaw) == valueTimeMarkRuntimeTypeID {
        return box[2]
    }
    if runtimeObjectTypeID(rawValue: markRaw) == abstractLongTimeMarkRuntimeTypeID,
       let reading = runtimeAbstractLongTimeMarkReadingNanos(markRaw) {
        return reading
    }
    if runtimeObjectTypeID(rawValue: markRaw) == abstractDoubleTimeMarkRuntimeTypeID,
       let reading = runtimeAbstractDoubleTimeMarkReadingNanos(markRaw) {
        return reading
    }
    // Fallback for one-field value-class boxes stored at the last slot.
    return box[box.count - 1]
}

@_cdecl("__kk_time_mark_now_reading_nanos")
public func __kk_time_mark_now_reading_nanos() -> Int {
    Int(runtimeMonotonicNowNanoseconds())
}

@_cdecl("__kk_time_mark_from_reading_nanos")
public func __kk_time_mark_from_reading_nanos(_ readingNanos: Int) -> Int {
    registerRuntimeObject(RuntimeTimeMarkBox(uptimeNanoseconds: Int64(readingNanos)))
}

/// ComparableTimeMark shares RuntimeTimeMarkBox with TimeMark; the two factories exist only
/// because the Kotlin declarations differ in return type and cannot be overloads.
@_cdecl("__kk_comparable_time_mark_from_reading_nanos")
public func __kk_comparable_time_mark_from_reading_nanos(_ readingNanos: Int) -> Int {
    __kk_time_mark_from_reading_nanos(readingNanos)
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
