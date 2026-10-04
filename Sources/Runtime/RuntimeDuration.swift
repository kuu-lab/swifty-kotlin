import Dispatch
import Foundation

// MARK: - kotlin.time.Duration Runtime (STDLIB-230/231)

/// Duration is stored as nanoseconds internally.
final class RuntimeDurationBox {
    let nanoseconds: Int64
    init(nanoseconds: Int64) { self.nanoseconds = nanoseconds }
}

private func runtimeDurationBox(from raw: Int) -> RuntimeDurationBox? {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
    let isRegisteredObject = runtimeStorage.withGCLock { state in
        state.objectPointers.contains(UInt(bitPattern: ptr))
    }
    guard isRegisteredObject else { return nil }
    return tryCast(ptr, to: RuntimeDurationBox.self)
}

/// Reads both the legacy boxed representation and Duration's source-backed
/// value-class payload. Raw values are only treated as object handles when the
/// runtime has registered the pointer, so ordinary small Long payloads are safe.
func runtimeDurationNanosecondsValue(from raw: Int) -> Int64? {
    if let box = runtimeDurationBox(from: raw) {
        return box.nanoseconds
    }
    return Int64(bitPattern: UInt64(bitPattern: Int64(raw)))
}

private func runtimeDurationIsInfinite(_ nanoseconds: Int64) -> Bool {
    nanoseconds == Int64.max || nanoseconds == Int64.min
}

private func runtimeDurationHandle(fromNanoseconds nanoseconds: Int64) -> Int {
    Int(truncatingIfNeeded: nanoseconds)
}

private func runtimeDurationBoxHandle(fromNanoseconds nanoseconds: Int64) -> Int {
    registerRuntimeObject(RuntimeDurationBox(nanoseconds: nanoseconds))
}

private func runtimeDurationNanoseconds(
    fromDoubleBits valueBits: Int,
    scale: Double
) -> Int64 {
    let value = kk_bits_to_double(valueBits)
    guard value.isFinite else {
        if value.isNaN {
            return 0
        }
        return value.sign == .minus ? Int64.min : Int64.max
    }

    let scaled = value * scale
    guard scaled.isFinite else {
        return scaled.sign == .minus ? Int64.min : Int64.max
    }

    let rounded = scaled.rounded()
    if rounded >= Double(Int64.max) {
        return Int64.max
    }
    if rounded <= Double(Int64.min) {
        return Int64.min
    }
    return Int64(rounded)
}

/// Formats `whole.fraction<unit>` following kotlin-stdlib's `Duration.toString()`
/// trimming rule: fewer than 3 significant fractional digits are kept as-is,
/// otherwise the fraction is padded out to the next multiple of 3 digits
/// (e.g. 4500ns of a second -> ".000004500", 500000ns -> ".000500").
private func runtimeDurationFormatFractional(
    whole: Int64,
    fractionalRemainder: Int64,
    fractionalWidth: Int,
    suffix: String
) -> String {
    guard fractionalRemainder != 0 else {
        return "\(whole)\(suffix)"
    }

    var fraction = String(fractionalRemainder)
    if fraction.count < fractionalWidth {
        fraction = String(repeating: "0", count: fractionalWidth - fraction.count) + fraction
    }
    let digits = Array(fraction)
    var significantDigits = digits.count
    while significantDigits > 0, digits[significantDigits - 1] == "0" {
        significantDigits -= 1
    }
    let keepDigits = significantDigits < 3 ? significantDigits : ((significantDigits + 2) / 3) * 3
    let trimmed = String(digits.prefix(keepDigits))
    return "\(whole).\(trimmed)\(suffix)"
}

private func runtimeDurationMakeString(_ value: String) -> Int {
    Int(bitPattern: value.withCString { cstr in
        cstr.withMemoryRebound(to: UInt8.self, capacity: value.utf8.count) { pointer in
            kk_string_from_utf8(pointer, Int32(value.utf8.count))
        }
    })
}

