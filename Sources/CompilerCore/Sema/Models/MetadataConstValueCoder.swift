import Foundation

/// Encodes/decodes `const val` initializer values for the text metadata format.
///
/// Values are written as `<tag>:<payload>`; floating point payloads use the raw
/// bit pattern and string payloads are base64 so the encoding never contains a
/// space and survives the space-separated record format.
enum MetadataConstValueCoder {
    static func encode(_ kind: KIRExprKind, resolver: (InternedString) -> String) -> String? {
        switch kind {
        case let .intLiteral(value): "i:\(value)"
        case let .longLiteral(value): "l:\(value)"
        case let .uintLiteral(value): "u:\(value)"
        case let .ulongLiteral(value): "ul:\(value)"
        case let .floatLiteral(value): "f:\(value.bitPattern)"
        case let .doubleLiteral(value): "d:\(value.bitPattern)"
        case let .charLiteral(value): "c:\(value)"
        case let .boolLiteral(value): "b:\(value ? 1 : 0)"
        case let .stringLiteral(value): "s:\(Data(resolver(value).utf8).base64EncodedString())"
        default: nil
        }
    }

    static func decode(_ encoded: String, interner: (String) -> InternedString) -> KIRExprKind? {
        guard let separator = encoded.firstIndex(of: ":") else { return nil }
        let tag = String(encoded[encoded.startIndex ..< separator])
        let payload = String(encoded[encoded.index(after: separator)...])
        switch tag {
        case "i": return Int64(payload).map { .intLiteral($0) }
        case "l": return Int64(payload).map { .longLiteral($0) }
        case "u": return UInt64(payload).map { .uintLiteral($0) }
        case "ul": return UInt64(payload).map { .ulongLiteral($0) }
        case "f": return UInt64(payload).map { .floatLiteral(Double(bitPattern: $0)) }
        case "d": return UInt64(payload).map { .doubleLiteral(Double(bitPattern: $0)) }
        case "c": return UInt32(payload).map { .charLiteral($0) }
        case "b": return .boolLiteral(payload == "1")
        case "s":
            guard let data = Data(base64Encoded: payload),
                  let text = String(data: data, encoding: .utf8)
            else { return nil }
            return .stringLiteral(interner(text))
        default: return nil
        }
    }
}
