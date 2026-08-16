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