private func runtimeDurationComponents(
    _ nanoseconds: Int64,
    topUnit: Int64,
    lowerUnits: [Int64]
) -> (top: Int64, lower: [Int]) {
    var remaining = nanoseconds
    let top = remaining / topUnit
    remaining %= topUnit
    let lower = lowerUnits.map { unit -> Int in
        let component = remaining / unit
        remaining %= unit
        return Int(component)
    }
    return (top, lower)
}

private func runtimeDurationString(from raw: Int) -> String? {
    extractString(from: UnsafeMutableRawPointer(bitPattern: raw))
}

private let runtimeDurationNanosPerMicrosecond: Int64 = 1_000
private let runtimeDurationNanosPerMillisecond: Int64 = 1_000_000
private let runtimeDurationNanosPerSecond: Int64 = 1_000_000_000
private let runtimeDurationNanosPerMinute: Int64 = 60 * runtimeDurationNanosPerSecond
private let runtimeDurationNanosPerHour: Int64 = 60 * runtimeDurationNanosPerMinute
private let runtimeDurationNanosPerDay: Int64 = 24 * runtimeDurationNanosPerHour

/// DurationUnit ordinals mirror Kotlin's enum entry order:
/// 0=NANOSECONDS, 1=MICROSECONDS, 2=MILLISECONDS, 3=SECONDS,
/// 4=MINUTES, 5=HOURS, 6=DAYS.
private func runtimeDurationUnitScale(fromOrdinal ordinal: Int) -> Int64 {
    switch ordinal {
    case 0: return 1
    case 1: return runtimeDurationNanosPerMicrosecond
    case 2: return runtimeDurationNanosPerMillisecond
    case 3: return runtimeDurationNanosPerSecond
    case 4: return runtimeDurationNanosPerMinute
    case 5: return runtimeDurationNanosPerHour
    case 6: return runtimeDurationNanosPerDay
    default:
        assertionFailure("KSwiftK: unknown DurationUnit ordinal \(ordinal) – compiler/runtime enum mismatch?")
        return 1
    }
}

private func runtimeDurationSaturatingAdd(_ lhs: Int64, _ rhs: Int64) -> Int64 {
    let (result, overflow) = lhs.addingReportingOverflow(rhs)
    if overflow {
        return lhs >= 0 && rhs >= 0 ? Int64.max : Int64.min
    }
    return result
}

private func runtimeDurationSaturatingNegate(_ value: Int64) -> Int64 {
    value == Int64.min ? Int64.max : -value
}

private func runtimeDurationApplySign(_ value: Int64, sign: Int) -> Int64 {
    if sign >= 0 {
        return value
    }
    if value == Int64.max {
        return Int64.min
    }
    return runtimeDurationSaturatingNegate(value)
}

private func runtimeDurationNanoseconds(from value: Double, scale: Int64) -> Int64? {
    guard value.isFinite else {
        return nil
    }
    let scaled = value * Double(scale)
    guard scaled.isFinite else {
        return scaled.sign == .minus ? Int64.min : Int64.max
    }
    let rounded = scaled.rounded()
    if rounded >= Double(Int64.max) {
        return Int64.max
    }
    if rounded <= Double(Int64.min) {
        return Int64.min
    }
    return Int64(rounded)
}

/// kotlin-stdlib `Duration.parse` / `parseIsoString` grammar (2.3.10).
/// Decimal components are `[0-9]+` with an optional `.` + `[0-9]+` fraction;
/// scientific notation, a trailing/leading dot, and surrounding whitespace are rejected.
private func runtimeDurationAsciiDigit(_ ch: Character) -> Int? {
    guard let ascii = ch.asciiValue,
          ascii >= UInt8(ascii: "0"),
          ascii <= UInt8(ascii: "9")
    else {
        return nil
    }
    return Int(ascii - UInt8(ascii: "0"))
}

