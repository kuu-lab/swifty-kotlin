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
    /// Java date/time suffix after `%t`/`%T` (`Y`, `m`, `Q`, …). Nil for other conversions.
    let dateTimeConversion: Character?

    var normalizedConversion: Character {
        Character(String(conversion).lowercased())
    }

    /// `%,d` / `%,f`: Kotlin/JVM inserts locale-aware grouping separators.
    /// The C formatter has no equivalent flag, so grouping and the resulting
    /// width padding are applied afterwards on the rendered digits.
    var usesGroupingSeparator: Bool {
        flags.contains(",")
    }

    /// Java `Formatter` `<` flag: reuse the argument of the previous specifier.
    var reusesPreviousArgument: Bool {
        flags.contains("<")
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
        case "d", "x", "o":
            token += "ll"
        default:
            break
        }
        token.append(conversion)
        return token
    }
}

private enum RuntimeParsedFormatToken {
    case specifier(RuntimeFormatSpecifier, next: Int)
}

// MARK: - Resource limits for String.format (KUU-804)
// Prevents memory exhaustion and arithmetic traps on maliciously large width/precision.
internal let runtimeFormatMaxWidth = 100_000
internal let runtimeFormatMaxPrecision = 100_000
internal let runtimeFormatMaxArgumentIndex = 100_000
internal let runtimeFormatMaxOutputBudget = 100_000

private let runtimeFormatFlagCharacters: Set<Character> = ["-", "+", " ", "0", "#", ",", "(", "<"]
private let runtimeSupportedFormatConversions: Set<Character> = [
    "s", "S", "b", "B", "d", "x", "X", "o", "f", "e", "E", "g", "G", "a", "A", "c", "C",
    "h", "H", "t", "T", "%", "n",
]
/// Java `Formatter` date/time conversion suffixes. These are case-sensitive
/// (`Y` vs `y`, `H` vs `h`).
private let runtimeSupportedDateTimeConversions: Set<Character> = [
    "H", "I", "k", "l", "M", "S", "L", "N", "p", "z", "Z", "s", "Q",
    "B", "b", "h", "A", "a", "C", "Y", "y", "j", "m", "d", "e",
    "R", "T", "r", "D", "F", "c",
]

private func runtimeValidateFormatSpecifier(_ specifier: RuntimeFormatSpecifier) throws {
    func fail(_ kind: String) throws {
        throw RuntimeFormatError(kind: kind, message: "Invalid format: %\(specifier.flags)\(specifier.conversion)")
    }
    let flags = Set(specifier.flags)
    if flags.count != specifier.flags.count { try fail("DuplicateFormatFlagsException") }
    let conversion = specifier.normalizedConversion
    let numeric = "doxfega".contains(conversion)
    if !numeric && specifier.precision != nil && "ct%n".contains(conversion) {
        try fail("IllegalFormatPrecisionException")
    }
    if conversion == "n" {
        if specifier.width != nil { try fail("IllegalFormatWidthException") }
        if !flags.isEmpty { try fail("IllegalFormatFlagsException") }
        return
    }
    if numeric && (flags.contains("-") || flags.contains("0")) && specifier.width == nil {
        try fail("MissingFormatWidthException")
    }
    if numeric && (flags.isSuperset(of: ["+", " "]) || flags.isSuperset(of: ["-", "0"])) {
        try fail("IllegalFormatFlagsException")
    }
    if numeric && specifier.precision != nil && "dox".contains(conversion) {
        try fail("IllegalFormatPrecisionException")
    }
    let allowed: String
    switch conversion {
    case "s": allowed = "-#<"
    case "b", "h", "c", "t": allowed = "-<"
    case "d": allowed = "-+ 0,(<"
    case "o", "x": allowed = "-#0<"
    case "f": allowed = "-+ 0#,(<"
    case "e": allowed = "-+ 0#(<"
    case "g": allowed = "-+ 0,(<"
    case "a": allowed = "-+ 0#<"
    case "%": allowed = "-"
    default: allowed = ""
    }
    if flags.contains(where: { !allowed.contains($0) }) {
        try fail(conversion == "%" ? "IllegalFormatFlagsException" : "FormatFlagsConversionMismatchException")
    }
    if !numeric && flags.contains("-") && specifier.width == nil {
        try fail("MissingFormatWidthException")
    }
}

