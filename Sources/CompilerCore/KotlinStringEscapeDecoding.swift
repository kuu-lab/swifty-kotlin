import Foundation
import RuntimeABI

private let simpleKotlinStringEscapes: [Character: Character] = [
    "n": "\n",
    "t": "\t",
    "r": "\r",
    "\"": "\"",
    "'": "'",
    "\\": "\\",
    "$": "$",
    "b": "\u{08}",
]

/// Kotlin normalizes CR and CRLF line endings to LF inside raw string literals
/// at compile time, regardless of the platform the compiler runs on.
/// Iterates Unicode scalars because Swift treats CRLF as a single grapheme cluster.
internal func normalizeKotlinRawStringLineEndings(_ value: String) -> String {
    guard value.contains("\r") else { return value }
    var result = String.UnicodeScalarView()
    var index = value.unicodeScalars.startIndex
    let end = value.unicodeScalars.endIndex
    while index < end {
        let scalar = value.unicodeScalars[index]
        if scalar == "\r" {
            result.append("\n")
            let next = value.unicodeScalars.index(after: index)
            if next < end, value.unicodeScalars[next] == "\n" {
                index = value.unicodeScalars.index(after: next)
            } else {
                index = next
            }
        } else {
            result.append(scalar)
            index = value.unicodeScalars.index(after: index)
        }
    }
    return String(result)
}

internal func decodeKotlinStringEscapes(_ raw: String) -> String {
    var result = ""
    var index = raw.startIndex

    func advance(_ current: String.Index, by offset: Int) -> String.Index {
        raw.index(current, offsetBy: offset, limitedBy: raw.endIndex) ?? raw.endIndex
    }

    while index < raw.endIndex {
        let character = raw[index]
        guard character == "\\" else {
            result.append(contentsOf: KotlinStringSurrogateEncoding.encode(String(character)))
            index = raw.index(after: index)
            continue
        }

        let escapeIndex = raw.index(after: index)
        guard escapeIndex < raw.endIndex else {
            result.append("\\")
            break
        }

        let escape = raw[escapeIndex]
        if let decoded = simpleKotlinStringEscapes[escape] {
            result.append(decoded)
            index = raw.index(after: escapeIndex)
            continue
        }
        switch escape {
        case "u":
            let hexStart = raw.index(after: escapeIndex)
            let hexEnd = advance(hexStart, by: 4)
            let hexDigits = String(raw[hexStart..<hexEnd])
            if hexDigits.count == 4,
               let scalarValue = UInt32(hexDigits, radix: 16)
            {
                if (0xD800 ... 0xDBFF).contains(scalarValue),
                   hexEnd < raw.endIndex,
                   raw[hexEnd] == "\\"
                {
                    let nextEscapeIndex = raw.index(after: hexEnd)
                    if nextEscapeIndex < raw.endIndex,
                       raw[nextEscapeIndex] == "u"
                    {
                        let lowStart = raw.index(after: nextEscapeIndex)
                        let lowEnd = advance(lowStart, by: 4)
                        let lowDigits = String(raw[lowStart..<lowEnd])
                        if lowDigits.count == 4,
                           let lowValue = UInt32(lowDigits, radix: 16),
                           (0xDC00 ... 0xDFFF).contains(lowValue)
                        {
                            let highTenBits = scalarValue - 0xD800
                            let lowTenBits = lowValue - 0xDC00
                            let combined = 0x10000 + (highTenBits << 10) + lowTenBits
                            if let scalar = UnicodeScalar(combined) {
                                result.unicodeScalars.append(scalar)
                                index = lowEnd
                                continue
                            }
                        }
                    }
                }

                if let scalar = UnicodeScalar(scalarValue) {
                    result.append(contentsOf: KotlinStringSurrogateEncoding.encode(String(scalar)))
                    index = hexEnd
                } else if KotlinStringSurrogateEncoding.markerValue(for: scalarValue) != nil {
                    result.append(contentsOf: KotlinStringSurrogateEncoding.fromUTF16CodeUnits([UInt16(scalarValue)]))
                    index = hexEnd
                } else {
                    result.append("\\")
                    result.append("u")
                    index = raw.index(after: escapeIndex)
                }
            } else {
                result.append("\\")
                result.append("u")
                index = raw.index(after: escapeIndex)
            }
        default:
            result.append(contentsOf: KotlinStringSurrogateEncoding.encode(String(escape)))
            index = raw.index(after: escapeIndex)
        }
    }

    return result
}