private func runtimeDurationParseSign(
    _ chars: [Character],
    index: inout Int,
    end: Int
) -> Int {
    guard index < end else { return 1 }
    if chars[index] == "-" {
        index += 1
        return -1
    }
    if chars[index] == "+" {
        index += 1
        return 1
    }
    return 1
}

private struct RuntimeDurationParsedNumber {
    let whole: Int64
    let fraction: Double
    let hasFraction: Bool
    let overflow: Bool
    let sign: Int
}

private struct RuntimeDurationParsedUnit {
    let order: Int
    let scale: Int64
}

private func runtimeDurationParseInteger(
    _ chars: [Character],
    index: inout Int,
    end: Int,
    allowSign: Bool
) -> (whole: Int64, overflow: Bool, sign: Int)? {
    let sign = allowSign ? runtimeDurationParseSign(chars, index: &index, end: end) : 1
    let digitsStart = index
    // Drop leading zeros so a zero-padded value is not reported as overflow.
    while index < end, chars[index] == "0" {
        index += 1
    }

    var whole: Int64 = 0
    var overflow = false
    while index < end {
        guard let digit = runtimeDurationAsciiDigit(chars[index]) else { break }
        if !overflow {
            let (multiplied, mulOverflow) = whole.multipliedReportingOverflow(by: 10)
            let (added, addOverflow) = multiplied.addingReportingOverflow(Int64(digit))
            if mulOverflow || addOverflow {
                overflow = true
                whole = Int64.max
            } else {
                whole = added
            }
        }
        index += 1
    }

    guard index > digitsStart else { return nil }
    return (whole, overflow, sign)
}

private func runtimeDurationParseFraction(
    _ chars: [Character],
    index: inout Int,
    end: Int
) -> Double? {
    let start = index
    var fraction = 0.0
    var place = 10.0
    while index < end {
        guard let digit = runtimeDurationAsciiDigit(chars[index]) else { break }
        fraction += Double(digit) / place
        place *= 10
        index += 1
    }
    guard index > start else { return nil }
    return fraction
}

private func runtimeDurationParseNumber(
    _ chars: [Character],
    index: inout Int,
    end: Int,
    allowSign: Bool
) -> RuntimeDurationParsedNumber? {
    guard let integer = runtimeDurationParseInteger(
        chars, index: &index, end: end, allowSign: allowSign
    ) else {
        return nil
    }
    let fraction: Double
    let hasFraction: Bool
    if index < end, chars[index] == "." {
        index += 1
        guard let parsed = runtimeDurationParseFraction(chars, index: &index, end: end) else {
            return nil
        }
        fraction = parsed
        hasFraction = true
    } else {
        fraction = 0
        hasFraction = false
    }
    return RuntimeDurationParsedNumber(
        whole: integer.whole,
        fraction: fraction,
        hasFraction: hasFraction,
        overflow: integer.overflow,
        sign: integer.sign
    )
}

private func runtimeDurationNanoseconds(
    from number: RuntimeDurationParsedNumber,
    scale: Int64
) -> Int64? {
    guard let unsigned = runtimeDurationNanoseconds(
        from: Double(number.whole) + number.fraction,
        scale: scale
    ) else {
        return nil
    }
    return runtimeDurationApplySign(unsigned, sign: number.sign)
}

private func runtimeDurationParseDefaultUnit(
    _ chars: [Character],
    index: inout Int,
    end: Int
) -> RuntimeDurationParsedUnit? {
    let start = index
    while index < end {
        guard let ascii = chars[index].asciiValue,
              ascii >= UInt8(ascii: "a"),
              ascii <= UInt8(ascii: "z")
        else {
            break
        }
        index += 1
    }
    guard index > start else { return nil }
    switch String(chars[start..<index]) {
    case "d": return RuntimeDurationParsedUnit(order: 6, scale: runtimeDurationNanosPerDay)
    case "h": return RuntimeDurationParsedUnit(order: 5, scale: runtimeDurationNanosPerHour)
    case "m": return RuntimeDurationParsedUnit(order: 4, scale: runtimeDurationNanosPerMinute)
    case "s": return RuntimeDurationParsedUnit(order: 3, scale: runtimeDurationNanosPerSecond)
    case "ms": return RuntimeDurationParsedUnit(order: 2, scale: runtimeDurationNanosPerMillisecond)
    case "us": return RuntimeDurationParsedUnit(order: 1, scale: runtimeDurationNanosPerMicrosecond)
    case "ns": return RuntimeDurationParsedUnit(order: 0, scale: 1)
    default: return nil
    }
}