private func runtimeValidateFormatArgument(_ value: RuntimeValue, specifier: RuntimeFormatSpecifier) throws {
    let conversion = specifier.normalizedConversion
    if conversion == "s", specifier.flags.contains("#") {
        // Formattable is not supported; all current arguments use ordinary %s.
        throw RuntimeFormatError(kind: "FormatFlagsConversionMismatchException", message: "# with s")
    }
    if runtimeFormatArgumentIsNull(value) { return }
    if "sbh".contains(conversion) { return }
    var integral = value.tag == RuntimeValue.rawTag
    var character = value.tag == RuntimeValue.charTag
    var floating = false
    var dateTime = false
    if value.tag == RuntimeValue.rawTag,
       let pointer = UnsafeMutableRawPointer(bitPattern: value.payload0), runtimeIsObjectPointer(pointer) {
        integral = tryCast(pointer, to: RuntimeIntBox.self) != nil || tryCast(pointer, to: RuntimeLongBox.self) != nil
        character = tryCast(pointer, to: RuntimeCharBox.self) != nil
        floating = tryCast(pointer, to: RuntimeFloatBox.self) != nil || tryCast(pointer, to: RuntimeDoubleBox.self) != nil
        dateTime = tryCast(pointer, to: RuntimeLongBox.self) != nil
            || tryCast(pointer, to: RuntimeInstantBox.self) != nil || tryCast(pointer, to: RuntimeJSDateBox.self) != nil
        // Java's %c accepts Byte/Short/Int, but not Long.
        if conversion == "c", tryCast(pointer, to: RuntimeLongBox.self) != nil { integral = false }
    } else if value.tag == RuntimeValue.rawTag {
        // Preserve unboxed legacy Runtime callers; Kotlin Any? values are boxed.
        dateTime = true
        floating = true
    }
    let valid: Bool
    switch conversion {
    case "d", "o", "x": valid = integral
    case "f", "e", "g", "a": valid = floating
    case "c": valid = integral || character
    case "t": valid = dateTime
    default: valid = true
    }
    if !valid {
        throw RuntimeFormatError(kind: "IllegalFormatConversionException", message: "Invalid argument for \(specifier.conversion)")
    }
    if conversion == "c" {
        let codePoint = runtimeFormatIntegerValue(value)
        if codePoint < 0 || codePoint > 0x10ffff {
            throw RuntimeFormatError(kind: "IllegalFormatCodePointException", message: String(codePoint))
        }
    }
}

private func runtimeFormatString(_ template: String, values arguments: [RuntimeValue], locale: Locale? = nil) throws -> String {
    let characters = Array(template)
    // Formatter validates the entire template before consuming any arguments.
    var validationCursor = 0
    while validationCursor < characters.count {
        if characters[validationCursor] == "%" {
            if case let .specifier(specifier, next) = try runtimeParseFormatToken(characters, start: validationCursor) {
                try runtimeValidateFormatSpecifier(specifier)
                validationCursor = next
            }
        } else {
            validationCursor += 1
        }
    }
    var cursor = 0
    var implicitArgumentIndex = 0
    /// Index of the argument selected by the most recent specifier
    /// (`java.util.Formatter`'s `last`), reused by the `<` flag.
    var lastArgumentIndex: Int?
    var result = ""
    var remainingBudget = runtimeFormatMaxOutputBudget
    var outputStopped = false

    while cursor < characters.count {
        guard characters[cursor] == "%" else {
            let ch = characters[cursor]
            let byteCount = ch.utf8.count
            if byteCount > remainingBudget { outputStopped = true }
            if !outputStopped {
                result.append(ch)
                remainingBudget -= byteCount
            }
            cursor += 1
            continue
        }

        switch try runtimeParseFormatToken(characters, start: cursor) {
        case let .specifier(specifier, next):
            if specifier.conversion == "%" || specifier.conversion == "n" {
                let rendered = specifier.conversion == "n" ? "\n" : runtimeApplyStringWidth("%", specifier: specifier)
                if rendered.utf8.count > remainingBudget { outputStopped = true }
                if !outputStopped {
                    result += rendered
                    remainingBudget -= rendered.utf8.count
                }
                cursor = next
                continue
            }
            // The `<` flag overrides an explicit `%n$` index and relative
            // indexing does not consume the ordinary (implicit) index,
            // matching `java.util.Formatter`.
            let argumentIndex: Int?
            if specifier.reusesPreviousArgument {
                argumentIndex = lastArgumentIndex
            } else if let explicitArgumentIndex = specifier.explicitArgumentIndex {
                argumentIndex = explicitArgumentIndex
            } else {
                argumentIndex = implicitArgumentIndex
                implicitArgumentIndex += 1
            }
            if let argumentIndex {
                lastArgumentIndex = argumentIndex
            }
            let argument: RuntimeValue
            if let argumentIndex, arguments.indices.contains(argumentIndex) {
                argument = arguments[argumentIndex]
            } else {
                throw RuntimeFormatError(kind: "MissingFormatArgumentException", message: String(characters[cursor ..< next]))
            }
            try runtimeValidateFormatArgument(argument, specifier: specifier)
            if outputStopped {
                cursor = next
                continue
            }
            let rendered = runtimeFormatArgumentIsNull(argument) && specifier.normalizedConversion != "b"
                ? runtimeApplyStringWidth(runtimeFormatStringValue(argument, specifier: specifier, locale: locale), specifier: specifier)
                : runtimeRenderFormattedArgument(argument, specifier: specifier, locale: locale)
            let renderedBytes = rendered.utf8.count
            guard renderedBytes <= remainingBudget else {
                outputStopped = true
                cursor = next
                continue
            }
            result += rendered
            remainingBudget -= renderedBytes
            cursor = next
        }
    }

    return result
}

