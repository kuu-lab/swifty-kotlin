// String formatting (String.format).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

// MARK: - Format parser internals

private struct RuntimeFormatSpecifier {
    let explicitArgumentIndex: Int?
    let flags: String
    let width: Int?
    let precision: Int?
    let conversion: Character

    var normalizedConversion: Character {
        Character(String(conversion).lowercased())
    }

    /// `%,d` / `%,f`: Kotlin/JVM inserts locale-aware grouping separators.
    /// The C formatter has no equivalent flag, so grouping and the resulting
    /// width padding are applied afterwards on the rendered digits.
    var usesGroupingSeparator: Bool {
        flags.contains(",")
    }

    var usesParenthesesForNegativeValues: Bool {
        flags.contains("(")
    }

    var cStyleToken: String {
        let supportedFlags = flags.filter { "-+ #0".contains($0) }
        var token = "%"
        token += supportedFlags
        if let width, !usesGroupingSeparator, !usesParenthesesForNegativeValues {
            token += String(width)
        }
        if let precision {
            token += ".\(precision)"
        }
        switch normalizedConversion {
        case "d", "i", "x", "o":
            token += "ll"
        default:
            break
        }
        token.append(conversion)
        return token
    }
}

private enum RuntimeParsedFormatToken {
    case escapedPercent(next: Int)
    case newline(next: Int)
    case specifier(RuntimeFormatSpecifier, next: Int)
    case invalid
}

private let runtimeFormatFlagCharacters: Set<Character> = ["-", "+", " ", "0", "#", ",", "("]
private let runtimeFormatLengthCharacters: Set<Character> = ["h", "l", "L", "z", "j", "t"]
private let runtimeSupportedFormatConversions: Set<Character> = [
    "s", "S", "b", "B", "d", "i", "x", "X", "o", "f", "e", "E", "g", "G", "a", "A", "c", "C",
]

private func runtimeFormatString(_ template: String, values arguments: [RuntimeValue], locale: Locale? = nil) -> String {
    let characters = Array(template)
    var cursor = 0
    var implicitArgumentIndex = 0
    var result = ""

    while cursor < characters.count {
        guard characters[cursor] == "%" else {
            result.append(characters[cursor])
            cursor += 1
            continue
        }

        switch runtimeParseFormatToken(characters, start: cursor) {
        case let .escapedPercent(next):
            result.append("%")
            cursor = next
        case let .newline(next):
            result.append("\n")
            cursor = next
        case let .specifier(specifier, next):
            let argumentIndex = specifier.explicitArgumentIndex ?? implicitArgumentIndex
            if specifier.explicitArgumentIndex == nil {
                implicitArgumentIndex += 1
            }
            let argument = arguments.indices.contains(argumentIndex)
                ? arguments[argumentIndex]
                : RuntimeValue(raw: runtimeNullSentinelInt)
            result += runtimeRenderFormattedArgument(argument, specifier: specifier, locale: locale)
            cursor = next
        case .invalid:
            result.append("%")
            cursor += 1
        }
    }

    return result
}

