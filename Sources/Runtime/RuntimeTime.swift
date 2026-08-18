import Dispatch
import Foundation

// MARK: - kotlin.time experimental time runtime (STDLIB-TIME-180)

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

// MARK: - TestTimeSource runtime (STDLIB-TIME-TYPE-009)

@_cdecl("kk_test_time_source_new")
public func kk_test_time_source_new() -> Int {
    return registerRuntimeObject(RuntimeTestTimeSourceBox())
}

@_cdecl("kk_test_time_source_plus_assign")
public func kk_test_time_source_plus_assign(_ sourceRaw: Int, _ durationRaw: Int) -> Int {
    guard let source = runtimeTestTimeSourceBox(from: sourceRaw),
          let durationNanoseconds = runtimeDurationNanosecondsValue(from: durationRaw)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_test_time_source_plus_assign received invalid handle")
    }
    source.nanoseconds = runtimeSaturatingAdd(source.nanoseconds, durationNanoseconds)
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
