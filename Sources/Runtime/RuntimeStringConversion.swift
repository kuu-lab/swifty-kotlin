// String-to-type conversion functions (toInt, toDouble, toLong, toFloat,
// toByte, toShort, toBoolean, toBigDecimal, and their variants).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

/// `Character.digit(ch, radix)` for a single UTF-16 code unit: ASCII and
/// full-width Latin letters plus every Unicode decimal digit (category Nd).
/// Supplementary scalars are rejected because Kotlin parses `Char`s.
private func runtimeKotlinDigitValue(_ scalar: Unicode.Scalar, radix: Int) -> Int? {
    let value = scalar.value
    let digit: Int
    switch value {
    case 0x30 ... 0x39: digit = Int(value - 0x30)
    case 0x41 ... 0x5A: digit = Int(value - 0x41) + 10
    case 0x61 ... 0x7A: digit = Int(value - 0x61) + 10
    case 0xFF21 ... 0xFF3A: digit = Int(value - 0xFF21) + 10
    case 0xFF41 ... 0xFF5A: digit = Int(value - 0xFF41) + 10
    case 0x80 ... 0xFFFF:
        guard scalar.properties.generalCategory == .decimalNumber,
              let numeric = scalar.properties.numericValue
        else { return nil }
        digit = Int(numeric)
    default:
        return nil
    }
    return digit < radix ? digit : nil
}

/// Kotlin `String.toXxxOrNull(radix)` grammar: optional sign (`-` only for
/// signed targets, so `"-0"` is rejected for unsigned ones), then one or more
/// digits accepted by `Character.digit`, with overflow reported as `nil`.
func runtimeParseKotlinInteger<T: FixedWidthInteger>(
    _ source: String,
    radix: Int,
    as _: T.Type
) -> T? {
    var scalars = source.unicodeScalars[...]
    guard let first = scalars.first else { return nil }
    var negative = false
    if first.value < 0x30 {
        guard scalars.count > 1 else { return nil }
        if first == "-", T.isSigned {
            negative = true
        } else if first != "+" {
            return nil
        }
        scalars = scalars.dropFirst()
    }
    var magnitude: UInt64 = 0
    let base = UInt64(radix)
    for scalar in scalars {
        guard let digit = runtimeKotlinDigitValue(scalar, radix: radix) else { return nil }
        let (scaled, scaleOverflow) = magnitude.multipliedReportingOverflow(by: base)
        let (sum, addOverflow) = scaled.addingReportingOverflow(UInt64(digit))
        if scaleOverflow || addOverflow { return nil }
        magnitude = sum
    }
    if negative {
        let minMagnitude = UInt64(T.max) + 1
        guard magnitude <= minMagnitude else { return nil }
        return magnitude == minMagnitude ? T.min : 0 - T(magnitude)
    }
    return T(exactly: magnitude)
}

/// JDK `NumberFormatException.forInputString(s, radix)`: the radix is only
/// mentioned when it is not 10.
func runtimeNumberFormatInputMessage(_ source: String, radix: Int) -> String {
    radix == 10 ? "For input string: \"\(source)\"" : "For input string: \"\(source)\" under radix \(radix)"
}

/// JDK `Byte.parseByte` / `Short.parseShort`: parse as `Int` first (reporting
/// unparsable input with `forInputString`), then reject values outside the
/// target range with the "Value out of range" message.
func runtimeParseNarrowKotlinInteger<T: FixedWidthInteger & SignedInteger>(
    _ source: String,
    radix: Int,
    as _: T.Type,
    outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    guard let wide = runtimeParseKotlinInteger(source, radix: radix, as: Int32.self) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: runtimeNumberFormatInputMessage(source, radix: radix)
        )
        return 0
    }
    guard let value = T(exactly: wide) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "Value out of range. Value:\"\(source)\" Radix:\(radix)"
        )
        return 0
    }
    return Int(value)
}