private func runtimeParseFormatToken(_ characters: [Character], start: Int) -> RuntimeParsedFormatToken {
    var cursor = start + 1
    guard cursor < characters.count else {
        return .invalid
    }
    if characters[cursor] == "%" {
        return .escapedPercent(next: cursor + 1)
    }
    if characters[cursor] == "n" {
        return .newline(next: cursor + 1)
    }

    let initialDigitsStart = cursor
    while cursor < characters.count, characters[cursor].isNumber {
        cursor += 1
    }
    var explicitArgumentIndex: Int?
    if cursor < characters.count, characters[cursor] == "$", initialDigitsStart < cursor {
        explicitArgumentIndex = Int(String(characters[initialDigitsStart ..< cursor])).map { $0 - 1 }
        cursor += 1
    } else {
        cursor = initialDigitsStart
    }

    let flagsStart = cursor
    while cursor < characters.count, runtimeFormatFlagCharacters.contains(characters[cursor]) {
        cursor += 1
    }
    let flags = String(characters[flagsStart ..< cursor])

    let widthStart = cursor
    while cursor < characters.count, characters[cursor].isNumber {
        cursor += 1
    }
    let width = widthStart < cursor ? Int(String(characters[widthStart ..< cursor])) : nil

    var precision: Int?
    if cursor < characters.count, characters[cursor] == "." {
        cursor += 1
        let precisionStart = cursor
        while cursor < characters.count, characters[cursor].isNumber {
            cursor += 1
        }
        let precisionDigits = String(characters[precisionStart ..< cursor])
        precision = Int(precisionDigits) ?? 0
    }

    while cursor < characters.count, runtimeFormatLengthCharacters.contains(characters[cursor]) {
        cursor += 1
    }
    guard cursor < characters.count else {
        return .invalid
    }

    let conversion = characters[cursor]
    guard runtimeSupportedFormatConversions.contains(conversion) else {
        return .invalid
    }

    return .specifier(
        RuntimeFormatSpecifier(
            explicitArgumentIndex: explicitArgumentIndex,
            flags: flags,
            width: width,
            precision: precision,
            conversion: conversion
        ),
        next: cursor + 1
    )
}

private func runtimeRenderFormattedArgument(
    _ value: RuntimeValue,
    specifier: RuntimeFormatSpecifier,
    locale: Locale?
) -> String {
    switch specifier.normalizedConversion {
    case "s":
        let rendered = runtimeFormatStringValue(value, specifier: specifier, locale: locale)
        return runtimeApplyStringWidth(rendered, specifier: specifier)
    case "b":
        let value = runtimeFormatBooleanValue(value)
        let normalized = specifier.conversion.isUppercase
            ? runtimeFormatUppercase(value, locale: locale)
            : value
        return runtimeApplyStringWidth(normalized, specifier: specifier)
    case "d", "i":
        let value = Int64(runtimeFormatIntegerValue(value))
        let rendered = String(format: specifier.cStyleToken, arguments: [value])
        return runtimeLocalizeFormattedNumber(
            rendered,
            specifier: specifier,
            locale: locale,
            applyWidth: specifier.usesParenthesesForNegativeValues
        )
    case "x", "o":
        let value = UInt64(bitPattern: Int64(runtimeFormatIntegerValue(value)))
        return String(format: specifier.cStyleToken, arguments: [value])
    case "f", "e", "g", "a":
        let value = runtimeFormatDoubleValue(value)
        let rendered = runtimeRenderFormattedFloatingPoint(value, specifier: specifier)
        if specifier.normalizedConversion == "a" {
            return runtimeApplyNumericWidth(
                runtimeParenthesizeNegativeValue(rendered, specifier: specifier),
                specifier: specifier
            )
        }
        return runtimeLocalizeFormattedNumber(
            rendered,
            specifier: specifier,
            locale: locale,
            applyWidth: true
        )
    case "c":
        let value = runtimeFormatCharacterValue(value)
        let normalized = specifier.conversion.isUppercase
            ? runtimeFormatUppercase(value, locale: locale)
            : value
        return runtimeApplyStringWidth(normalized, specifier: specifier)
    default:
        return runtimeApplyStringWidth(
            runtimeFormatStringValue(value, specifier: specifier, locale: locale),
            specifier: specifier
        )
    }
}

private func runtimeFormatStringValue(
    _ argument: RuntimeValue,
    specifier: RuntimeFormatSpecifier,
    locale: Locale?
) -> String {
    var value = runtimeElementToString(argument)
    if let precision = specifier.precision, value.count > precision {
        value = String(value.prefix(precision))
    }
    if specifier.conversion.isUppercase {
        value = runtimeFormatUppercase(value, locale: locale)
    }
    return value
}

private func runtimeFormatUppercase(_ value: String, locale: Locale?) -> String {
    if let locale {
        return value.uppercased(with: locale)
    }
    return value.uppercased()
}

