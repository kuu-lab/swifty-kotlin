@testable import Runtime
import XCTest

/// Tests for kk_byteArray_putUuid and kk_byteArray_uuid.
final class RuntimeUuidPutUuidTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Helpers

    private func makeArray(length: Int) -> (raw: Int, box: RuntimeArrayBox) {
        let box = RuntimeArrayBox(length: length)
        return (registerRuntimeObject(box), box)
    }

    private func uuidString(from raw: Int) -> String {
        guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_uuid_toString(raw)),
              let box = tryCast(ptr, to: RuntimeStringBox.self)
        else { return "" }
        return box.value
    }

    // MARK: - putUuid: basic write

    func testPutUuidWritesCorrectBytesAtZeroOffset() {
        // 550e8400-e29b-41d4-a716-446655440000
        let msb = Int(bitPattern: UInt(0x550e8400e29b41d4))
        let lsb = Int(bitPattern: UInt(0xa716446655440000))
        let uuidRaw = kk_uuid_fromLongs(msb, lsb)

        let (arrayRaw, arrayBox) = makeArray(length: 16)
        var thrown = 0
        let result = kk_byteArray_putUuid(arrayRaw, 0, uuidRaw, &thrown)

        XCTAssertEqual(thrown, 0, "putUuid must not throw for a valid 16-byte array at offset 0")
        XCTAssertEqual(result, 0, "putUuid returns Unit (0)")

        let expected: [Int] = [
            0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4,
            0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00,
        ]
        XCTAssertEqual(arrayBox.elements, expected, "bytes in array must match UUID big-endian representation")
    }

    func testPutUuidWritesAtNonZeroOffset() {
        let msb = Int(bitPattern: UInt(0x123e4567e89b12d3))
        let lsb = Int(bitPattern: UInt(0xa456426614174000))
        let uuidRaw = kk_uuid_fromLongs(msb, lsb)

        // Array is 20 bytes; write UUID starting at offset 4
        let (arrayRaw, arrayBox) = makeArray(length: 20)
        var thrown = 0
        _ = kk_byteArray_putUuid(arrayRaw, 4, uuidRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        // First 4 bytes untouched
        XCTAssertEqual(arrayBox.elements[0], 0)
        XCTAssertEqual(arrayBox.elements[1], 0)
        XCTAssertEqual(arrayBox.elements[2], 0)
        XCTAssertEqual(arrayBox.elements[3], 0)
        // Bytes 4–19 must hold the UUID
        let slice = Array(arrayBox.elements[4..<20])
        let expected: [Int] = [
            0x12, 0x3e, 0x45, 0x67, 0xe8, 0x9b, 0x12, 0xd3,
            0xa4, 0x56, 0x42, 0x66, 0x14, 0x17, 0x40, 0x00,
        ]
        XCTAssertEqual(slice, expected)
    }

    func testPutUuidDoesNotClobberSurroundingBytes() {
        let uuidRaw = kk_uuid_fromLongs(
            Int(bitPattern: UInt(0xAAAAAAAAAAAAAAAA)),
            Int(bitPattern: UInt(0xBBBBBBBBBBBBBBBB))
        )

        // 32-byte array; write UUID at offset 8
        let (arrayRaw, arrayBox) = makeArray(length: 32)
        // Pre-fill with sentinel
        for i in 0..<32 { arrayBox.elements[i] = 0xFF }
        var thrown = 0
        _ = kk_byteArray_putUuid(arrayRaw, 8, uuidRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        // Bytes before and after the UUID window must remain 0xFF
        for i in 0..<8 { XCTAssertEqual(arrayBox.elements[i], 0xFF, "byte \(i) must be untouched") }
        for i in 24..<32 { XCTAssertEqual(arrayBox.elements[i], 0xFF, "byte \(i) must be untouched") }
    }

    // MARK: - putUuid: error conditions

    func testPutUuidThrowsOnNegativeOffset() {
        let uuidRaw = kk_uuid_fromLongs(0, 0)
        let (arrayRaw, _) = makeArray(length: 16)

        var thrown = 0
        let result = kk_byteArray_putUuid(arrayRaw, -1, uuidRaw, &thrown)

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "putUuid must throw IndexOutOfBoundsException for negative offset")
    }

    func testPutUuidThrowsWhenArrayTooSmall() {
        let uuidRaw = kk_uuid_fromLongs(0, 0)
        let (arrayRaw, _) = makeArray(length: 10)

        var thrown = 0
        _ = kk_byteArray_putUuid(arrayRaw, 0, uuidRaw, &thrown)

        XCTAssertNotEqual(thrown, 0, "putUuid must throw when array is too small to hold 16 bytes")
    }

    func testPutUuidThrowsWhenOffsetPlusSizeExceedsBounds() {
        let uuidRaw = kk_uuid_fromLongs(0, 0)
        // 20-byte array, but offset 5 + 16 = 21 > 20
        let (arrayRaw, _) = makeArray(length: 20)

        var thrown = 0
        _ = kk_byteArray_putUuid(arrayRaw, 5, uuidRaw, &thrown)

        XCTAssertNotEqual(thrown, 0, "putUuid must throw when at + 16 exceeds array size")
    }

    func testPutUuidThrowsForEmptyArray() {
        let uuidRaw = kk_uuid_fromLongs(0, 0)
        let (arrayRaw, _) = makeArray(length: 0)

        var thrown = 0
        _ = kk_byteArray_putUuid(arrayRaw, 0, uuidRaw, &thrown)

        XCTAssertNotEqual(thrown, 0, "putUuid must throw for zero-length array")
    }

    // MARK: - uuid(at:): basic read

    func testUuidAtZeroOffsetReadsCorrectUuid() {
        let expectedBytes: [Int] = [
            0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4,
            0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00,
        ]
        let (arrayRaw, arrayBox) = makeArray(length: 16)
        for i in 0..<16 { arrayBox.elements[i] = expectedBytes[i] }

        var thrown = 0
        let uuidRaw = kk_byteArray_uuid(arrayRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertNotEqual(uuidRaw, 0)
        XCTAssertEqual(uuidString(from: uuidRaw), "550e8400-e29b-41d4-a716-446655440000")
    }

    func testUuidAtNonZeroOffset() {
        // Prepend 4 garbage bytes, then 16 UUID bytes
        let (arrayRaw, arrayBox) = makeArray(length: 20)
        let uuidBytes: [Int] = [
            0x12, 0x3e, 0x45, 0x67, 0xe8, 0x9b, 0x12, 0xd3,
            0xa4, 0x56, 0x42, 0x66, 0x14, 0x17, 0x40, 0x00,
        ]
        for i in 0..<4 { arrayBox.elements[i] = 0xDE }
        for i in 0..<16 { arrayBox.elements[4 + i] = uuidBytes[i] }

        var thrown = 0
        let uuidRaw = kk_byteArray_uuid(arrayRaw, 4, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertEqual(uuidString(from: uuidRaw), "123e4567-e89b-12d3-a456-426614174000")
    }

    // MARK: - uuid(at:): error conditions

    func testUuidAtThrowsOnNegativeOffset() {
        let (arrayRaw, _) = makeArray(length: 16)

        var thrown = 0
        let result = kk_byteArray_uuid(arrayRaw, -1, &thrown)

        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0)
    }

    func testUuidAtThrowsWhenOutOfBounds() {
        // 10-byte array — too small for 16 bytes
        let (arrayRaw, _) = makeArray(length: 10)

        var thrown = 0
        _ = kk_byteArray_uuid(arrayRaw, 0, &thrown)

        XCTAssertNotEqual(thrown, 0)
    }

    // MARK: - putUuid / uuid(at:) round-trip

    func testPutUuidThenUuidAtRoundTrips() {
        let originalRaw = kk_uuid_random()
        let (arrayRaw, _) = makeArray(length: 16)

        var putThrown = 0
        _ = kk_byteArray_putUuid(arrayRaw, 0, originalRaw, &putThrown)
        XCTAssertEqual(putThrown, 0)

        var getThrown = 0
        let reconstructedRaw = kk_byteArray_uuid(arrayRaw, 0, &getThrown)
        XCTAssertEqual(getThrown, 0)

        XCTAssertEqual(
            kk_uuid_mostSignificantBits(originalRaw),
            kk_uuid_mostSignificantBits(reconstructedRaw),
            "MSB mismatch after putUuid/uuid round-trip"
        )
        XCTAssertEqual(
            kk_uuid_leastSignificantBits(originalRaw),
            kk_uuid_leastSignificantBits(reconstructedRaw),
            "LSB mismatch after putUuid/uuid round-trip"
        )
    }

    func testPutUuidMatchesToByteArray() {
        // Verify putUuid writes the same bytes that toByteArray() produces
        let uuidRaw = kk_uuid_random()
        let toByteArrayRaw = kk_uuid_toByteArray(uuidRaw)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: toByteArrayRaw),
              let referenceBox = tryCast(ptr, to: RuntimeArrayBox.self)
        else {
            XCTFail("toByteArray returned invalid handle"); return
        }

        let (putArrayRaw, putArrayBox) = makeArray(length: 16)
        var thrown = 0
        _ = kk_byteArray_putUuid(putArrayRaw, 0, uuidRaw, &thrown)
        XCTAssertEqual(thrown, 0)

        XCTAssertEqual(
            putArrayBox.elements,
            referenceBox.elements,
            "putUuid must write the same bytes as toByteArray()"
        )
    }

    func testNilUuidWritesAllZeros() {
        let nilUuidRaw = kk_uuid_nil()
        let (arrayRaw, arrayBox) = makeArray(length: 16)
        var thrown = 0
        _ = kk_byteArray_putUuid(arrayRaw, 0, nilUuidRaw, &thrown)

        XCTAssertEqual(thrown, 0)
        XCTAssertTrue(arrayBox.elements.allSatisfy { $0 == 0 }, "Uuid.NIL must write 16 zero bytes")
    }
}
