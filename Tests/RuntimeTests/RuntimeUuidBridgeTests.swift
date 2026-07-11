#if canImport(Testing)
@testable import Runtime
import Testing

@Suite(.serialized)
struct RuntimeUuidBridgeTests {
    init() {
        kk_runtime_force_reset()
    }

    private func uuidBits(_ raw: Int) -> (msb: Int64, lsb: Int64)? {
        guard let box = runtimeArrayBox(from: raw), box.elements.count >= 4 else {
            return nil
        }
        return (Int64(box.elements[2]), Int64(box.elements[3]))
    }

    private func makeByteArray(_ bytes: [Int]) -> Int {
        let box = RuntimeArrayBox(length: bytes.count)
        for index in bytes.indices {
            box.elements[index] = bytes[index]
        }
        return registerRuntimeObject(box)
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

    @Test
    func testNameUuidBridgeIsDeterministicVersion3UuidObject() throws {
        let name = makeByteArray([104, 101, 108, 108, 111])
        let first = try #require(uuidBits(__kk_uuid_nameUUIDFromBytes(name)))
        let second = try #require(uuidBits(__kk_uuid_nameUUIDFromBytes(name)))

        #expect(first.msb == second.msb)
        #expect(first.lsb == second.lsb)
        #expect(uuidVersion(first) == 3)
        #expect(uuidVariant(first) == 2)
    }

    /// MD5("") with version-3 / IETF-variant bits applied.
    /// Cross-verified against Java UUID.nameUUIDFromBytes(new byte[0]).toString()
    /// == "d41d8cd9-8f00-3204-a980-0998ecf8427e".
    @Test
    func testNameUuidBridgeMatchesKnownRfc4122VectorForEmptyBytes() throws {
        let bits = try #require(uuidBits(__kk_uuid_nameUUIDFromBytes(makeByteArray([]))))
        #expect(UInt64(bitPattern: bits.msb) == 0xd41d8cd98f003204)
        #expect(UInt64(bitPattern: bits.lsb) == 0xa9800998ecf8427e)
    }

    /// MD5("hello") with version-3 / IETF-variant bits applied.
    /// Cross-verified against Java UUID.nameUUIDFromBytes("hello".getBytes(StandardCharsets.UTF_8)).toString()
    /// == "5d41402a-bc4b-3a76-b971-9d911017c592".
    @Test
    func testNameUuidBridgeMatchesKnownRfc4122VectorForHelloBytes() throws {
        let helloUTF8 = [104, 101, 108, 108, 111] // "hello"
        let bits = try #require(uuidBits(__kk_uuid_nameUUIDFromBytes(makeByteArray(helloUTF8))))
        #expect(UInt64(bitPattern: bits.msb) == 0x5d41402abc4b3a76)
        #expect(UInt64(bitPattern: bits.lsb) == 0xb9719d911017c592)
    }

    /// null raw is treated as an empty byte array — same UUID as empty bytes, no crash.
    @Test
    func testNameUuidBridgeNullRawEqualsEmptyBytes() throws {
        let fromNull = try #require(uuidBits(__kk_uuid_nameUUIDFromBytes(0)))
        let fromEmpty = try #require(uuidBits(__kk_uuid_nameUUIDFromBytes(makeByteArray([]))))
        #expect(fromNull.msb == fromEmpty.msb)
        #expect(fromNull.lsb == fromEmpty.lsb)
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