private func runtimeFormatBooleanValue(_ value: RuntimeValue) -> String {
    if value.tag == RuntimeValue.stringTag {
        return runtimeElementToString(value).isEmpty ? "false" : "true"
    }
    let argument = value.payload0
    if argument == runtimeNullSentinelInt {
        return "false"
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: argument),
       runtimeIsObjectPointer(pointer),
       let boolBox = tryCast(pointer, to: RuntimeBoolBox.self)
    {
        return boolBox.value ? "true" : "false"
    }
    return switch argument {
    case 0:
        "false"
    case 1:
        "true"
    default:
        "true"
    }
}

private func runtimeFormatIntegerValue(_ value: RuntimeValue) -> Int {
    if value.tag == RuntimeValue.stringTag {
        return Int(runtimeElementToString(value)) ?? 0
    }
    return maybeUnbox(value.payload0)
}

private func runtimeFormatDoubleValue(_ value: RuntimeValue) -> Double {
    if value.tag == RuntimeValue.stringTag {
        return Double(runtimeElementToString(value)) ?? 0
    }
    let argument = value.payload0
    if argument == runtimeNullSentinelInt {
        return 0
    }
    if let pointer = UnsafeMutableRawPointer(bitPattern: argument),
       runtimeIsObjectPointer(pointer)
    {
        if let floatBox = tryCast(pointer, to: RuntimeFloatBox.self) {
            return Double(floatBox.value)
        }
        if let doubleBox = tryCast(pointer, to: RuntimeDoubleBox.self) {
            return doubleBox.value
        }
        if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
            return Double(intBox.value)
        }
        if let boolBox = tryCast(pointer, to: RuntimeBoolBox.self) {
            return boolBox.value ? 1 : 0
        }
        if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
            return Double(longBox.value)
        }
        if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
            return Double(UInt(bitPattern: ulongBox.value))
        }
        if let charBox = tryCast(pointer, to: RuntimeCharBox.self) {
            return Double(charBox.value)
        }
        if let stringBox = tryCast(pointer, to: RuntimeStringBox.self) {
            return Double(stringBox.value) ?? 0
        }
    }
    if argument > -0x1_0000_0000, argument < 0x1_0000_0000 {
        return Double(argument)
    }
    return Double(bitPattern: UInt64(bitPattern: Int64(argument)))
}

private struct RuntimeDecimalFloatingPoint {
    let digits: String
    let scale: Int

    var isZero: Bool {
        digits == "0"
    }

    var exponent: Int {
        guard !isZero else { return 0 }
        return digits.count - scale - 1
    }
}

private func runtimeParseDecimalFloatingPoint(_ rendered: String) -> RuntimeDecimalFloatingPoint {
    var value = rendered
    let isNegative = value.hasPrefix("-")
    if isNegative {
        value.removeFirst()
    }

    let exponentIndex = value.firstIndex(of: "E") ?? value.firstIndex(of: "e")
    let mantissa: String
    let exponent: Int
    if let exponentIndex {
        mantissa = String(value[..<exponentIndex])
        exponent = Int(value[value.index(after: exponentIndex)...]) ?? 0
    } else {
        mantissa = value
        exponent = 0
    }

    let parts = mantissa.split(separator: ".", maxSplits: 1, omittingEmptySubsequences: false)
    let integerPart = String(parts.first ?? "")
    let fractionalPart = parts.count > 1 ? String(parts[1]) : ""
    let rawDigits = integerPart + fractionalPart
    let leadingZeros = rawDigits.prefix { $0 == "0" }.count
    let digits = leadingZeros == rawDigits.count
        ? "0"
        : String(rawDigits.dropFirst(leadingZeros))

    // Keep trailing zeroes in the coefficient: they are part of the decimal
    // scale (for example, 1.0 is 10 * 10^-1, not 1 * 10^-1).
    return RuntimeDecimalFloatingPoint(
        digits: digits,
        scale: fractionalPart.count - exponent
    )
}

