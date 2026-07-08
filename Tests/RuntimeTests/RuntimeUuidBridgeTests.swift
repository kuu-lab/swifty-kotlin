@testable import Runtime
import XCTest

final class RuntimeUuidBridgeTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
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

    func testRandomBridgeReturnsVersion4UuidObject() throws {
        let raw = __kk_uuid_random()
        let bits = try XCTUnwrap(uuidBits(raw))

        XCTAssertEqual(uuidVersion(bits), 4)
        XCTAssertEqual(uuidVariant(bits), 2)
    }

    func testNameUuidBridgeIsDeterministicVersion3UuidObject() throws {
        let name = makeByteArray([104, 101, 108, 108, 111])
        let first = try XCTUnwrap(uuidBits(__kk_uuid_nameUUIDFromBytes(name)))
        let second = try XCTUnwrap(uuidBits(__kk_uuid_nameUUIDFromBytes(name)))

        XCTAssertEqual(first.msb, second.msb)
        XCTAssertEqual(first.lsb, second.lsb)
        XCTAssertEqual(uuidVersion(first), 3)
        XCTAssertEqual(uuidVariant(first), 2)
    }

    func testByteArrayUuidBridgeRoundTripsResidualRuntimeObject() throws {
        let original = __kk_uuid_random()
        let array = makeByteArray(Array(repeating: 0, count: 16))
        var putThrown = 0
        var getThrown = 0

        XCTAssertEqual(kk_byteArray_putUuid(array, 0, original, &putThrown), 0)
        XCTAssertEqual(putThrown, 0)
        let reconstructed = kk_byteArray_uuid(array, 0, &getThrown)
        XCTAssertEqual(getThrown, 0)

        let originalBits = try XCTUnwrap(uuidBits(original))
        let reconstructedBits = try XCTUnwrap(uuidBits(reconstructed))
        XCTAssertEqual(originalBits.msb, reconstructedBits.msb)
        XCTAssertEqual(originalBits.lsb, reconstructedBits.lsb)
    }

    func testToKotlinUuidCopiesTwoLongObjectShape() throws {
        let source = __kk_uuid_random()
        let converted = kk_uuid_toKotlinUuid(source)

        let sourceBits = try XCTUnwrap(uuidBits(source))
        let convertedBits = try XCTUnwrap(uuidBits(converted))
        XCTAssertEqual(sourceBits.msb, convertedBits.msb)
        XCTAssertEqual(sourceBits.lsb, convertedBits.lsb)
    }
}