private func runtimeDurationParseISOUnit(
    _ designator: Character,
    inTime: Bool
) -> RuntimeDurationParsedUnit? {
    switch (designator, inTime) {
    case ("D", false): return RuntimeDurationParsedUnit(order: 6, scale: runtimeDurationNanosPerDay)
    case ("H", true): return RuntimeDurationParsedUnit(order: 5, scale: runtimeDurationNanosPerHour)
    case ("M", true): return RuntimeDurationParsedUnit(order: 4, scale: runtimeDurationNanosPerMinute)
    case ("S", true): return RuntimeDurationParsedUnit(order: 3, scale: runtimeDurationNanosPerSecond)
    default: return nil
    }
}

private func runtimeDurationParseISOFormat(_ chars: [Character], startIndex: Int) -> Int64? {
    var index = startIndex
    guard index < chars.count else { return nil }

    var inTime = false
    var prevOrder: Int?
    var total: Int64 = 0

    while index < chars.count {
        if chars[index] == "T" {
            if inTime { return nil }
            index += 1
            if index == chars.count { return nil }
            inTime = true
            continue
        }

        guard let number = runtimeDurationParseNumber(
            chars, index: &index, end: chars.count, allowSign: true
        ), index < chars.count else {
            return nil
        }
        if number.hasFraction, chars[index] != "S" {
            return nil
        }
        guard let unit = runtimeDurationParseISOUnit(chars[index], inTime: inTime) else {
            return nil
        }
        if let prevOrder, prevOrder <= unit.order {
            return nil
        }
        prevOrder = unit.order
        index += 1

        guard let component = runtimeDurationNanoseconds(from: number, scale: unit.scale) else {
            return nil
        }
        total = runtimeDurationSaturatingAdd(total, component)
    }

    guard prevOrder != nil else { return nil }
    return total
}

private func runtimeDurationParseDefaultFormat(
    _ chars: [Character],
    startIndex: Int,
    hasSign: Bool
) -> Int64? {
    var index = startIndex
    var end = chars.count
    var allowSpaces = !hasSign

    if hasSign, index < chars.count, chars[index] == "(", chars.last == ")" {
        allowSpaces = true
        index += 1
        end -= 1
        guard index < end else { return nil }
    }

    var total: Int64 = 0
    var prevOrder: Int?

    while index < end {
        if allowSpaces, prevOrder != nil {
            while index < end, chars[index] == " " {
                index += 1
            }
        }

        guard let number = runtimeDurationParseNumber(
            chars, index: &index, end: end, allowSign: false
        ), !number.overflow, index < end else {
            return nil
        }
        guard let unit = runtimeDurationParseDefaultUnit(chars, index: &index, end: end) else {
            return nil
        }
        if let prevOrder, prevOrder <= unit.order {
            return nil
        }
        prevOrder = unit.order

        if number.hasFraction, index < end {
            return nil
        }

        guard let component = runtimeDurationNanoseconds(from: number, scale: unit.scale) else {
            return nil
        }
        total = runtimeDurationSaturatingAdd(total, component)
    }

    return total
}