@_cdecl("__kk_string_toInt")
public func __kk_string_toInt(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: Int32.self) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("__kk_string_toInt_radix")
public func __kk_string_toInt_radix(_ strRaw: Int, _ radix: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return 0
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: Int32.self) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: runtimeNumberFormatInputMessage(source, radix: radix)
        )
        return 0
    }
    return Int(value)
}

@_cdecl("__kk_string_toIntOrNull")
public func __kk_string_toIntOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: Int32.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toIntOrNull_radix")
public func __kk_string_toIntOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return runtimeNullSentinelInt
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: Int32.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

// SPEC-NUM-0007: String.toUByteOrNull() / toUShortOrNull() / toUIntOrNull() / toULongOrNull() — no-arg (radix 10)

@_cdecl("__kk_string_toUByteOrNull")
public func __kk_string_toUByteOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: UInt8.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toUShortOrNull")
public func __kk_string_toUShortOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: UInt16.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toUIntOrNull")
public func __kk_string_toUIntOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: UInt32.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toULongOrNull")
public func __kk_string_toULongOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: UInt64.self) else {
        return runtimeNullSentinelInt
    }
    // ULong? slots hold box-or-sentinel: 2^63 bit-equals the sentinel (KUU-854).
    return kk_box_ulong_nonnull(Int(bitPattern: UInt(value)))
}

@_cdecl("__kk_string_toUByteOrNull_radix")
public func __kk_string_toUByteOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return runtimeNullSentinelInt
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: UInt8.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toUShortOrNull_radix")
public func __kk_string_toUShortOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return runtimeNullSentinelInt
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: UInt16.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toUIntOrNull_radix")
public func __kk_string_toUIntOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return runtimeNullSentinelInt
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: UInt32.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toULongOrNull_radix")
public func __kk_string_toULongOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return runtimeNullSentinelInt
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: UInt64.self) else {
        return runtimeNullSentinelInt
    }
    return kk_box_ulong_nonnull(Int(bitPattern: UInt(truncatingIfNeeded: value)))
}

@_cdecl("__kk_string_toULongOrNull_radix_flat")
public func __kk_string_toULongOrNull_radix_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toULongOrNull_radix(kk_string_from_flat(data, length, byteCount, hash), radix, outThrown)
}

/// `java.lang.String.trim()`: strips only leading/trailing scalars <= U+0020,
/// unlike Foundation's `.whitespacesAndNewlines` (which also drops NBSP etc.).
private func runtimeTrimJavaWhitespace(_ source: String) -> String {
    let scalars = source.unicodeScalars
    guard let start = scalars.firstIndex(where: { $0.value > 0x20 }),
          let last = scalars.lastIndex(where: { $0.value > 0x20 })
    else { return "" }
    return String(scalars[start ... last])
}

private let runtimeDecimalFloatingLiteralPattern =
    #"^[+-]?((([0-9]+(\.[0-9]*)?|\.[0-9]+)([eE][+-]?[0-9]+)?)|([0-9]+[eE][+-]?[0-9]+))[fFdD]?$"#
private let runtimeHexFloatingLiteralPattern =
    #"^[+-]?0[xX](([0-9A-Fa-f]+(\.[0-9A-Fa-f]*)?)|(\.[0-9A-Fa-f]+))[pP][+-]?[0-9]+[fFdD]?$"#

private func runtimeMatchesEntireRegex(_ source: String, pattern: String) -> Bool {
    guard let range = source.range(of: pattern, options: .regularExpression) else {
        return false
    }
    return range == source.startIndex ..< source.endIndex
}

private func runtimeDroppingFloatingTypeSuffix(_ source: String) -> String {
    guard let last = source.unicodeScalars.last, "fFdD".unicodeScalars.contains(last) else {
        return source
    }
    return String(source.dropLast())
}