private func runtimeIncrementDecimalDigits(_ value: String) -> String {
    var digits = Array(value.utf8)
    var index = digits.count
    while index > 0 {
        index -= 1
        if digits[index] == 57 { // ASCII '9'
            digits[index] = 48 // ASCII '0'
        } else {
            digits[index] += 1
            return String(decoding: digits, as: UTF8.self)
        }
    }
    return "1" + String(decoding: digits, as: UTF8.self)
}

/// Divides a non-negative decimal integer by 10^dropCount using HALF_UP.
private func runtimeRoundDecimalInteger(_ value: String, dropping dropCount: Int) -> String {
    guard dropCount > 0 else {
        return value + String(repeating: "0", count: -dropCount)
    }
    if dropCount > value.count {
        return "0"
    }
    if dropCount == value.count {
        return value.first.map { $0 >= "5" ? "1" : "0" } ?? "0"
    }

    let keptCount = value.count - dropCount
    var kept = String(value.prefix(keptCount))
    if value[value.index(value.startIndex, offsetBy: keptCount)] >= "5" {
        kept = runtimeIncrementDecimalDigits(kept)
    }
    return kept
}

private func runtimeRoundedSignificantDigits(
    _ value: RuntimeDecimalFloatingPoint,
    count: Int
) -> (digits: String, exponent: Int) {
    let count = max(1, count)
    guard !value.isZero else {
        return (String(repeating: "0", count: count), 0)
    }

    var exponent = value.exponent
    var digits: String
    if value.digits.count > count {
        digits = runtimeRoundDecimalInteger(value.digits, dropping: value.digits.count - count)
    } else {
        digits = value.digits + String(repeating: "0", count: count - value.digits.count)
    }

    if digits.count > count {
        exponent += 1
        digits = "1" + String(repeating: "0", count: count - 1)
    }
    return (digits, exponent)
}

private func runtimeFloatingPointSign(isNegative: Bool, specifier: RuntimeFormatSpecifier) -> String {
    if isNegative {
        return "-"
    }
    if specifier.flags.contains("+") {
        return "+"
    }
    if specifier.flags.contains(" ") {
        return " "
    }
    return ""
}

private func runtimeScientificExponent(_ exponent: Int) -> String {
    let sign = exponent < 0 ? "-" : "+"
    let magnitude = exponent < 0 ? -exponent : exponent
    let digits = String(magnitude)
    return sign + (digits.count < 2 ? "0" + digits : digits)
}

private func runtimeRenderRoundedFixed(
    digits: String,
    decimalPosition: Int,
    alternateForm: Bool
) -> String {
    let body: String
    if decimalPosition <= 0 {
        body = "0." + String(repeating: "0", count: -decimalPosition) + digits
    } else if decimalPosition >= digits.count {
        body = digits + String(repeating: "0", count: decimalPosition - digits.count)
    } else {
        let splitIndex = digits.index(digits.startIndex, offsetBy: decimalPosition)
        body = String(digits[..<splitIndex]) + "." + String(digits[splitIndex...])
    }

    if alternateForm, !body.contains(".") {
        return body + "."
    }
    return body
}

