package enum StableFNV1a64 {
    private static let offsetBasis: UInt64 = 0xCBF2_9CE4_8422_2325
    private static let prime: UInt64 = 0x100_0000_01B3

    package struct Hasher {
        private var state = StableFNV1a64.offsetBasis

        package init() {}

        package mutating func update<S: Sequence>(bytes: S) where S.Element == UInt8 {
            for byte in bytes {
                state ^= UInt64(byte)
                state &*= StableFNV1a64.prime
            }
        }

        package func hexString(zeroPadded: Bool = true) -> String {
            let digits = String(state, radix: 16)
            guard zeroPadded, digits.count < 16 else {
                return digits
            }
            return String(repeating: "0", count: 16 - digits.count) + digits
        }
    }

    package static func hex(_ value: String, zeroPadded: Bool = true) -> String {
        var hasher = Hasher()
        hasher.update(bytes: value.utf8)
        return hasher.hexString(zeroPadded: zeroPadded)
    }
}
