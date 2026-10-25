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

private func runtimeStringIntegerOrNull<T: FixedWidthInteger>(
    _ strRaw: Int,
    as _: T.Type,
    caller: StaticString,
    box: (T) -> Int
) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: caller)
    guard let value = runtimeParseKotlinInteger(source, radix: 10, as: T.self) else {
        return runtimeNullSentinelInt
    }
    return box(value)
}

private func runtimeStringIntegerOrNullRadix<T: FixedWidthInteger>(
    _ strRaw: Int,
    _ radix: Int,
    as _: T.Type,
    caller: StaticString,
    _ outThrown: UnsafeMutablePointer<Int>?,
    box: (T) -> Int
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: caller)
    guard (2 ... 36).contains(radix) else {
        runtimeSetThrown(
            outThrown,
            runtimeAllocateIllegalArgumentException(message: "radix \(radix) was not in valid range 2..36")
        )
        return runtimeNullSentinelInt
    }
    guard let value = runtimeParseKotlinInteger(source, radix: radix, as: T.self) else {
        return runtimeNullSentinelInt
    }
    return box(value)
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
    runtimeStringIntegerOrNull(strRaw, as: Int32.self, caller: #function) { Int($0) }
}

@_cdecl("__kk_string_toIntOrNull_radix")
public func __kk_string_toIntOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringIntegerOrNullRadix(strRaw, radix, as: Int32.self, caller: #function, outThrown) { Int($0) }
}