private func runtimeDurationParseDuration(_ value: String, strictIso: Bool) -> Int64? {
    guard !value.isEmpty else { return nil }
    let chars = Array(value)
    var index = 0
    let isNegative = runtimeDurationParseSign(chars, index: &index, end: chars.count) < 0
    let hasSign = index > 0
    guard index < chars.count else { return nil }

    let parsed: Int64?
    if chars[index] == "P" {
        parsed = runtimeDurationParseISOFormat(chars, startIndex: index + 1)
    } else if strictIso {
        return nil
    } else if String(chars[index...]).lowercased() == "infinity" {
        parsed = Int64.max
    } else {
        parsed = runtimeDurationParseDefaultFormat(chars, startIndex: index, hasSign: hasSign)
    }
    guard let result = parsed else { return nil }
    return isNegative ? runtimeDurationApplySign(result, sign: -1) : result
}

private func runtimeDurationParseISO(_ input: String) -> Int64? {
    runtimeDurationParseDuration(input, strictIso: true)
}

private func runtimeDurationParse(_ input: String) -> Int64? {
    runtimeDurationParseDuration(input, strictIso: false)
}

/// Clamp-safe multiplication: returns `Int64.max` / `Int64.min` on overflow
/// instead of trapping, matching Kotlin's Duration saturation semantics.
func saturatingMultiply(_ a: Int64, _ b: Int64) -> Int64 {
    let (result, overflow) = a.multipliedReportingOverflow(by: b)
    if overflow {
        // If signs differ the overflow is negative, otherwise positive
        return (a ^ b) < 0 ? Int64.min : Int64.max
    }
    return result
}

@_cdecl("kk_duration_zero")
public func kk_duration_zero() -> Int {
    runtimeDurationHandle(fromNanoseconds: 0)
}

@_cdecl("kk_duration_infinite")
public func kk_duration_infinite() -> Int {
    runtimeDurationHandle(fromNanoseconds: Int64.max)
}

@_cdecl("kk_duration_toDuration_int")
public func kk_duration_toDuration_int(_ value: Int, _ unitOrdinal: Int) -> Int {
    runtimeDurationHandle(
        fromNanoseconds: saturatingMultiply(Int64(value), runtimeDurationUnitScale(fromOrdinal: unitOrdinal))
    )
}

@_cdecl("kk_duration_toDuration_long")
public func kk_duration_toDuration_long(_ value: Int, _ unitOrdinal: Int) -> Int {
    runtimeDurationHandle(
        fromNanoseconds: saturatingMultiply(Int64(value), runtimeDurationUnitScale(fromOrdinal: unitOrdinal))
    )
}

@_cdecl("kk_duration_toDuration_double")
public func kk_duration_toDuration_double(_ valueBits: Int, _ unitOrdinal: Int) -> Int {
    runtimeDurationHandle(
        fromNanoseconds: runtimeDurationNanoseconds(
            fromDoubleBits: valueBits,
            scale: Double(runtimeDurationUnitScale(fromOrdinal: unitOrdinal))
        )
    )
}

// MARK: - Duration properties

@_cdecl("kk_duration_inWholeNanoseconds")
public func kk_duration_inWholeNanoseconds(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_inWholeNanoseconds received invalid Duration handle")
    }
    return Int(truncatingIfNeeded: nanoseconds)
}

