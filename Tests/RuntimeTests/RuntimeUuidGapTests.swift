@testable import Runtime
import XCTest

/// Gap-coverage tests for the surviving kotlin.uuid.Uuid native bridges (KSP-476).
/// Parsing/formatting/version/variant/LEXICAL_ORDER/ByteArray extension coverage
/// moved to pure Kotlin (Sources/CompilerCore/Stdlib/kotlin/uuid/Uuid.kt) and is
/// exercised via Scripts/diff_cases/uuid_basic.kt / uuid_put_uuid.kt instead.
final class RuntimeUuidGapTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeByteArray(_ bytes: [UInt8]) -> Int {
        let box = RuntimeArrayBox(length: bytes.count)
        for (i, b) in bytes.enumerated() {
            box.elements[i] = Int(b)
        }
        return registerRuntimeObject(box)
    }

    private func bits(_ raw: Int) -> (msb: UInt64, lsb: UInt64) {
        (
            UInt64(bitPattern: Int64(__kk_uuid_mostSignificantBits(raw))),
            UInt64(bitPattern: Int64(__kk_uuid_leastSignificantBits(raw)))
        )
    }

    // MARK: - nameUUIDFromBytes: known RFC 4122 test vectors

    /// MD5("") with version-3 / IETF-variant bits applied.
    /// Cross-verified against Java UUID.nameUUIDFromBytes(new byte[0]).toString()
    /// == "d41d8cd9-8f00-3204-a980-0998ecf8427e".
    func testNameUUIDFromBytesEmptyBytesKnownVector() {
        let uuidRaw = __kk_uuid_nameUUIDFromBytes(makeByteArray([]))
        let (msb, lsb) = bits(uuidRaw)
        XCTAssertEqual(msb, 0xd41d8cd98f003204)
        XCTAssertEqual(lsb, 0xa9800998ecf8427e)
    }

    /// MD5("hello") with version-3 / IETF-variant bits applied.
    /// Cross-verified against Java UUID.nameUUIDFromBytes("hello".getBytes(StandardCharsets.UTF_8)).toString()
    /// == "5d41402a-bc4b-3a76-b971-9d911017c592".
    func testNameUUIDFromBytesHelloKnownVector() {
        let helloUTF8: [UInt8] = [0x68, 0x65, 0x6c, 0x6c, 0x6f] // "hello"
        let uuidRaw = __kk_uuid_nameUUIDFromBytes(makeByteArray(helloUTF8))
        let (msb, lsb) = bits(uuidRaw)
        XCTAssertEqual(msb, 0x5d41402abc4b3a76)
        XCTAssertEqual(lsb, 0xb9719d911017c592)
    }

    /// null raw is treated as an empty byte array — same UUID as empty bytes, no crash.
    func testNameUUIDFromBytesNullRawEqualsEmptyBytes() {
        let fromNull = bits(__kk_uuid_nameUUIDFromBytes(0))
        let fromEmpty = bits(__kk_uuid_nameUUIDFromBytes(makeByteArray([])))
        XCTAssertEqual(fromNull.msb, fromEmpty.msb)
        XCTAssertEqual(fromNull.lsb, fromEmpty.lsb)
    }

    // MARK: - Null receiver: surviving accessor defensive paths

    func testMostSignificantBitsNullReceiverReturnsZero() {
        XCTAssertEqual(__kk_uuid_mostSignificantBits(0), 0)
    }

    func testLeastSignificantBitsNullReceiverReturnsZero() {
        XCTAssertEqual(__kk_uuid_leastSignificantBits(0), 0)
    }

    // MARK: - fromLongs on MAX bit pattern

    /// fromLongs must round-trip (UInt64.max, UInt64.max) through
    /// mostSignificantBits / leastSignificantBits without truncation.
    func testFromLongsMaxBitsRoundTrips() {
        let allOnes = Int(bitPattern: UInt.max)
        let uuidRaw = __kk_uuid_fromLongs(allOnes, allOnes)
        let (msb, lsb) = bits(uuidRaw)
        XCTAssertEqual(msb, UInt64.max, "MSB must be UInt64.max for all-Fs UUID")
        XCTAssertEqual(lsb, UInt64.max, "LSB must be UInt64.max for all-Fs UUID")
    }
}