@_cdecl("__kk_string_toUByteOrNull")
public func __kk_string_toUByteOrNull(_ strRaw: Int) -> Int {
    runtimeStringIntegerOrNull(strRaw, as: UInt8.self, caller: #function) { Int($0) }
}

@_cdecl("__kk_string_toUShortOrNull")
public func __kk_string_toUShortOrNull(_ strRaw: Int) -> Int {
    runtimeStringIntegerOrNull(strRaw, as: UInt16.self, caller: #function) { Int($0) }
}

@_cdecl("__kk_string_toUIntOrNull")
public func __kk_string_toUIntOrNull(_ strRaw: Int) -> Int {
    runtimeStringIntegerOrNull(strRaw, as: UInt32.self, caller: #function) { Int($0) }
}

@_cdecl("__kk_string_toULongOrNull")
public func __kk_string_toULongOrNull(_ strRaw: Int) -> Int {
    // ULong? slots hold box-or-sentinel: 2^63 bit-equals the sentinel (KUU-854).
    return runtimeStringIntegerOrNull(strRaw, as: UInt64.self, caller: #function) {
        kk_box_ulong_nonnull(Int(bitPattern: UInt($0)))
    }
}

@_cdecl("__kk_string_toUByteOrNull_radix")
public func __kk_string_toUByteOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringIntegerOrNullRadix(strRaw, radix, as: UInt8.self, caller: #function, outThrown) { Int($0) }
}

@_cdecl("__kk_string_toUShortOrNull_radix")
public func __kk_string_toUShortOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringIntegerOrNullRadix(strRaw, radix, as: UInt16.self, caller: #function, outThrown) { Int($0) }
}

@_cdecl("__kk_string_toUIntOrNull_radix")
public func __kk_string_toUIntOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    runtimeStringIntegerOrNullRadix(strRaw, radix, as: UInt32.self, caller: #function, outThrown) { Int($0) }
}

@_cdecl("__kk_string_toULongOrNull_radix")
public func __kk_string_toULongOrNull_radix(
    _ strRaw: Int,
    _ radix: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return runtimeStringIntegerOrNullRadix(strRaw, radix, as: UInt64.self, caller: #function, outThrown) {
        kk_box_ulong_nonnull(Int(bitPattern: UInt(truncatingIfNeeded: $0)))
    }
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

#if !arch(arm64) && !arch(x86_64)
#error("Long conversion assumes 64-bit Int")
#endif

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
    // Long? slots hold box-or-sentinel: Long.MIN_VALUE bit-equals the
    // sentinel (KUU-854).
    return runtimeStringIntegerOrNull(strRaw, as: Int64.self, caller: #function) {
        kk_box_long_nonnull(Int(truncatingIfNeeded: $0))
    }
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
    // Long? slots hold box-or-sentinel: Long.MIN_VALUE bit-equals the
    // sentinel (KUU-854).
    return runtimeStringIntegerOrNullRadix(strRaw, radix, as: Int64.self, caller: #function, outThrown) {
        kk_box_long_nonnull(Int(truncatingIfNeeded: $0))
    }
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
    runtimeStringIntegerOrNull(strRaw, as: Int16.self, caller: #function) { Int($0) }
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
    runtimeStringIntegerOrNull(strRaw, as: Int8.self, caller: #function) { Int($0) }
}

/// BigDecimal is represented as a boxed string in KSwiftK.
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
    if s[i] == "+" || s[i] == "-" {
        i = s.index(after: i)
        guard i < s.endIndex else { return false }
    }
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

func runtimeBigDecimalValue(_ numRaw: Int, caller: String) -> String {
    guard let ptr = UnsafeMutableRawPointer(bitPattern: numRaw),
          let box = tryCast(ptr, to: RuntimeBigNumberBox.self),
          box.kind == .decimal
    else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: \(caller) received invalid BigDecimal handle")
    }
    return box.value
}

/// Return the low 64 bits of a BigDecimal truncated toward zero.
private func runtimeBigDecimalIntegerBits(_ source: String) -> UInt64 {
    let value = parseBigDecimalParts(source)
    guard !value.digits.isEmpty, value.pointExponent > 0 else { return 0 }

    let digits = Array(value.digits.utf8)
    let integerDigitCount = value.pointExponent
    let retainedDigitCount = min(integerDigitCount, digits.count)
    var bits: UInt64 = 0
    if retainedDigitCount > 0 {
        for index in 0 ..< retainedDigitCount {
            bits = bits &* 10 &+ UInt64(digits[index] - UInt8(ascii: "0"))
        }
    }

    let appendedZeroCount = integerDigitCount - retainedDigitCount
    if appendedZeroCount >= 64 {
        bits = 0
    } else if appendedZeroCount > 0 {
        for _ in 0 ..< appendedZeroCount {
            bits = bits &* 10
        }
    }

    return value.negative ? 0 &- bits : bits
}

@_cdecl("__kk_bignum_toDouble")
public func __kk_bignum_toDouble(_ numRaw: Int) -> Int {
    let source = runtimeBigDecimalValue(numRaw, caller: #function)
    if parseBigDecimalParts(source).digits.isEmpty {
        return 0
    }
    guard let value = Double(source) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid BigDecimal numeric representation")
    }
    return Int(bitPattern: UInt(value.bitPattern))
}

@_cdecl("__kk_bignum_toFloat")
public func __kk_bignum_toFloat(_ numRaw: Int) -> Int {
    let source = runtimeBigDecimalValue(numRaw, caller: #function)
    if parseBigDecimalParts(source).digits.isEmpty {
        return 0
    }
    guard let value = Float(source) else {
        fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: invalid BigDecimal numeric representation")
    }
    return runtimeFloatBitsToInt(value)
}

@_cdecl("__kk_bignum_toLong")
public func __kk_bignum_toLong(_ numRaw: Int) -> Int {
    Int(truncatingIfNeeded: runtimeBigDecimalIntegerBits(runtimeBigDecimalValue(numRaw, caller: #function)))
}

@_cdecl("__kk_bignum_toInt")
public func __kk_bignum_toInt(_ numRaw: Int) -> Int {
    let bits = runtimeBigDecimalIntegerBits(runtimeBigDecimalValue(numRaw, caller: #function))
    return Int(Int32(bitPattern: UInt32(truncatingIfNeeded: bits)))
}

@_cdecl("__kk_bignum_toShort")
public func __kk_bignum_toShort(_ numRaw: Int) -> Int {
    let bits = runtimeBigDecimalIntegerBits(runtimeBigDecimalValue(numRaw, caller: #function))
    return Int(Int16(bitPattern: UInt16(truncatingIfNeeded: bits)))
}

@_cdecl("__kk_bignum_toByte")
public func __kk_bignum_toByte(_ numRaw: Int) -> Int {
    let bits = runtimeBigDecimalIntegerBits(runtimeBigDecimalValue(numRaw, caller: #function))
    return Int(Int8(bitPattern: UInt8(truncatingIfNeeded: bits)))
}

/// BigDecimal uses a runtime box instead of a compiler-generated class vtable.
func runtimeBigDecimalNumberConversion(_ numRaw: Int, targetKind: Int32) -> Int? {
    guard let pointer = UnsafeMutableRawPointer(bitPattern: numRaw),
          let box = tryCast(pointer, to: RuntimeBigNumberBox.self),
          box.kind == .decimal
    else {
        return nil
    }

    return switch targetKind {
    case 0: __kk_bignum_toDouble(numRaw)
    case 1: __kk_bignum_toFloat(numRaw)
    case 2: __kk_bignum_toLong(numRaw)
    case 3: __kk_bignum_toInt(numRaw)
    case 4: __kk_bignum_toShort(numRaw)
    case 5: __kk_bignum_toByte(numRaw)
    case 6: kk_int_to_char(__kk_bignum_toInt(numRaw))
    default: nil
    }
}

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