/// Parse Kotlin/Java-style floating literals without accepting Swift-only spellings.
private func runtimeParseDouble(_ trimmed: String) -> Double? {
    switch trimmed {
    case "NaN", "+NaN", "-NaN":
        return .nan
    case "Infinity", "+Infinity":
        return .infinity
    case "-Infinity":
        return -.infinity
    default:
        break
    }

    guard runtimeMatchesEntireRegex(trimmed, pattern: runtimeDecimalFloatingLiteralPattern)
        || runtimeMatchesEntireRegex(trimmed, pattern: runtimeHexFloatingLiteralPattern)
    else {
        return nil
    }
    return Double(runtimeDroppingFloatingTypeSuffix(trimmed))
}

@_cdecl("__kk_string_toDouble")
public func __kk_string_toDouble(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = runtimeTrimJavaWhitespace(source)
    if trimmed.isEmpty {
        outThrown?.pointee = runtimeAllocateNumberFormatException(message: "empty String")
        return 0
    }

    guard let parsed = runtimeParseDouble(trimmed) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(trimmed)\""
        )
        return 0
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: parsed.bitPattern))
}

@_cdecl("__kk_string_toDouble_flat")
public func __kk_string_toDouble_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    __kk_string_toDouble(kk_string_from_flat(data, length, byteCount, hash), outThrown)
}

@_cdecl("__kk_string_toDoubleOrNull")
public func __kk_string_toDoubleOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = runtimeTrimJavaWhitespace(source)
    guard !trimmed.isEmpty else {
        return runtimeNullSentinelInt
    }

    guard let parsed = runtimeParseDouble(trimmed) else {
        return runtimeNullSentinelInt
    }
    // Double? slots hold box-or-sentinel: -0.0 bit-equals the sentinel (KUU-854).
    return kk_box_double_nonnull(Int(bitPattern: UInt(truncatingIfNeeded: parsed.bitPattern)))
}

@_cdecl("__kk_string_toDoubleOrNull_flat")
public func __kk_string_toDoubleOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    __kk_string_toDoubleOrNull(kk_string_from_flat(data, length, byteCount, hash))
}

// MARK: - STDLIB-420 String.toLong / toLongOrNull / toFloat / toFloatOrNull

#if !arch(arm64) && !arch(x86_64)
#error("Long conversion assumes 64-bit Int")
#endif

/// Parse a trimmed string using the same Kotlin/Java floating-literal grammar as Double.
private func runtimeParseFloat(_ trimmed: String) -> Float? {
    switch trimmed {
    case "NaN", "+NaN", "-NaN":
        return .nan
    case "Infinity", "+Infinity":
        return .infinity
    case "-Infinity":
        return -.infinity
    default:
        break
    }

    guard runtimeMatchesEntireRegex(trimmed, pattern: runtimeDecimalFloatingLiteralPattern)
        || runtimeMatchesEntireRegex(trimmed, pattern: runtimeHexFloatingLiteralPattern)
    else {
        return nil
    }
    return Float(runtimeDroppingFloatingTypeSuffix(trimmed))
}

/// Convert a Float's bit pattern to Int in an architecture-safe manner.
private func runtimeFloatBitsToInt(_ f: Float) -> Int {
    Int(bitPattern: UInt(f.bitPattern))
}

@_cdecl("__kk_string_toLong")
public func __kk_string_toLong(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: Int64.self) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(source)\""
        )
        return 0
    }
    return Int(truncatingIfNeeded: value)
}

@_cdecl("__kk_string_toLongOrNull")
public func __kk_string_toLongOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: Int64.self) else {
        return runtimeNullSentinelInt
    }
    // Long? slots hold box-or-sentinel: Long.MIN_VALUE bit-equals the
    // sentinel (KUU-854).
    return kk_box_long_nonnull(Int(truncatingIfNeeded: value))
}

@_cdecl("__kk_string_toLong_radix")
public func __kk_string_toLong_radix(_ strRaw: Int, _ radix: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return 0
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: Int64.self) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: runtimeNumberFormatInputMessage(source, radix: radix)
        )
        return 0
    }
    return Int(truncatingIfNeeded: value)
}

