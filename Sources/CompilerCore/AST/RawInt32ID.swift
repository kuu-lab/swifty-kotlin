/// A small integer identifier that JSON-encodes as a bare number instead of a
/// `{"rawValue": N}` object. The incremental frontend cache stores thousands of
/// these inside the AST arena snapshot, so the compact form shrinks frontend.json
/// and speeds up its encode/decode.
///
/// Decoding accepts both the bare-number form written by this version and the
/// legacy `{"rawValue": N}` object written by older caches, so existing caches
/// remain readable.
public protocol RawInt32ID: Hashable, Sendable, Codable {
    var rawValue: Int32 { get }
    init(rawValue: Int32)
}

private enum RawInt32IDCodingKeys: String, CodingKey {
    case rawValue
}

extension RawInt32ID {
    public init(from decoder: Decoder) throws {
        if let value = try? decoder.singleValueContainer().decode(Int32.self) {
            self.init(rawValue: value)
        } else {
            // Legacy cache format: {"rawValue": N}.
            let container = try decoder.container(keyedBy: RawInt32IDCodingKeys.self)
            self.init(rawValue: try container.decode(Int32.self, forKey: .rawValue))
        }
    }

    public func encode(to encoder: Encoder) throws {
        var container = encoder.singleValueContainer()
        try container.encode(rawValue)
    }
}
