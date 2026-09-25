// String-to-type conversion functions (toInt, toDouble, toLong, toFloat,
// toByte, toShort, toBoolean, toBigDecimal, and their variants).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

@_cdecl("__kk_string_toInt")
public func __kk_string_toInt(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int32(source) else {
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
    guard let value = Int32(source, radix: radix) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("__kk_string_toIntOrNull")
public func __kk_string_toIntOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int32(source) else {
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
    guard let value = Int32(source, radix: radix) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

// SPEC-NUM-0007: String.toUByteOrNull() / toUShortOrNull() / toUIntOrNull() / toULongOrNull() — no-arg (radix 10)

@_cdecl("__kk_string_toUByteOrNull")
public func __kk_string_toUByteOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = UInt8(source) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toUShortOrNull")
public func __kk_string_toUShortOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = UInt16(source) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toUIntOrNull")
public func __kk_string_toUIntOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = UInt32(source) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toULongOrNull")
public func __kk_string_toULongOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = UInt64(source) else {
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: UInt(value))
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
    guard let value = UInt8(source, radix: radix) else {
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
    guard let value = UInt16(source, radix: radix) else {
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
    guard let value = UInt32(source, radix: radix) else {
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
    guard let value = UInt64(source, radix: radix) else {
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: value))
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
    case "NaN":
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
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
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
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return runtimeNullSentinelInt
    }

    guard let parsed = runtimeParseDouble(trimmed) else {
        return runtimeNullSentinelInt
    }
    return Int(bitPattern: UInt(truncatingIfNeeded: parsed.bitPattern))
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
    case "NaN":
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
    guard let value = Int64(source) else {
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
    guard let value = Int64(source) else {
        return runtimeNullSentinelInt
    }
    return Int(truncatingIfNeeded: value)
}

@_cdecl("__kk_string_toFloat")
public func __kk_string_toFloat(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
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
    let trimmed = source.trimmingCharacters(in: .whitespacesAndNewlines)
    guard !trimmed.isEmpty else {
        return runtimeNullSentinelInt
    }

    guard let parsed = runtimeParseFloat(trimmed) else {
        return runtimeNullSentinelInt
    }
    return runtimeFloatBitsToInt(parsed)
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
    guard let value = Int16(source) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("__kk_string_toShortOrNull")
public func __kk_string_toShortOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int16(source) else {
        return runtimeNullSentinelInt
    }
    return Int(value)
}

@_cdecl("__kk_string_toByte")
public func __kk_string_toByte(_ strRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int8(source) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
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
    guard let value = Int8(source, radix: radix) else {
        outThrown?.pointee = runtimeAllocateNumberFormatException(
            message: "For input string: \"\(source)\""
        )
        return 0
    }
    return Int(value)
}

@_cdecl("__kk_string_toByteOrNull")
public func __kk_string_toByteOrNull(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    guard let value = Int8(source) else {
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

/// BigDecimal.compareTo: exact comparison of two validated decimal strings.
/// Unlike `equals`, Java/Kotlin BigDecimal comparison ignores scale
/// (1.0 == 1.00) and treats any zero as equal regardless of sign.
private struct BigDecimalParts {
    /// Canonical mantissa with no leading or trailing zeros; empty means zero.
    var digits: String
    /// Value is `0.digits * 10^pointExponent` (normalised scientific form).
    var pointExponent: Int
    var negative: Bool
}

private func parseBigDecimalParts(_ s: String) -> BigDecimalParts {
    var index = s.startIndex
    var negative = false
    if index < s.endIndex, s[index] == "+" || s[index] == "-" {
        negative = s[index] == "-"
        index = s.index(after: index)
    }
    var digits = ""
    var integerCount = 0
    while index < s.endIndex, s[index] >= "0", s[index] <= "9" {
        digits.append(s[index])
        integerCount += 1
        index = s.index(after: index)
    }
    if index < s.endIndex, s[index] == "." {
        index = s.index(after: index)
        while index < s.endIndex, s[index] >= "0", s[index] <= "9" {
            digits.append(s[index])
            index = s.index(after: index)
        }
    }
    var exponent = 0
    if index < s.endIndex, s[index] == "e" || s[index] == "E" {
        index = s.index(after: index)
        var exponentNegative = false
        if index < s.endIndex, s[index] == "+" || s[index] == "-" {
            exponentNegative = s[index] == "-"
            index = s.index(after: index)
        }
        while index < s.endIndex, s[index] >= "0", s[index] <= "9" {
            exponent = exponent * 10 + Int(s[index].asciiValue! - UInt8(ascii: "0"))
            index = s.index(after: index)
        }
        if exponentNegative { exponent = -exponent }
    }
    var pointExponent = exponent + integerCount
    while digits.hasPrefix("0") {
        digits.removeFirst()
        pointExponent -= 1
    }
    while digits.hasSuffix("0") {
        digits.removeLast()
    }
    return BigDecimalParts(digits: digits, pointExponent: pointExponent, negative: negative)
}

private func compareBigDecimalMagnitudes(_ a: BigDecimalParts, _ b: BigDecimalParts) -> Int {
    if a.pointExponent != b.pointExponent {
        return a.pointExponent < b.pointExponent ? -1 : 1
    }
    let aDigits = Array(a.digits.utf8)
    let bDigits = Array(b.digits.utf8)
    for i in 0 ..< max(aDigits.count, bDigits.count) {
        let aDigit = i < aDigits.count ? aDigits[i] : UInt8(ascii: "0")
        let bDigit = i < bDigits.count ? bDigits[i] : UInt8(ascii: "0")
        if aDigit != bDigit {
            return aDigit < bDigit ? -1 : 1
        }
    }
    return 0
}

private func compareBigDecimalValues(_ lhs: String, _ rhs: String) -> Int {
    let a = parseBigDecimalParts(lhs)
    let b = parseBigDecimalParts(rhs)
    let aIsZero = a.digits.isEmpty
    let bIsZero = b.digits.isEmpty
    if aIsZero || bIsZero {
        if aIsZero, bIsZero { return 0 }
        return aIsZero ? (b.negative ? 1 : -1) : (a.negative ? -1 : 1)
    }
    if a.negative != b.negative {
        return a.negative ? -1 : 1
    }
    let magnitude = compareBigDecimalMagnitudes(a, b)
    return a.negative ? -magnitude : magnitude
}

@_cdecl("__kk_bignum_compareTo")
public func __kk_bignum_compareTo(_ lhsRaw: Int, _ rhsRaw: Int) -> Int {
    guard let lhsPtr = UnsafeMutableRawPointer(bitPattern: lhsRaw),
          let lhs = tryCast(lhsPtr, to: RuntimeBigNumberBox.self),
          let rhsPtr = UnsafeMutableRawPointer(bitPattern: rhsRaw),
          let rhs = tryCast(rhsPtr, to: RuntimeBigNumberBox.self),
          lhs.kind == .decimal, rhs.kind == .decimal
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_bignum_compareTo received invalid BigNumber handle")
    }
    return compareBigDecimalValues(lhs.value, rhs.value)
}