@_cdecl("__kk_string_toLongOrNull_radix")
public func __kk_string_toLongOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return runtimeNullSentinelInt
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: Int64.self) else {
        return runtimeNullSentinelInt
    }
    // Long? slots hold box-or-sentinel: Long.MIN_VALUE bit-equals the
    // sentinel (KUU-854).
    return kk_box_long_nonnull(Int(truncatingIfNeeded: value))
}

@_cdecl("__kk_string_toFloat")
public func __kk_string_toFloat(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = runtimeTrimJavaWhitespace(source)
    if trimmed.isEmpty {
        outThrown?.pointee = runtimeAllocateNumberFormatException(message: "empty String")
        return 0
    }

    guard let parsed = runtimeParseFloat(trimmed) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(trimmed)\""
        )
        return 0
    }
    return runtimeFloatBitsToInt(parsed)
}

@_cdecl("__kk_string_toFloatOrNull")
public func __kk_string_toFloatOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = runtimeTrimJavaWhitespace(source)
    guard !trimmed.isEmpty else {
        return runtimeNullSentinelInt
    }

    guard let parsed = runtimeParseFloat(trimmed) else {
        return runtimeNullSentinelInt
    }
    // Float? slots hold box-or-sentinel: -0.0f collides with the sentinel
    // under the f32 null comparison (KUU-854).
    return kk_box_float(runtimeFloatBitsToInt(parsed))
}

@_cdecl("__kk_string_toBoolean")
public func __kk_string_toBoolean(_ strRaw: Int) -> Int {
    // Kotlin spec: `public actual fun String?.toBoolean(): Boolean` returns false
    // when the receiver is null, otherwise true iff content equals "true" ignoring case.
    if strRaw == runtimeNullSentinelInt {
        return kk_box_bool(0)
    }
    guard let rawPointer = UnsafeMutableRawPointer(bitPattern: strRaw),
          let source = extractString(from: rawPointer)
    else {
        return kk_box_bool(0)
    }
    return kk_box_bool(source.caseInsensitiveCompare("true") == .orderedSame ? 1 : 0)
}

@_cdecl("__kk_string_toBooleanStrict")
public func __kk_string_toBooleanStrict(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    switch source {
    case "true":
        return kk_box_bool(1)
    case "false":
        return kk_box_bool(0)
    default:
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "The string doesn't represent a boolean value: \(source)")
        )
        return 0
    }
}

@_cdecl("__kk_string_toBooleanStrictOrNull")
public func __kk_string_toBooleanStrictOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    switch source {
    case "true":
        return 1
    case "false":
        return 0
    default:
        return runtimeNullSentinelInt
    }
}

@_cdecl("__kk_string_toShort")
public func __kk_string_toShort(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeParseNarrowKotlinInteger(source, radix: 10, as: Int16.self, outThrown: outThrown)
}

@_cdecl("__kk_string_toShortOrNull")
public func __kk_string_toShortOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: Int16.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toByte")
public func __kk_string_toByte(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeParseNarrowKotlinInteger(source, radix: 10, as: Int8.self, outThrown: outThrown)
}

@_cdecl("__kk_string_toByte_radix")
public func __kk_string_toByte_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return 0
    }
    return runtimeParseNarrowKotlinInteger(source, radix: radix, as: Int8.self, outThrown: outThrown)
}

@_cdecl("__kk_string_toByteOrNull")
public func __kk_string_toByteOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: Int8.self) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

// MARK: - STDLIB-TEXT-FN-083: String.toBigDecimal()

/// BigDecimal is represented as a boxed string in KSwiftK.
/// The runtime validates the format and stores the string representation.
final class RuntimeBigNumberBox {
    let value: String
    let kind: BigNumberKind

    enum BigNumberKind { case decimal }

    init(value: String, kind: BigNumberKind) {
        self.value = value
        self.kind = kind
    }
}

