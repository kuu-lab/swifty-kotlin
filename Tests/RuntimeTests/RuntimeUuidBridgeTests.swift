#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeUuidBridgeTests {
    private func uuidBits(_ raw: Int) -> (msb: Int64, lsb: Int64)? {
        guard let box = runtimeArrayBox(from: raw), box.elements.count >= 4 else {
            return nil
        }
        return (Int64(box.elements[2]), Int64(box.elements[3]))
    }

    private func uuidVersion(_ bits: (msb: Int64, lsb: Int64)) -> Int {
        Int((UInt64(bitPattern: bits.msb) >> 12) & 0x0f)
    }

    private func uuidVariant(_ bits: (msb: Int64, lsb: Int64)) -> Int {
        let topThreeBits = (UInt64(bitPattern: bits.lsb) >> 61) & 0x07
        switch topThreeBits {
        case 0...3: return 0
        case 4...5: return 2
        case 6: return 6
        default: return 7
        }
    }

    @Test
    func testRandomBridgeReturnsVersion4UuidObject() throws {
        let raw = __kk_uuid_random()
        let bits = try #require(uuidBits(raw))

        #expect(uuidVersion(bits) == 4)
        #expect(uuidVariant(bits) == 2)
    }

    /// fromLongs must round-trip (UInt64.max, UInt64.max) without truncation.
    @Test
    func testFromLongsBridgeRoundTripsMaxBits() throws {
        let allOnes = Int(bitPattern: UInt.max)
        let bits = try #require(uuidBits(__kk_uuid_fromLongs(allOnes, allOnes)))
        #expect(UInt64(bitPattern: bits.msb) == UInt64.max)
        #expect(UInt64(bitPattern: bits.lsb) == UInt64.max)
    }

    @Test
    func testToKotlinUuidCopiesTwoLongObjectShape() throws {
        let source = __kk_uuid_random()
        let converted = __kk_uuid_toKotlinUuid(source)

        let sourceBits = try #require(uuidBits(source))
        let convertedBits = try #require(uuidBits(converted))
        #expect(sourceBits.msb == convertedBits.msb)
        #expect(sourceBits.lsb == convertedBits.lsb)
    }

    @Test
    func testToKotlinUuidReturnsDistinctObjectHandle() {
        let source = __kk_uuid_random()
        let converted = __kk_uuid_toKotlinUuid(source)

        #expect(converted != source, "toKotlinUuid must return a distinct object handle")
    }

    @Test
    func testToKotlinUuidNullReceiverReturnsAllZeroUuid() throws {
        let converted = __kk_uuid_toKotlinUuid(0)

        #expect(converted != 0, "null receiver must not produce a zero handle")
        let bits = try #require(uuidBits(converted))
        #expect(bits.msb == 0)
        #expect(bits.lsb == 0)
    }
}
#endif
