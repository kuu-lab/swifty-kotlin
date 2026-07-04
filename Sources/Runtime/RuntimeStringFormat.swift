// String formatting (String.format) and indentation operations
// (trimIndent, trimMargin, prependIndent, replaceIndent).
// Split out from `RuntimeStringStdlib.swift`.

import Foundation

// MARK: - Private indent helpers

func runtimeNormalizedMultilineString(_ source: String) -> [String] {
    source
        .replacingOccurrences(of: "\r\n", with: "\n")
        .replacingOccurrences(of: "\r", with: "\n")
        .split(separator: "\n", omittingEmptySubsequences: false)
        .map(String.init)
}

private func runtimeTrimBlankEdges(_ lines: [String]) -> ArraySlice<String> {
    var start = lines.startIndex
    var end = lines.endIndex
    while start < end, lines[start].trimmingCharacters(in: .whitespaces).isEmpty {
        start += 1
    }
    while end > start, lines[end - 1].trimmingCharacters(in: .whitespaces).isEmpty {
        end -= 1
    }
    return lines[start ..< end]
}

private func runtimeLeadingIndentCount(_ line: String) -> Int {
    line.prefix { $0 == " " || $0 == "\t" }.count
}

private func runtimeTrimIndent(_ source: String) -> String {
    let lines = Array(runtimeTrimBlankEdges(runtimeNormalizedMultilineString(source)))
    guard !lines.isEmpty else {
        return ""
    }
    let minimumIndent = lines
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map(runtimeLeadingIndentCount)
        .min() ?? 0
    return lines.map { line in
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ""
        }
        return String(line.dropFirst(minimumIndent))
    }.joined(separator: "\n")
}

private func runtimeTrimMargin(_ source: String, marginPrefix: String) -> String {
    let lines = Array(runtimeTrimBlankEdges(runtimeNormalizedMultilineString(source)))
    guard !lines.isEmpty else {
        return ""
    }
    return lines.map { line in
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix(marginPrefix) else {
            return line
        }
        return String(trimmedLeading.dropFirst(marginPrefix.count))
    }.joined(separator: "\n")
}

private func runtimePrependIndent(_ source: String, indent: String) -> String {
    let lines = runtimeNormalizedMultilineString(source)
    return lines.map { indent + $0 }.joined(separator: "\n")
}

private func runtimeReplaceIndent(_ source: String, newIndent: String) -> String {
    let lines = Array(runtimeTrimBlankEdges(runtimeNormalizedMultilineString(source)))
    guard !lines.isEmpty else {
        return ""
    }
    let minimumIndent = lines
        .filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
        .map(runtimeLeadingIndentCount)
        .min() ?? 0
    return lines.map { line in
        guard !line.trimmingCharacters(in: .whitespaces).isEmpty else {
            return ""
        }
        return newIndent + String(line.dropFirst(minimumIndent))
    }.joined(separator: "\n")
}

