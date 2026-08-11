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

    var cStyleToken: String {
        let supportedFlags = flags.filter { "-+ #0".contains($0) }
        var token = "%"
        token += supportedFlags
        if let width, !usesGroupingSeparator {
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

private let runtimeFormatFlagCharacters: Set<Character> = ["-", "+", " ", "0", "#", ","]
private let runtimeFormatLengthCharacters: Set<Character> = ["h", "l", "L", "z", "j", "t"]
private let runtimeSupportedFormatConversions: Set<Character> = [
    "s", "S", "b", "B", "d", "i", "x", "X", "o", "f", "e", "E", "g", "G", "c", "C",
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
        return runtimeLocalizeFormattedNumber(rendered, specifier: specifier, locale: locale)
    case "x", "o":
        let value = UInt64(bitPattern: Int64(runtimeFormatIntegerValue(value)))
        return String(format: specifier.cStyleToken, arguments: [value])
    case "f", "e", "g":
        let value = runtimeFormatDoubleValue(value)
        let rendered = String(format: specifier.cStyleToken, arguments: [value])
        return runtimeLocalizeFormattedNumber(rendered, specifier: specifier, locale: locale)
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
    locale: Locale?
) -> String {
    let decimalSeparator = locale?.decimalSeparator ?? "."
    guard specifier.usesGroupingSeparator else {
        return rendered.replacingOccurrences(of: ".", with: decimalSeparator)
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
    let value = sign + grouped(digits) + remainder
    let zeroPads = specifier.flags.contains("0") && !specifier.flags.contains("-")
    if let width = specifier.width, zeroPads, value.count < width {
        return sign + String(repeating: "0", count: width - value.count)
            + grouped(digits) + remainder
    }
    return runtimeApplyStringWidth(value, specifier: specifier)
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
