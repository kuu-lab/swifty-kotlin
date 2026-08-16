import Foundation

/// Decodes standard Kotlin string-literal escape sequences (`\n`, `\\`, `\"`,
/// `\uXXXX` including surrogate pairs, etc.) so that text reconstructed from
/// raw lexer tokens matches the value a user would see at runtime.
internal func decodeKotlinStringEscapes(_ raw: String) -> String {
    var result = ""
    var index = raw.startIndex

    func advance(_ current: String.Index, by offset: Int) -> String.Index {
        raw.index(current, offsetBy: offset, limitedBy: raw.endIndex) ?? raw.endIndex
    }

    while index < raw.endIndex {
        let character = raw[index]
        guard character == "\\" else {
            result.append(character)
            index = raw.index(after: index)
            continue
        }

        let escapeIndex = raw.index(after: index)
        guard escapeIndex < raw.endIndex else {
            result.append("\\")
            break
        }

        let escape = raw[escapeIndex]
        switch escape {
        case "n":
            result.append("\n")
            index = raw.index(after: escapeIndex)
        case "t":
            result.append("\t")
            index = raw.index(after: escapeIndex)
        case "r":
            result.append("\r")
            index = raw.index(after: escapeIndex)
        case "\"":
            result.append("\"")
            index = raw.index(after: escapeIndex)
        case "'":
            result.append("'")
            index = raw.index(after: escapeIndex)
        case "\\":
            result.append("\\")
            index = raw.index(after: escapeIndex)
        case "$":
            result.append("$")
            index = raw.index(after: escapeIndex)
        case "b":
            result.append("\u{08}")
            index = raw.index(after: escapeIndex)
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
                    result.unicodeScalars.append(scalar)
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
            result.append(escape)
            index = raw.index(after: escapeIndex)
        }
    }

    return result
}

/// Extracts the content of a Kotlin string literal value that was reconstructed
/// from lexer tokens (e.g. an annotation argument produced by
/// `AnnotationParsingSupport.tokenRawText`).
///
/// The reconstructed form may be a regular string, a raw triple-quoted string,
/// or a multi-dollar variant of either (`$"..."`, `$$"""..."""`, etc.).
/// Returns the unwrapped content and a flag indicating whether the literal is
/// raw (in which case escape sequences must not be decoded).
internal func extractKotlinStringLiteralContent(_ value: String) -> (content: String, isRaw: Bool)? {
    // Count optional leading dollar prefix used by multi-dollar strings.
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

    // tokenRawText wraps a string segment in an extra pair of quotes. So:
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

    // Synthetic stub metadata provides string arguments with a single pair
    // of delimiter quotes, rather than the double-wrapped form produced by
    // tokenRawText for source-derived annotation arguments.
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