@_cdecl("kk_duration_toString")
public func kk_duration_toString(_ durationRaw: Int) -> Int {
    guard let ns = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_toString received invalid Duration handle")
    }

    if ns == 0 {
        return runtimeDurationMakeString("0s")
    }
    if ns == Int64.max {
        return runtimeDurationMakeString("Infinity")
    }
    if ns == Int64.min {
        return runtimeDurationMakeString("-Infinity")
    }

    let isNegative = ns < 0
    let absNs = isNegative ? -ns : ns

    // Decompose into days/hours/minutes/seconds/nanoseconds, matching
    // kotlin-stdlib's Duration.toString() component breakdown (values > 24h
    // roll up into days, e.g. 25h -> "1d 1h").
    let components = runtimeDurationComponents(
        absNs,
        topUnit: runtimeDurationNanosPerDay,
        lowerUnits: [runtimeDurationNanosPerHour, runtimeDurationNanosPerMinute, runtimeDurationNanosPerSecond, 1]
    )
    let days = components.top
    let hours = components.lower[0]
    let minutes = components.lower[1]
    let seconds = components.lower[2]
    let subsecondNanos = components.lower[3]

    let hasDays = days != 0
    let hasHours = hours != 0
    let hasMinutes = minutes != 0
    let hasSeconds = seconds != 0 || subsecondNanos != 0

    var out = ""
    var componentCount = 0

    if hasDays {
        out += "\(days)d"
        componentCount += 1
    }
    // Intermediate zero components stay visible once a higher and a lower
    // component are both present, e.g. 1 day + 5 minutes -> "1d 0h 5m".
    if hasHours || (hasDays && (hasMinutes || hasSeconds)) {
        if componentCount > 0 { out += " " }
        out += "\(hours)h"
        componentCount += 1
    }
    if hasMinutes || (hasSeconds && (hasHours || hasDays)) {
        if componentCount > 0 { out += " " }
        out += "\(minutes)m"
        componentCount += 1
    }
    if hasSeconds {
        if componentCount > 0 { out += " " }
        if seconds != 0 || hasDays || hasHours || hasMinutes {
            out += runtimeDurationFormatFractional(
                whole: Int64(seconds), fractionalRemainder: Int64(subsecondNanos), fractionalWidth: 9, suffix: "s"
            )
        } else if subsecondNanos >= 1_000_000 {
            out += runtimeDurationFormatFractional(
                whole: Int64(subsecondNanos / 1_000_000), fractionalRemainder: Int64(subsecondNanos % 1_000_000),
                fractionalWidth: 6, suffix: "ms"
            )
        } else if subsecondNanos >= 1_000 {
            out += runtimeDurationFormatFractional(
                whole: Int64(subsecondNanos / 1_000), fractionalRemainder: Int64(subsecondNanos % 1_000),
                fractionalWidth: 3, suffix: "us"
            )
        } else {
            out += "\(subsecondNanos)ns"
        }
        componentCount += 1
    }

    // A single negative component is prefixed with "-"; multiple components
    // are wrapped in parens, e.g. "-12m" vs. "-(1h 30m)".
    let str: String
    if isNegative && componentCount > 1 {
        str = "-(\(out))"
    } else if isNegative {
        str = "-\(out)"
    } else {
        str = out
    }
    return runtimeDurationMakeString(str)
}

@_cdecl("kk_duration_parse")
public func kk_duration_parse(_ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParse(value)
    else {
        let displayValue = runtimeDurationString(from: valueRaw) ?? "<null>"
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid duration string format: '\(displayValue)'."
        )
        return runtimeNullSentinelInt
    }
    return runtimeDurationHandle(fromNanoseconds: nanoseconds)
}

@_cdecl("kk_duration_parseOrNull")
public func kk_duration_parseOrNull(_ valueRaw: Int) -> Int {
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParse(value)
    else {
        return runtimeNullSentinelInt
    }
    return runtimeDurationBoxHandle(fromNanoseconds: nanoseconds)
}

@_cdecl("kk_duration_parseIsoString")
public func kk_duration_parseIsoString(_ valueRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParseISO(value)
    else {
        let displayValue = runtimeDurationString(from: valueRaw) ?? "<null>"
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "Invalid ISO duration string format: '\(displayValue)'."
        )
        return runtimeNullSentinelInt
    }
    return runtimeDurationHandle(fromNanoseconds: nanoseconds)
}

@_cdecl("kk_duration_parseIsoStringOrNull")
public func kk_duration_parseIsoStringOrNull(_ valueRaw: Int) -> Int {
    guard let value = runtimeDurationString(from: valueRaw),
          let nanoseconds = runtimeDurationParseISO(value)
    else {
        return runtimeNullSentinelInt
    }
    return runtimeDurationBoxHandle(fromNanoseconds: nanoseconds)
}

