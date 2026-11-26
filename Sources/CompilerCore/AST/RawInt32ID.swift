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