private func runtimeRenderFormattedFloatingPoint(
    _ value: Double,
    specifier: RuntimeFormatSpecifier
) -> String {
    if value.isNaN {
        return specifier.conversion.isUppercase ? "NAN" : "NaN"
    }

    let shortest = runtimeFormatFloatingPoint(value)
    let isNegative = shortest.hasPrefix("-")
    let unsignedShortest = isNegative ? String(shortest.dropFirst()) : shortest
    let sign = runtimeFloatingPointSign(isNegative: isNegative, specifier: specifier)
    if unsignedShortest == "Infinity" {
        let infinity = specifier.conversion.isUppercase ? "INFINITY" : unsignedShortest
        return sign + infinity
    }

    let decimal = runtimeParseDecimalFloatingPoint(shortest)
    let alternateForm = specifier.flags.contains("#")
    switch specifier.normalizedConversion {
    case "f":
        let precision = specifier.precision ?? 6
        let scaledDigits = runtimeRoundDecimalInteger(
            decimal.digits,
            dropping: decimal.scale - precision
        )
        return sign + runtimeRenderRoundedFixed(
            digits: scaledDigits,
            decimalPosition: scaledDigits.count - precision,
            alternateForm: alternateForm
        )
    case "e":
        let precision = specifier.precision ?? 6
        let rounded = runtimeRoundedSignificantDigits(decimal, count: precision + 1)
        let firstDigit = String(rounded.digits.prefix(1))
        let fractionalDigits = String(rounded.digits.dropFirst())
        let mantissa: String
        if precision == 0, !alternateForm {
            mantissa = firstDigit
        } else {
            mantissa = firstDigit + "." + fractionalDigits
        }
        let exponent = runtimeScientificExponent(rounded.exponent)
        let marker = specifier.conversion == "E" ? "E" : "e"
        return sign + mantissa + marker + exponent
    case "g":
        let precision = max(1, specifier.precision ?? 6)
        let rounded = runtimeRoundedSignificantDigits(decimal, count: precision)
        let useScientific = rounded.exponent < -4 || rounded.exponent >= precision
        if useScientific {
            let firstDigit = String(rounded.digits.prefix(1))
            let fractionalDigits = String(rounded.digits.dropFirst())
            let mantissa: String
            if precision == 1, !alternateForm {
                mantissa = firstDigit
            } else {
                mantissa = firstDigit + "." + fractionalDigits
            }
            let marker = specifier.conversion == "G" ? "E" : "e"
            return sign + mantissa + marker + runtimeScientificExponent(rounded.exponent)
        }

        return sign + runtimeRenderRoundedFixed(
            digits: rounded.digits,
            decimalPosition: rounded.exponent + 1,
            alternateForm: alternateForm
        )
    case "a":
        return sign + runtimeRenderHexFloatingPoint(value.magnitude, specifier: specifier)
    default:
        return sign + unsignedShortest
    }
}

private func runtimeRenderHexFloatingPoint(
    _ value: Double,
    specifier: RuntimeFormatSpecifier
) -> String {
    let bits = value.bitPattern
    let exponentBits = Int((bits >> 52) & 0x7ff)
    let fractionBits = bits & 0x000f_ffff_ffff_ffff
    let uppercase = specifier.conversion == "A"

    let body: String
    if let requestedPrecision = specifier.precision {
        let precision = max(1, requestedPrecision)
        let normalized: (significand: UInt64, exponent: Int)
        if exponentBits == 0 {
            if fractionBits == 0 {
                normalized = (0, 0)
            } else {
                let highestBit = 63 - fractionBits.leadingZeroBitCount
                normalized = (
                    fractionBits << (52 - highestBit),
                    -1074 + highestBit
                )
            }
        } else {
            normalized = ((1 << 52) | fractionBits, exponentBits - 1023)
        }

        var exponent = normalized.exponent
        var fractionalDigits: String
        var leadingDigit: UInt64
        if precision < 13 {
            let retainedFractionBitCount = precision * 4
            let droppedBitCount = 52 - retainedFractionBitCount
            var retained = normalized.significand >> droppedBitCount
            let remainderMask = (UInt64(1) << droppedBitCount) - 1
            let remainder = normalized.significand & remainderMask
            let halfway = UInt64(1) << (droppedBitCount - 1)
            if remainder > halfway || (remainder == halfway && !retained.isMultiple(of: 2)) {
                retained += 1
            }
            if retained == UInt64(1) << (retainedFractionBitCount + 1) {
                retained = UInt64(1) << retainedFractionBitCount
                exponent += 1
            }
            leadingDigit = retained >> retainedFractionBitCount
            let retainedFractionMask = (UInt64(1) << retainedFractionBitCount) - 1
            let retainedFraction = retained & retainedFractionMask
            fractionalDigits = runtimePaddedHexDigits(retainedFraction, count: precision)
        } else {
            leadingDigit = normalized.significand >> 52
            let normalizedFraction = normalized.significand & 0x000f_ffff_ffff_ffff
            fractionalDigits = runtimePaddedHexDigits(normalizedFraction, count: 13)
                + String(repeating: "0", count: precision - 13)
        }
        body = "0x\(String(leadingDigit, radix: 16)).\(fractionalDigits)p\(exponent)"
    } else if exponentBits == 0 {
        if fractionBits == 0 {
            body = "0x0.0p0"
        } else {
            let fraction = runtimeTrimTrailingHexZeros(
                runtimePaddedHexDigits(fractionBits, count: 13)
            )
            body = "0x0.\(fraction)p-1022"
        }
    } else {
        let fraction = runtimeTrimTrailingHexZeros(
            runtimePaddedHexDigits(fractionBits, count: 13)
        )
        body = "0x1.\(fraction.isEmpty ? "0" : fraction)p\(exponentBits - 1023)"
    }

    return uppercase ? body.uppercased() : body
}