/// Legacy annotation token reconstruction added quotes around every segment
/// and repeated multi-dollar prefixes on closing delimiters. Its raw form can
/// equal a canonical raw literal containing quotes, so provenance is required.
internal enum KotlinStringLiteralRepresentation {
    case canonical
    case legacyAnnotationTokens
}

internal func extractKotlinStringLiteralContent(
    _ value: String,
    representation: KotlinStringLiteralRepresentation = .canonical
) -> (content: String, isRaw: Bool)? {
    if representation == .legacyAnnotationTokens {
        return extractLegacyAnnotationStringLiteralContent(value)
    }

    let dollarPrefix = String(value.prefix { $0 == "$" })
    let rawPrefix = dollarPrefix + "\"\"\""
    if value.hasPrefix(rawPrefix) {
        guard value.count >= rawPrefix.count + 3, value.hasSuffix("\"\"\"") else { return nil }
        return (String(value.dropFirst(rawPrefix.count).dropLast(3)), true)
    }

    let remainder = value.dropFirst(dollarPrefix.count)
    guard let quote = remainder.first, quote == "\"" || quote == "'",
          remainder.count >= 2, remainder.last == quote else { return nil }
    return (String(remainder.dropFirst().dropLast()), false)
}

private func extractLegacyAnnotationStringLiteralContent(_ value: String) -> (content: String, isRaw: Bool)? {
    var index = value.startIndex
    var dollarCount = 0
    while index < value.endIndex, value[index] == "$" {
        dollarCount += 1
        value.formIndex(after: &index)
    }

    guard index < value.endIndex else { return nil }
    let quoteChar = value[index]
    guard quoteChar == "\"" || quoteChar == "'" else { return nil }

    let dollarPrefix = String(repeating: "$", count: dollarCount)

    // Historical tokenRawText wrapped each segment in extra quotes:
    // - Regular `$"abc"` becomes `$""abc"$"`.
    // - Raw `$$"""abc"""` becomes `$$""""abc"$$"""`.
    // - Empty raw `$$""""""` becomes `$$"""$$"""`.
    let rawPrefix = dollarPrefix + String(repeating: quoteChar, count: 4)
    let rawSuffix = String(quoteChar) + dollarPrefix + String(repeating: quoteChar, count: 3)
    let emptyRaw = dollarPrefix + String(repeating: quoteChar, count: 3) + dollarPrefix + String(repeating: quoteChar, count: 3)

    if value == emptyRaw {
        return ("", true)
    }
    if value.hasPrefix(rawPrefix), value.hasSuffix(rawSuffix) {
        let start = value.index(value.startIndex, offsetBy: rawPrefix.count)
        let end = value.index(value.endIndex, offsetBy: -rawSuffix.count)
        return (start <= end ? String(value[start..<end]) : "", true)
    }

    let regularPrefix = dollarPrefix + String(repeating: quoteChar, count: 2)
    let regularSuffix = String(quoteChar) + dollarPrefix + String(quoteChar)
    if value.hasPrefix(regularPrefix), value.hasSuffix(regularSuffix) {
        let start = value.index(value.startIndex, offsetBy: regularPrefix.count)
        let end = value.index(value.endIndex, offsetBy: -regularSuffix.count)
        return (start <= end ? String(value[start..<end]) : "", false)
    }

    // Empty multi-dollar regular strings (`$$""`) are reconstructed as
    // `$$"$$"`, which must not fall through to the single-quote fallback.
    let emptyRegular = dollarPrefix + String(quoteChar) + dollarPrefix + String(quoteChar)
    if value == emptyRegular {
        return ("", false)
    }

    // Synthetic stub metadata already used a single delimiter pair even
    // when source-derived annotation arguments were double-wrapped.
    let singlePrefix = dollarPrefix + String(quoteChar)
    if value.count > singlePrefix.count,
       value.hasPrefix(singlePrefix),
       value.hasSuffix(String(quoteChar))
    {
        let start = value.index(value.startIndex, offsetBy: singlePrefix.count)
        let end = value.index(before: value.endIndex)
        return (start <= end ? String(value[start..<end]) : "", false)
    }

    return nil
}
