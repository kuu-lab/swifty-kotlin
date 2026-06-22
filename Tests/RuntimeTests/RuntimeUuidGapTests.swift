@testable import Runtime
import XCTest

/// Gap-coverage tests for kotlin.uuid.Uuid runtime.
/// Covers the following previously untested behaviors:
///   • nameUUIDFromBytes: known RFC 4122 test vectors and null raw input
///   • fromByteArray: null raw input (distinct from wrong-size array)
///   • Null receiver: all instance methods return defined fallback values
///   • LEXICAL_ORDER: error path when non-UUID objects are compared
///   • toLongs on MAX UUID
///   • parseOrNull / parseHexDashOrNull uppercase input acceptance
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

    private func makeRuntimeString(_ value: String) -> Int {
        let utf8 = Array(value.utf8)
        return utf8.withUnsafeBufferPointer { buffer in
            Int(bitPattern: kk_string_from_utf8(buffer.baseAddress!, Int32(buffer.count)))
        }
    }

    private func extractRuntimeString(_ raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw),
              let box = tryCast(ptr, to: RuntimeStringBox.self) else {
            return ""
        }
        return box.value
    }

    private func extractThrowableMessage(_ raw: Int) -> String {
        extractRuntimeString(kk_throwable_message(raw))
    }

    private func makeByteArray(_ bytes: [UInt8]) -> Int {
        let box = RuntimeArrayBox(length: bytes.count)
        for (i, b) in bytes.enumerated() {
            box.elements[i] = Int(b)
        }
        return registerRuntimeObject(box)
    }

    private func extractArrayBox(_ raw: Int) -> RuntimeArrayBox? {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: raw) else { return nil }
        return tryCast(ptr, to: RuntimeArrayBox.self)
    }

    // MARK: - nameUUIDFromBytes: known RFC 4122 test vectors

    /// MD5("") with version-3 / IETF-variant bits applied.
    /// Cross-verified against Java UUID.nameUUIDFromBytes(new byte[0]).toString().
    func testNameUUIDFromBytesEmptyBytesKnownVector() {
        let uuidRaw = kk_uuid_nameUUIDFromBytes(makeByteArray([]))
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(uuidRaw)),
            "d41d8cd9-8f00-3204-a980-0998ecf8427e"
        )
    }

    /// MD5("hello") with version-3 / IETF-variant bits applied.
    /// Cross-verified against Java UUID.nameUUIDFromBytes("hello".getBytes(StandardCharsets.UTF_8)).toString().
    func testNameUUIDFromBytesHelloKnownVector() {
        let helloUTF8: [UInt8] = [0x68, 0x65, 0x6c, 0x6c, 0x6f] // "hello"
        let uuidRaw = kk_uuid_nameUUIDFromBytes(makeByteArray(helloUTF8))
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(uuidRaw)),
            "5d41402a-bc4b-3a76-b971-9d911017c592"
        )
    }

    /// null raw is treated as an empty byte array — same UUID as empty bytes, no crash.
    func testNameUUIDFromBytesNullRawEqualsEmptyBytes() {
        let fromNull = extractRuntimeString(kk_uuid_toString(kk_uuid_nameUUIDFromBytes(0)))
        let fromEmpty = extractRuntimeString(kk_uuid_toString(kk_uuid_nameUUIDFromBytes(makeByteArray([]))))
        XCTAssertEqual(fromNull, fromEmpty)
    }

    // MARK: - fromByteArray: null raw input

    /// Passing 0 as the raw array handle must throw with "was 0" — a distinct code path
    /// from passing a RuntimeArrayBox with zero elements.
    func testFromByteArrayNullRawThrows() {
        var thrown = 0
        let result = kk_uuid_fromByteArray(0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
        XCTAssertEqual(
            extractThrowableMessage(thrown),
            "IllegalArgumentException: byteArray.size must be 16, was 0"
        )
    }

    // MARK: - Null receiver: instance method defensive paths

    /// All instance methods guard against a 0 receiver and return a defined fallback
    /// rather than crashing.

    func testToStringNullReceiverReturnsNilUuidString() {
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(0)),
            "00000000-0000-0000-0000-000000000000"
        )
    }

    func testToHexStringNullReceiverReturnsThirtyTwoZeros() {
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toHexString(0)),
            "00000000000000000000000000000000"
        )
    }

    func testToLongsNullReceiverReturnsPairOfZeros() {
        let pairRaw = kk_uuid_toLongs(0)
        XCTAssertEqual(kk_pair_first(pairRaw), 0)
        XCTAssertEqual(kk_pair_second(pairRaw), 0)
    }

    func testToByteArrayNullReceiverReturnsSixteenZeroBytes() {
        let arrayRaw = kk_uuid_toByteArray(0)
        guard let box = extractArrayBox(arrayRaw) else {
            XCTFail("toByteArray(0) must return a valid array handle"); return
        }
        XCTAssertEqual(box.elements.count, 16)
        for i in 0..<16 {
            XCTAssertEqual(box.elements[i], 0, "byte \(i) must be 0 for null receiver")
        }
    }

    func testVersionNullReceiverReturnsZero() {
        XCTAssertEqual(kk_uuid_version(0), 0)
    }

    func testVariantNullReceiverReturnsZero() {
        XCTAssertEqual(kk_uuid_variant(0), 0)
    }

    func testMostSignificantBitsNullReceiverReturnsZero() {
        XCTAssertEqual(kk_uuid_mostSignificantBits(0), 0)
    }

    func testLeastSignificantBitsNullReceiverReturnsZero() {
        XCTAssertEqual(kk_uuid_leastSignificantBits(0), 0)
    }

    // MARK: - LEXICAL_ORDER: error path for non-UUID arguments

    /// The Comparator.compare implementation throws when neither argument is a RuntimeUuidBox.
    func testLexicalOrderCompareNonUuidArgSetsThrown() {
        let nonUuidRaw = makeRuntimeString("not-a-uuid-box")
        let comparator = kk_uuid_lexicalOrder()
        let compareFnRaw = kk_itable_lookup(comparator, 0, 0)
        XCTAssertNotEqual(compareFnRaw, 0, "LEXICAL_ORDER must register a Comparator.compare function")
        let compareFn = unsafeBitCast(compareFnRaw, to: RuntimeCollectionLambda2.self)
        var thrown = 0
        _ = compareFn(comparator, nonUuidRaw, nonUuidRaw, &thrown)
        XCTAssertNotEqual(thrown, 0, "compare with non-UUID arguments must throw")
    }

    // MARK: - toLongs on MAX UUID

    /// toLongs must return (UInt64.max, UInt64.max) for the all-Fs UUID, matching
    /// the behavior of mostSignificantBits / leastSignificantBits on the same UUID.
    func testToLongsMaxUuidReturnsBothBitsMax() {
        var thrown = 0
        let uuidRaw = kk_uuid_parse(makeRuntimeString("ffffffff-ffff-ffff-ffff-ffffffffffff"), &thrown)
        XCTAssertEqual(thrown, 0)

        let pairRaw = kk_uuid_toLongs(uuidRaw)
        XCTAssertEqual(UInt64(bitPattern: Int64(kk_pair_first(pairRaw))), UInt64.max,
                       "toLongs first (MSB) must be UInt64.max for all-Fs UUID")
        XCTAssertEqual(UInt64(bitPattern: Int64(kk_pair_second(pairRaw))), UInt64.max,
                       "toLongs second (LSB) must be UInt64.max for all-Fs UUID")
    }

    // MARK: - parseOrNull / parseHexDashOrNull uppercase acceptance

    /// parseOrNull must accept uppercase hex-dash input (same permissiveness as parse).
    func testParseOrNullAcceptsUppercaseHexDashInput() {
        let uuidRaw = kk_uuid_parseOrNull(makeRuntimeString("123E4567-E89B-12D3-A456-426614174000"))
        XCTAssertNotEqual(uuidRaw, runtimeNullSentinelInt)
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(uuidRaw)),
            "123e4567-e89b-12d3-a456-426614174000"
        )
    }

    /// parseHexDashOrNull must accept uppercase hex-dash input (same as parseHexDash).
    func testParseHexDashOrNullAcceptsUppercaseInput() {
        let uuidRaw = kk_uuid_parseHexDashOrNull(makeRuntimeString("123E4567-E89B-12D3-A456-426614174000"))
        XCTAssertNotEqual(uuidRaw, runtimeNullSentinelInt)
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(uuidRaw)),
            "123e4567-e89b-12d3-a456-426614174000"
        )
    }
}