private func runtimePaddedHexDigits(_ value: UInt64, count: Int) -> String {
    let digits = String(value, radix: 16)
    return String(repeating: "0", count: max(0, count - digits.count)) + digits
}

private func runtimeTrimTrailingHexZeros(_ value: String) -> String {
    var trimmed = value
    while trimmed.last == "0" {
        trimmed.removeLast()
    }
    return trimmed
}

private func runtimeFormatCharacterValue(_ value: RuntimeValue) -> String {
    let scalarValue = UInt32(truncatingIfNeeded: runtimeFormatIntegerValue(value))
    guard let scalar = UnicodeScalar(scalarValue) else {
        return "?"
    }
    return String(scalar)
}

private func runtimeApplyStringWidth(_ value: String, specifier: RuntimeFormatSpecifier) -> String {
    guard let width = specifier.width, value.count < width else {
        return value
    }
    let padding = String(repeating: " ", count: width - value.count)
    if specifier.flags.contains("-") {
        return value + padding
    }
    return padding + value
}

/// Applies the Kotlin/JVM locale rules to a number rendered with the C default locale:
/// the decimal separator becomes the locale's one, and the `,` flag inserts the locale's
/// grouping separator. Numbers are never grouped without the flag, matching
/// `java.util.Formatter` (and unlike `String(format:locale:)`, which groups by locale).
private func runtimeLocalizeFormattedNumber(
    _ rendered: String,
    specifier: RuntimeFormatSpecifier,
    locale: Locale?,
    applyWidth: Bool = false
) -> String {
    let decimalSeparator = locale?.decimalSeparator ?? "."
    guard specifier.usesGroupingSeparator else {
        let localized = rendered.replacingOccurrences(of: ".", with: decimalSeparator)
        let parenthesized = runtimeParenthesizeNegativeValue(localized, specifier: specifier)
        return applyWidth
            ? runtimeApplyNumericWidth(parenthesized, specifier: specifier)
            : parenthesized
    }
    let groupingSeparator = locale?.groupingSeparator ?? ","

    var characters = Substring(rendered)
    let sign = String(characters.prefix { "-+ ".contains($0) })
    characters = characters.dropFirst(sign.count)
    let digits = String(characters.prefix(while: \.isNumber))
    let remainder = String(characters.dropFirst(digits.count))
        .replacingOccurrences(of: ".", with: decimalSeparator)

    func grouped(_ digits: String) -> String {
        var result = ""
        for (offset, digit) in digits.reversed().enumerated() {
            if offset > 0, offset.isMultiple(of: 3) {
                result = groupingSeparator + result
            }
            result = String(digit) + result
        }
        return result
    }

    // `java.util.Formatter` groups the value digits first and zero-pads afterwards,
    // so the padding zeros themselves stay ungrouped.
    let value = runtimeParenthesizeNegativeValue(
        sign + grouped(digits) + remainder,
        specifier: specifier
    )
    return runtimeApplyNumericWidth(value, specifier: specifier)
}