private func runtimeReplaceIndentByMargin(
    _ source: String,
    newIndent: String,
    marginPrefix: String
) -> String {
    let lines = Array(runtimeTrimBlankEdges(runtimeNormalizedMultilineString(source)))
    guard !lines.isEmpty else {
        return ""
    }
    return lines.map { line in
        let trimmedLeading = line.drop { $0 == " " || $0 == "\t" }
        guard trimmedLeading.hasPrefix(marginPrefix) else {
            return line
        }
        return newIndent + String(trimmedLeading.dropFirst(marginPrefix.count))
    }.joined(separator: "\n")
}

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

    var cStyleToken: String {
        let supportedFlags = flags.filter { "-+ #0".contains($0) }
        var token = "%"
        token += supportedFlags
        if let width {
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

private let runtimeFormatFlagCharacters: Set<Character> = ["-", "+", " ", "0", "#"]
private let runtimeFormatLengthCharacters: Set<Character> = ["h", "l", "L", "z", "j", "t"]
private let runtimeSupportedFormatConversions: Set<Character> = [
    "s", "S", "b", "B", "d", "i", "x", "X", "o", "f", "e", "E", "g", "G", "c", "C",
]

private func runtimeFormatString(_ template: String, arguments: [Int], locale: Locale? = nil) -> String {
    runtimeFormatString(template, values: arguments.map { RuntimeValue(raw: $0) }, locale: locale)
}

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
        if let locale {
            return String(format: specifier.cStyleToken, locale: locale, arguments: [value])
        }
        return String(format: specifier.cStyleToken, arguments: [value])
    case "x", "o":
        let value = UInt64(bitPattern: Int64(runtimeFormatIntegerValue(value)))
        if let locale {
            return String(format: specifier.cStyleToken, locale: locale, arguments: [value])
        }
        return String(format: specifier.cStyleToken, arguments: [value])
    case "f", "e", "g":
        let value = runtimeFormatDoubleValue(value)
        if let locale {
            return String(format: specifier.cStyleToken, locale: locale, arguments: [value])
        }
        return String(format: specifier.cStyleToken, arguments: [value])
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

// MARK: - Public @_cdecl functions: String.format

@_cdecl("kk_string_format")
public func kk_string_format(_ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    let template = runtimeStringFromRawOrPanic(formatRaw, caller: #function)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.values
        ?? runtimeListBox(from: argsArrayRaw)?.values
        ?? []
    return runtimeMakeStringRaw(runtimeFormatString(template, values: arguments))
}

@_cdecl("kk_string_format_flat")
public func kk_string_format_flat(
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

@_cdecl("kk_string_format_locale")
public func kk_string_format_locale(_ localeRaw: Int, _ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    let locale: Locale?
    if localeRaw == runtimeNullSentinelInt {
        locale = nil
    } else {
        guard let box = runtimeLocaleBox(from: localeRaw) else {
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_string_format_locale received invalid Locale handle")
        }
        locale = box.locale
    }

    let template = runtimeStringFromRawOrPanic(formatRaw, caller: #function)
    let arguments = runtimeArrayBox(from: argsArrayRaw)?.values
        ?? runtimeListBox(from: argsArrayRaw)?.values
        ?? []
    return runtimeMakeStringRaw(runtimeFormatString(template, values: arguments, locale: locale))
}

@_cdecl("kk_string_format_locale_flat")
public func kk_string_format_locale_flat(
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
            fatalError("KSwiftK panic [\(runtimePanicDiagnosticCode)]: kk_string_format_locale_flat received invalid Locale handle")
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

// MARK: - Public @_cdecl functions: Indent operations

@_cdecl("kk_string_trimIndent")
public func kk_string_trimIndent(_ strRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    return runtimeMakeStringRaw(runtimeTrimIndent(source))
}

@_cdecl("kk_string_trimMargin_default")
public func kk_string_trimMargin_default(_ strRaw: Int) -> Int {
    kk_string_trimMargin(strRaw, runtimeDefaultTrimMarginPrefixRaw, nil)
}

@_cdecl("kk_string_trimMargin")
public func kk_string_trimMargin(_ strRaw: Int, _ marginPrefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let marginPrefix = runtimeStringFromRaw(marginPrefixRaw) ?? "|"
    if marginPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "marginPrefix must be non-blank string."
        )
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(runtimeTrimMargin(source, marginPrefix: marginPrefix))
}

// MARK: - STDLIB-191: prependIndent / replaceIndent

private let runtimeDefaultPrependIndentRaw = runtimeMakeStringRaw(" ")
private let runtimeDefaultReplaceIndentRaw = runtimeMakeStringRaw("")

@_cdecl("kk_string_prependIndent_default")
public func kk_string_prependIndent_default(_ strRaw: Int) -> Int {
    kk_string_prependIndent(strRaw, runtimeDefaultPrependIndentRaw)
}

@_cdecl("kk_string_replaceIndent_default")
public func kk_string_replaceIndent_default(_ strRaw: Int) -> Int {
    kk_string_replaceIndent(strRaw, runtimeDefaultReplaceIndentRaw)
}

@_cdecl("kk_string_prependIndent")
public func kk_string_prependIndent(_ strRaw: Int, _ indentRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let indent = runtimeStringFromRaw(indentRaw) ?? " "
    return runtimeMakeStringRaw(runtimePrependIndent(source, indent: indent))
}

@_cdecl("kk_string_replaceIndent")
public func kk_string_replaceIndent(_ strRaw: Int, _ newIndentRaw: Int) -> Int {
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let newIndent = runtimeStringFromRawOrPanic(newIndentRaw, caller: #function)
    return runtimeMakeStringRaw(runtimeReplaceIndent(source, newIndent: newIndent))
}

@_cdecl("kk_string_replaceIndentByMargin")
public func kk_string_replaceIndentByMargin(
    _ strRaw: Int,
    _ newIndentRaw: Int,
    _ marginPrefixRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    outThrown?.pointee = 0
    let source = runtimeStringFromRawOrPanic(strRaw, caller: #function)
    let newIndent = runtimeStringFromRaw(newIndentRaw) ?? ""
    let marginPrefix = runtimeStringFromRaw(marginPrefixRaw) ?? "|"
    if marginPrefix.trimmingCharacters(in: .whitespaces).isEmpty {
        outThrown?.pointee = runtimeAllocateIllegalArgumentException(
            message: "marginPrefix must be non-blank string."
        )
        return runtimeMakeStringRaw("")
    }
    return runtimeMakeStringRaw(
        runtimeReplaceIndentByMargin(source, newIndent: newIndent, marginPrefix: marginPrefix)
    )
}

// MARK: - Flat ABI wrappers

@_cdecl("kk_string_trimIndent_flat")
public func kk_string_trimIndent_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_trimIndent(kk_string_from_flat(data, length, byteCount, hash))
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_trimMargin_default_flat")
public func kk_string_trimMargin_default_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_trimMargin_default(kk_string_from_flat(data, length, byteCount, hash))
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_trimMargin_flat")
public func kk_string_trimMargin_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ marginPrefixData: UnsafePointer<UInt8>?, _ marginPrefixLength: Int, _ marginPrefixByteCount: Int, _ marginPrefixHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    var thrown = 0
    let raw = kk_string_trimMargin(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(marginPrefixData, marginPrefixLength, marginPrefixByteCount, marginPrefixHash),
        &thrown
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_prependIndent_default_flat")
public func kk_string_prependIndent_default_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_prependIndent_default(kk_string_from_flat(data, length, byteCount, hash))
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_prependIndent_flat")
public func kk_string_prependIndent_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ indentData: UnsafePointer<UInt8>?, _ indentLength: Int, _ indentByteCount: Int, _ indentHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_prependIndent(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(indentData, indentLength, indentByteCount, indentHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceIndent_default_flat")
public func kk_string_replaceIndent_default_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceIndent_default(kk_string_from_flat(data, length, byteCount, hash))
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceIndent_flat")
public func kk_string_replaceIndent_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ newIndentData: UnsafePointer<UInt8>?, _ newIndentLength: Int, _ newIndentByteCount: Int, _ newIndentHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    let raw = kk_string_replaceIndent(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(newIndentData, newIndentLength, newIndentByteCount, newIndentHash)
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

@_cdecl("kk_string_replaceIndentByMargin_flat")
public func kk_string_replaceIndentByMargin_flat(
    _ data: UnsafePointer<UInt8>?, _ length: Int, _ byteCount: Int, _ hash: Int,
    _ newIndentData: UnsafePointer<UInt8>?, _ newIndentLength: Int, _ newIndentByteCount: Int, _ newIndentHash: Int,
    _ marginPrefixData: UnsafePointer<UInt8>?, _ marginPrefixLength: Int, _ marginPrefixByteCount: Int, _ marginPrefixHash: Int,
    _ outLength: UnsafeMutablePointer<Int>?, _ outByteCount: UnsafeMutablePointer<Int>?, _ outHash: UnsafeMutablePointer<Int>?
) -> UnsafeMutablePointer<UInt8>? {
    var thrown = 0
    let raw = kk_string_replaceIndentByMargin(
        kk_string_from_flat(data, length, byteCount, hash),
        kk_string_from_flat(newIndentData, newIndentLength, newIndentByteCount, newIndentHash),
        kk_string_from_flat(marginPrefixData, marginPrefixLength, marginPrefixByteCount, marginPrefixHash),
        &thrown
    )
    guard let string = runtimeStringFromRaw(raw) else { return nil }
    return runtimeRegisterFlatString(string, outLength: outLength, outByteCount: outByteCount, outHash: outHash)
}

// MARK: - MIGRATION-TEXT-006: Internal bridge functions for Kotlin stdlib source

@_cdecl("__string_trimIndent")
public func __string_trimIndent(_ strRaw: Int) -> Int {
    return kk_string_trimIndent(strRaw)
}

@_cdecl("__string_trimMargin")
public func __string_trimMargin(_ strRaw: Int, _ marginPrefixRaw: Int, _ outThrown: UnsafeMutablePointer<Int>?) -> Int {
    return kk_string_trimMargin(strRaw, marginPrefixRaw, outThrown)
}

@_cdecl("__string_prependIndent")
public func __string_prependIndent(_ strRaw: Int, _ indentRaw: Int) -> Int {
    return kk_string_prependIndent(strRaw, indentRaw)
}

@_cdecl("__string_replaceIndent")
public func __string_replaceIndent(_ strRaw: Int, _ newIndentRaw: Int) -> Int {
    return kk_string_replaceIndent(strRaw, newIndentRaw)
}

@_cdecl("__string_replaceIndentByMargin")
public func __string_replaceIndentByMargin(
    _ strRaw: Int,
    _ newIndentRaw: Int,
    _ marginPrefixRaw: Int,
    _ outThrown: UnsafeMutablePointer<Int>?
) -> Int {
    return kk_string_replaceIndentByMargin(strRaw, newIndentRaw, marginPrefixRaw, outThrown)
}

@_cdecl("__string_format")
public func __string_format(_ formatRaw: Int, _ argsArrayRaw: Int) -> Int {
    return kk_string_format(formatRaw, argsArrayRaw)
}