private func runtimeParseFormatToken(_ characters: [Character], start: Int) throws -> RuntimeParsedFormatToken {
    var cursor = start + 1
    guard cursor < characters.count else {
        throw RuntimeFormatError(kind: "UnknownFormatConversionException", message: "Invalid format conversion")
    }

    let initialDigitsStart = cursor
    while cursor < characters.count, characters[cursor].isNumber {
        cursor += 1
    }
    var explicitArgumentIndex: Int?
    if cursor < characters.count, characters[cursor] == "$", initialDigitsStart < cursor {
        let indexString = String(characters[initialDigitsStart ..< cursor])
        guard let index = Int(indexString), index > 0, index <= runtimeFormatMaxArgumentIndex else {
            throw RuntimeFormatError(kind: "IllegalFormatArgumentIndexException", message: indexString)
        }
        explicitArgumentIndex = index - 1
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
    var width: Int?
    if widthStart < cursor {
        let widthString = String(characters[widthStart ..< cursor])
        guard let parsedWidth = Int(widthString), parsedWidth >= 0, parsedWidth <= runtimeFormatMaxWidth else {
            throw RuntimeFormatError(kind: "IllegalFormatWidthException", message: widthString)
        }
        width = parsedWidth
    }

    var precision: Int?
    if cursor < characters.count, characters[cursor] == "." {
        cursor += 1
        let precisionStart = cursor
        while cursor < characters.count, characters[cursor].isNumber {
            cursor += 1
        }
        if precisionStart < cursor {
            let precisionDigits = String(characters[precisionStart ..< cursor])
            guard let parsedPrecision = Int(precisionDigits),
                  parsedPrecision >= 0,
                  parsedPrecision <= runtimeFormatMaxPrecision else {
                throw RuntimeFormatError(kind: "IllegalFormatPrecisionException", message: precisionDigits)
            }
            precision = parsedPrecision
        } else {
            throw RuntimeFormatError(kind: "UnknownFormatConversionException", message: ".")
        }
    }

    // Java Formatter has no C-style length modifiers. Do not consume `h`/`t`
    // here: they are conversions (`%h` hash, `%t*` date/time), not lengths.
    guard cursor < characters.count else {
        throw RuntimeFormatError(kind: "UnknownFormatConversionException", message: "Invalid format conversion")
    }

    let conversion = characters[cursor]
    guard runtimeSupportedFormatConversions.contains(conversion) else {
        throw RuntimeFormatError(kind: "UnknownFormatConversionException", message: "Invalid format conversion")
    }
    var next = cursor + 1
    var dateTimeConversion: Character?
    if conversion == "t" || conversion == "T" {
        guard next < characters.count else {
            throw RuntimeFormatError(kind: "UnknownFormatConversionException", message: "Invalid format conversion")
        }
        let suffix = characters[next]
        guard runtimeSupportedDateTimeConversions.contains(suffix) else {
            throw RuntimeFormatError(kind: "UnknownFormatConversionException", message: "Invalid format conversion")
        }
        dateTimeConversion = suffix
        next += 1
    }

    return .specifier(
        RuntimeFormatSpecifier(
            explicitArgumentIndex: explicitArgumentIndex,
            flags: flags,
            width: width,
            precision: precision,
            conversion: conversion,
            dateTimeConversion: dateTimeConversion
        ),
        next: next
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
        let boolean = runtimeFormatBooleanValue(value)
        let value = specifier.precision.map { String(boolean.prefix($0)) } ?? boolean
        let normalized = specifier.conversion.isUppercase
            ? runtimeFormatUppercase(value, locale: locale)
            : value
        return runtimeApplyStringWidth(normalized, specifier: specifier)
    case "d":
        let value = Int64(runtimeFormatIntegerValue(value))
        let rendered = String(format: specifier.cStyleToken, arguments: [value])
        return runtimeLocalizeFormattedNumber(
            rendered,
            specifier: specifier,
            locale: locale,
            applyWidth: specifier.usesParenthesesForNegativeValues
        )
    case "x", "o":
        let value = runtimeFormatIntegerBitPattern(value)
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
    case "h":
        return runtimeFormatHashConversion(value, specifier: specifier)
    case "t":
        return runtimeFormatDateTimeConversion(value, specifier: specifier, locale: locale)
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
    if let precision = specifier.precision {
        // Java/Kotlin Formatter %s precision is a UTF-16 code-unit cap
        // (`String.substring(0, precision)`), including unpaired surrogates.
        // Swift `String.count`/`prefix` count grapheme clusters, which would
        // keep a supplementary character or combining sequence intact.
        let units = runtimeKotlinStringUTF16CodeUnits(value)
        if units.count > precision {
            value = runtimeKotlinStringFromUTF16CodeUnits(Array(units.prefix(precision)))
        }
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
        return "true"
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
    return "true"
}

private func runtimeFormatIntegerValue(_ value: RuntimeValue) -> Int {
    if value.tag == RuntimeValue.stringTag {
        return Int(runtimeElementToString(value)) ?? 0
    }
    return maybeUnbox(value.payload0)
}

private func runtimeFormatIntegerBitPattern(_ value: RuntimeValue) -> UInt64 {
    guard value.tag != RuntimeValue.stringTag else {
        return UInt64(bitPattern: Int64(runtimeFormatIntegerValue(value)))
    }

    let argument = value.payload0
    if let pointer = UnsafeMutableRawPointer(bitPattern: argument),
       runtimeIsObjectPointer(pointer)
    {
        if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
            let intValue = Int32(truncatingIfNeeded: intBox.value)
            return UInt64(UInt32(bitPattern: intValue))
        }
        if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
            return UInt64(bitPattern: Int64(longBox.value))
        }
        if let ulongBox = tryCast(pointer, to: RuntimeULongBox.self) {
            return UInt64(bitPattern: Int64(ulongBox.value))
        }
    }

    // Legacy raw callers do not carry a source-width tag. Preserve their
    // existing 64-bit behavior while boxed Kotlin Int and Long stay distinct.
    return UInt64(bitPattern: Int64(maybeUnbox(argument)))
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
        let (count, overflow) = precision.addingReportingOverflow(1)
        let safeCount = overflow ? precision : count
        let rounded = runtimeRoundedSignificantDigits(decimal, count: safeCount)
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
    return runtimeCharacterFromRaw(Int(scalarValue))
}

private func runtimeApplyStringWidth(_ value: String, specifier: RuntimeFormatSpecifier) -> String {
    guard let width = specifier.width, runtimeKotlinStringUTF16Length(value) < width else {
        return value
    }
    let padding = String(repeating: " ", count: width - runtimeKotlinStringUTF16Length(value))
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
    guard let width = specifier.width, runtimeKotlinStringUTF16Length(value) < width else {
        return value
    }
    let paddingCount = width - runtimeKotlinStringUTF16Length(value)
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

// MARK: - %h / %H (hex hashCode)

private func runtimeFormatArgumentIsNull(_ value: RuntimeValue) -> Bool {
    switch value.tag {
    case RuntimeValue.stringTag, RuntimeValue.charTag:
        return false
    default:
        return value.payload0 == runtimeNullSentinelInt
    }
}

/// `%h` / `%t` print width-padded `"null"`; precision is not applied to the literal.
private func runtimeRenderOrNull(
    _ value: RuntimeValue,
    specifier: RuntimeFormatSpecifier,
    render: () -> String
) -> String {
    let rendered = runtimeFormatArgumentIsNull(value) ? "null" : render()
    return runtimeApplyStringWidth(rendered, specifier: specifier)
}

private func runtimeFormatHashCode(_ value: RuntimeValue) -> Int {
    switch value.tag {
    case RuntimeValue.stringTag:
        return Int(runtimeKotlinStringUTF16CodeUnits(runtimeElementToString(value)).reduce(Int32(0)) { partial, unit in
            31 &* partial &+ Int32(unit)
        })
    case RuntimeValue.charTag:
        return value.payload0
    default:
        return kk_any_hashCode(value.payload0, 0)
    }
}

/// `Integer.toHexString(arg.hashCode())`, matching `java.util.Formatter` `%h`.
private func runtimeFormatHashConversion(
    _ value: RuntimeValue,
    specifier: RuntimeFormatSpecifier
) -> String {
    runtimeRenderOrNull(value, specifier: specifier) {
        let hash32 = UInt32(bitPattern: Int32(truncatingIfNeeded: runtimeFormatHashCode(value)))
        let hex = String(hash32, radix: 16)
        let rendered = if let precision = specifier.precision {
            String(hex.prefix(precision))
        } else {
            hex
        }
        return specifier.conversion.isUppercase ? rendered.uppercased() : rendered
    }
}

// MARK: - %t / %T date-time conversions

private struct RuntimeFormatDateTimeInstant {
    let epochMilliseconds: Int64
    let nanoOfSecond: Int32

    init(epochMilliseconds: Int64, nanoOfSecond: Int32) {
        self.epochMilliseconds = epochMilliseconds
        self.nanoOfSecond = nanoOfSecond
    }

    init(epochSeconds: Int64, nanoOfSecond: Int32) {
        let millis = epochSeconds &* 1000 &+ Int64(nanoOfSecond) / 1_000_000
        self.init(epochMilliseconds: millis, nanoOfSecond: nanoOfSecond)
    }

    init(epochMilliseconds millis: Int64) {
        let millisOfSecond = Int32(((millis % 1000) + 1000) % 1000)
        self.init(epochMilliseconds: millis, nanoOfSecond: millisOfSecond * 1_000_000)
    }
}

private func runtimeFormatDateTimeInstant(_ value: RuntimeValue) -> RuntimeFormatDateTimeInstant {
    if value.tag == RuntimeValue.stringTag || value.tag == RuntimeValue.charTag {
        return RuntimeFormatDateTimeInstant(epochMilliseconds: 0, nanoOfSecond: 0)
    }
    let raw = value.payload0
    if let pointer = UnsafeMutableRawPointer(bitPattern: raw), runtimeIsObjectPointer(pointer) {
        if let instant = tryCast(pointer, to: RuntimeInstantBox.self) {
            return RuntimeFormatDateTimeInstant(
                epochSeconds: instant.epochSeconds,
                nanoOfSecond: instant.nanoOfSecond
            )
        }
        if let date = tryCast(pointer, to: RuntimeJSDateBox.self) {
            return RuntimeFormatDateTimeInstant(epochMilliseconds: Int64(date.epochMilliseconds))
        }
        if let longBox = tryCast(pointer, to: RuntimeLongBox.self) {
            return RuntimeFormatDateTimeInstant(epochMilliseconds: Int64(longBox.value))
        }
        if let intBox = tryCast(pointer, to: RuntimeIntBox.self) {
            return RuntimeFormatDateTimeInstant(epochMilliseconds: Int64(intBox.value))
        }
    }
    return RuntimeFormatDateTimeInstant(epochMilliseconds: Int64(maybeUnbox(raw)))
}

private func runtimeFormatDateTimeConversion(
    _ value: RuntimeValue,
    specifier: RuntimeFormatSpecifier,
    locale: Locale?
) -> String {
    runtimeRenderOrNull(value, specifier: specifier) {
        guard let suffix = specifier.dateTimeConversion else {
            return "%t"
        }
        let dateLocale = locale ?? .current
        let rendered = runtimeRenderDateTime(
            runtimeFormatDateTimeInstant(value),
            conversion: suffix,
            locale: dateLocale
        )
        return specifier.conversion.isUppercase
            ? rendered.uppercased(with: dateLocale)
            : rendered
    }
}

private func runtimeRenderDateTime(
    _ instant: RuntimeFormatDateTimeInstant,
    conversion: Character,
    locale: Locale
) -> String {
    let date = Date(timeIntervalSince1970: TimeInterval(instant.epochMilliseconds) / 1000.0)
    var calendar = Calendar(identifier: .gregorian)
    calendar.timeZone = .current
    calendar.locale = locale
    let components = calendar.dateComponents(
        [.year, .month, .day, .hour, .minute, .second],
        from: date
    )

    func pad(_ value: Int, _ width: Int) -> String {
        let digits = String(abs(value))
        let padding = String(repeating: "0", count: max(0, width - digits.count))
        return (value < 0 ? "-" : "") + padding + digits
    }

    let formatter = DateFormatter()
    formatter.locale = locale
    formatter.timeZone = calendar.timeZone
    formatter.calendar = calendar
    func symbol(_ format: String) -> String {
        formatter.dateFormat = format
        return formatter.string(from: date)
    }

    let year = components.year ?? 0
    let month = components.month ?? 1
    let day = components.day ?? 1
    let hour24 = components.hour ?? 0
    let minute = components.minute ?? 0
    let second = components.second ?? 0
    let hour12 = (hour24 == 0 || hour24 == 12) ? 12 : hour24 % 12

    func field(_ conversion: Character) -> String {
        switch conversion {
        case "H":
            return pad(hour24, 2)
        case "I":
            return pad(hour12, 2)
        case "k":
            return String(hour24)
        case "l":
            return String(hour12)
        case "M":
            return pad(minute, 2)
        case "S":
            return pad(second, 2)
        case "L":
            return pad(Int(instant.nanoOfSecond) / 1_000_000, 3)
        case "N":
            return pad(Int(instant.nanoOfSecond), 9)
        case "p":
            return symbol("a").lowercased(with: locale)
        case "z":
            let seconds = calendar.timeZone.secondsFromGMT(for: date)
            let sign = seconds < 0 ? "-" : "+"
            let absolute = abs(seconds)
            return sign + pad((absolute / 3600) * 100 + (absolute % 3600) / 60, 4)
        case "Z":
            return calendar.timeZone.abbreviation(for: date) ?? symbol("z")
        case "s":
            return String(instant.epochMilliseconds / 1000)
        case "Q":
            return String(instant.epochMilliseconds)
        case "B":
            return symbol("MMMM")
        case "b", "h":
            return symbol("MMM")
        case "A":
            return symbol("EEEE")
        case "a":
            return symbol("EEE")
        case "C":
            return pad(year / 100, 2)
        case "Y":
            return pad(year, 4)
        case "y":
            return pad(year % 100, 2)
        case "j":
            // `Calendar.dayOfYear` is macOS 15+; ordinality is available on macOS 12.
            let dayOfYear = calendar.ordinality(of: .day, in: .year, for: date) ?? 1
            return pad(dayOfYear, 3)
        case "m":
            return pad(month, 2)
        case "d":
            return pad(day, 2)
        case "e":
            return String(day)
        case "R":
            return field("H") + ":" + field("M")
        case "T":
            return field("R") + ":" + field("S")
        case "r":
            return field("I") + ":" + field("M") + ":" + field("S")
                + " " + symbol("a").uppercased(with: locale)
        case "D":
            return field("m") + "/" + field("d") + "/" + field("y")
        case "F":
            return field("Y") + "-" + field("m") + "-" + field("d")
        case "c":
            return [field("a"), field("b"), field("d"), field("T"), field("Z"), field("Y")]
                .joined(separator: " ")
        default:
            return ""
        }
    }

    return field(conversion)
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
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let template = runtimeStringFromFlatFields(data: data, length: length, byteCount: byteCount, hash: hash)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.values
        ?? runtimeListBox(from: argsArrayRaw)?.values
        ?? []
    outThrown?.pointee = 0
    do {
        return runtimeRegisterFlatString(
            try runtimeFormatString(template, values: arguments),
            outLength: outLength,
            outByteCount: outByteCount,
            outHash: outHash
        )
    } catch let error as RuntimeFormatError {
        outThrown?.pointee = runtimeAllocateFormatException(error)
        outLength?.pointee = 0
        outByteCount?.pointee = 0
        outHash?.pointee = 0
        return nil
    } catch {
        preconditionFailure("Unexpected format error")
    }
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
    _ outHash: UnsafeMutablePointer<Int>?,
    _ outThrown: UnsafeMutablePointer<Int>?
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
    outThrown?.pointee = 0
    do {
        return runtimeRegisterFlatString(
            try runtimeFormatString(template, values: arguments, locale: locale),
            outLength: outLength,
            outByteCount: outByteCount,
            outHash: outHash
        )
    } catch let error as RuntimeFormatError {
        outThrown?.pointee = runtimeAllocateFormatException(error)
        outLength?.pointee = 0
        outByteCount?.pointee = 0
        outHash?.pointee = 0
        return nil
    } catch {
        preconditionFailure("Unexpected format error")
    }
}