/// Locale-independent validation for BigDecimal format matching Kotlin/Java:
/// `[+-]?(\d+\.?\d*|\.\d+)([eE][+-]?\d+)?`
///
/// Note: We intentionally avoid `Decimal(string:)` or `NumberFormatter` because
/// Foundation's decimal parsing is locale-sensitive (e.g., decimal separator may
/// vary by locale). Instead, this hand-written parser validates against a fixed
/// POSIX-style grammar that matches Kotlin/JVM BigDecimal semantics.
private func isValidBigDecimalFormat(_ s: String) -> Bool {
    var i = s.startIndex
    guard i < s.endIndex else { return false }
    // Optional leading sign
    if s[i] == "+" || s[i] == "-" {
        i = s.index(after: i)
        guard i < s.endIndex else { return false }
    }
    // Must have at least one digit before or after the decimal point
    let digitStart = i
    while i < s.endIndex, s[i] >= "0", s[i] <= "9" { i = s.index(after: i) }
    let hasIntPart = i > digitStart
    var hasFracPart = false
    if i < s.endIndex, s[i] == "." {
        i = s.index(after: i)
        let fracStart = i
        while i < s.endIndex, s[i] >= "0", s[i] <= "9" { i = s.index(after: i) }
        hasFracPart = i > fracStart
    }
    guard hasIntPart || hasFracPart else { return false }
    // Optional exponent
    if i < s.endIndex, s[i] == "e" || s[i] == "E" {
        i = s.index(after: i)
        guard i < s.endIndex else { return false }
        if s[i] == "+" || s[i] == "-" {
            i = s.index(after: i)
            guard i < s.endIndex else { return false }
        }
        let expStart = i
        while i < s.endIndex, s[i] >= "0", s[i] <= "9" { i = s.index(after: i) }
        guard i > expStart else { return false }
    }
    return i == s.endIndex
}

@_cdecl("__kk_string_toBigDecimal")
public func __kk_string_toBigDecimal(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    guard let ptr = UnsafeMutableRawPointer(bitPattern: strRaw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_string_toBigDecimal received invalid string handle")
    }
    // No whitespace trimming: Kotlin/JVM throws NumberFormatException on
    // leading/trailing whitespace, so we validate the raw string as-is.
    guard isValidBigDecimalFormat(str) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(message: "For input string: \"\(str)\"")
        return 0
    }
    let box = RuntimeBigNumberBox(value: str, kind: .decimal)
    return registerRuntimeObject(box)
}

@_cdecl("__kk_string_toBigDecimal_flat")
public func __kk_string_toBigDecimal_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    let str = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    outThrown?.pointee = 0
    guard isValidBigDecimalFormat(str) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(message: "For input string: \"\(str)\"")
        return 0
    }
    let box = RuntimeBigNumberBox(value: str, kind: .decimal)
    return registerRuntimeObject(box)
}

@_cdecl("__kk_string_toBigDecimalOrNull")
public func __kk_string_toBigDecimalOrNull(_ strRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: strRaw),
          let str = extractString(from: ptr)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_string_toBigDecimalOrNull received invalid string handle")
    }
    // No whitespace trimming: Kotlin/JVM returns null for whitespace-wrapped
    // input because the underlying BigDecimal parser rejects it.
    guard isValidBigDecimalFormat(str) else {
        return runtimeNullSentinelInt
    }
    let box = RuntimeBigNumberBox(value: str, kind: .decimal)
    return registerRuntimeObject(box)
}

@_cdecl("__kk_string_toBigDecimalOrNull_flat")
public func __kk_string_toBigDecimalOrNull_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int
) -> Int {
    let str = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    guard isValidBigDecimalFormat(str) else {
        return runtimeNullSentinelInt
    }
    let box = RuntimeBigNumberBox(value: str, kind: .decimal)
    return registerRuntimeObject(box)
}

@_cdecl("__kk_bignum_toString")
public func __kk_bignum_toString(_ numRaw: Int) -> Int {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: numRaw),
          let box = tryCast(ptr, to: RuntimeBigNumberBox.self)
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_bignum_toString received invalid BigNumber handle")
    }
    return runtimeMakeStringRaw(box.value)
}