private func runtimeParenthesizeNegativeValue(
    _ value: String,
    specifier: RuntimeFormatSpecifier
) -> String {
    guard specifier.usesParenthesesForNegativeValues, value.hasPrefix("-") else {
        return value
    }
    return "(" + value.dropFirst() + ")"
}

private func runtimeApplyNumericWidth(_ value: String, specifier: RuntimeFormatSpecifier) -> String {
    guard let width = specifier.width, value.count < width else {
        return value
    }
    let paddingCount = width - value.count
    if specifier.flags.contains("-") {
        return value + String(repeating: " ", count: paddingCount)
    }
    if specifier.flags.contains("0"), runtimeNumericValueAllowsZeroPadding(value) {
        if value.hasPrefix("("), value.hasSuffix(")") {
            return "(" + String(repeating: "0", count: paddingCount) + value.dropFirst().dropLast() + ")"
        }

        let sign = String(value.prefix { "-+ ".contains($0) })
        let unsigned = String(value.dropFirst(sign.count))
        if unsigned.hasPrefix("0x") || unsigned.hasPrefix("0X") {
            return sign + unsigned.prefix(2) + String(repeating: "0", count: paddingCount) + unsigned.dropFirst(2)
        }
        return sign + String(repeating: "0", count: paddingCount) + unsigned
    }
    return String(repeating: " ", count: paddingCount) + value
}

private func runtimeNumericValueAllowsZeroPadding(_ value: String) -> Bool {
    let unwrapped = value
        .trimmingCharacters(in: CharacterSet(charactersIn: "-+ ()"))
        .lowercased()
    return unwrapped != "nan" && unwrapped != "infinity"
}

// MARK: - Public @_cdecl functions: String.format

@_cdecl("__kk_string_format_flat")
public func __kk_string_format_flat(
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ argsArrayRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let template = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.values
        ?? runtimeListBox(from: argsArrayRaw)?.values
        ?? []
    return runtimeRegisterFlatString(
        runtimeFormatString(template, values: arguments),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}

@_cdecl("__kk_string_format_locale")
public func __kk_string_format_locale(_ localeRaw: Int, _ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    let locale: Locale?
    if localeRaw == runtimeNullSentinelInt {
        locale = nil
    } else {
        guard let box = runtimeLocaleBox(from: localeRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_string_format_locale received invalid Locale handle")
        }
        locale = box.locale
    }

    let template = runtimeStringFromRawOrPanic(formatRaw, caller: #function)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.values
        ?? runtimeListBox(from: argsArrayRaw)?.values
        ?? []
    return runtimeMakeStringRaw(runtimeFormatString(template, values: arguments, locale: locale))
}

@_cdecl("__kk_string_format_locale_flat")
public func __kk_string_format_locale_flat(
    _ localeRaw: Int,
    _ data: UnsafePointer<UInt8>?,
    _ length: Int,
    _ byteCount: Int,
    _ hash: Int,
    _ argsArrayRaw: Int,
    _ outLength: UnsafeMutablePointer<Int>?,
    _ outByteCount: UnsafeMutablePointer<Int>?,
    _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let locale: Locale?
    if localeRaw == runtimeNullSentinelInt {
        locale = nil
    } else {
        guard let box = runtimeLocaleBox(from: localeRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: __kk_string_format_locale_flat received invalid Locale handle")
        }
        locale = box.locale
    }
    let template = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.values
        ?? runtimeListBox(from: argsArrayRaw)?.values
        ?? []
    return runtimeRegisterFlatString(
        runtimeFormatString(template, values: arguments, locale: locale),
        outLength: outLength,
        outByteCount: outByteCount,
        outHash: outHash
    )
}