// MARK: - Duration advanced operations (STDLIB-TIME-082)

@_cdecl("kk_duration_absoluteValue")
public func kk_duration_absoluteValue(_ durationRaw: Int) -> Int {
    guard let ns = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_absoluteValue received invalid Duration handle")
    }
    let absNs = ns == Int64.min ? Int64.max : (ns < 0 ? -ns : ns)
    return runtimeDurationHandle(fromNanoseconds: absNs)
}

@_cdecl("kk_duration_isNegative")
public func kk_duration_isNegative(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isNegative received invalid Duration handle")
    }
    return nanoseconds < 0 ? 1 : 0
}

@_cdecl("kk_duration_isPositive")
public func kk_duration_isPositive(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isPositive received invalid Duration handle")
    }
    return nanoseconds > 0 ? 1 : 0
}

@_cdecl("kk_duration_isInfinite")
public func kk_duration_isInfinite(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_isInfinite received invalid Duration handle")
    }
    return (nanoseconds == Int64.max || nanoseconds == Int64.min) ? 1 : 0
}

@_cdecl("kk_duration_plus")
public func kk_duration_plus(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_plus received invalid Duration handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeDurationSaturatingAdd(lhs, rhs))
}

@_cdecl("kk_duration_minus")
public func kk_duration_minus(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_minus received invalid Duration handle")
    }
    return runtimeDurationHandle(fromNanoseconds: runtimeDurationSaturatingAdd(lhs, -rhs))
}

@_cdecl("kk_duration_times_int")
public func kk_duration_times_int(_ durationRaw: Int, _ scale: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_times_int received invalid Duration handle")
    }
    return runtimeDurationHandle(fromNanoseconds: saturatingMultiply(nanoseconds, Int64(scale)))
}

@_cdecl("kk_duration_div_int")
public func kk_duration_div_int(_ durationRaw: Int, _ scale: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_div_int received invalid Duration handle")
    }
    guard scale != 0 else {
        let ns: Int64 = nanoseconds >= 0 ? Int64.max : Int64.min
        return runtimeDurationHandle(fromNanoseconds: ns)
    }
    if nanoseconds == Int64.min, scale == -1 {
        return runtimeDurationHandle(fromNanoseconds: Int64.max)
    }
    return runtimeDurationHandle(fromNanoseconds: nanoseconds / Int64(scale))
}

@_cdecl("kk_duration_div_duration")
public func kk_duration_div_duration(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_div_duration received invalid Duration handle")
    }
    let lhsValue = runtimeDurationIsInfinite(lhs)
        ? (lhs > 0 ? Double.infinity : -Double.infinity)
        : Double(lhs)
    let rhsValue = runtimeDurationIsInfinite(rhs)
        ? (rhs > 0 ? Double.infinity : -Double.infinity)
        : Double(rhs)
    return kk_double_to_bits(lhsValue / rhsValue)
}

@_cdecl("kk_duration_unary_minus")
public func kk_duration_unary_minus(_ durationRaw: Int) -> Int {
    guard let nanoseconds = runtimeDurationNanosecondsValue(from: durationRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_unary_minus received invalid Duration handle")
    }
    let ns: Int64
    if nanoseconds == Int64.min {
        ns = Int64.max
    } else if nanoseconds == Int64.max {
        ns = Int64.min
    } else {
        ns = -nanoseconds
    }
    return runtimeDurationHandle(fromNanoseconds: ns)
}

@_cdecl("kk_duration_compareTo")
public func kk_duration_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhs = runtimeDurationNanosecondsValue(from: lhsRaw),
          let rhs = runtimeDurationNanosecondsValue(from: rhsRaw) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_duration_compareTo received invalid Duration handle")
    }
    if lhs < rhs { return -1 }
    if lhs > rhs { return 1 }
    return 0
}
