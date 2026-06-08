@testable import Runtime
import XCTest

/// Tests for kk_uuid_getUuid (ByteArray.getUuid extension, kotlin.uuid).
final class RuntimeUuidGetUuidTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Round-trip correctness

    func testGetUuidAtOffsetZeroKnownUuid() {
        let bytes: [Int] = [
            0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4,
            0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00,
        ]
        let arrayBox = RuntimeArrayBox(length: 16)
        for i in 0..<16 { arrayBox.elements[i] = bytes[i] }
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let uuidRaw = kk_uuid_getUuid(arrayRaw, 0, &thrown)

        XCTAssertEqual(thrown, 0, "getUuid must not throw for offset 0 on a 16-byte array")
        XCTAssertNotEqual(uuidRaw, 0)
        guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_uuid_toString(uuidRaw)),
              let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
        else { XCTFail("toString failed"); return }
        XCTAssertEqual(stringBox.value, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testGetUuidAtNonZeroOffset() {
        // 4 junk bytes then the UUID bytes
        let padding = 4
        let uuidBytes: [Int] = [
            0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4,
            0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00,
        ]
        let arrayBox = RuntimeArrayBox(length: padding + 16)
        for i in 0..<padding { arrayBox.elements[i] = 0xFF }
        for i in 0..<16 { arrayBox.elements[padding + i] = uuidBytes[i] }
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let uuidRaw = kk_uuid_getUuid(arrayRaw, padding, &thrown)

        XCTAssertEqual(thrown, 0, "getUuid must not throw at valid non-zero offset")
        guard let ptr = UnsafeMutableRawPointer(bitPattern: kk_uuid_toString(uuidRaw)),
              let stringBox = tryCast(ptr, to: RuntimeStringBox.self)
        else { XCTFail("toString failed"); return }
        XCTAssertEqual(stringBox.value, "550e8400-e29b-41d4-a716-446655440000")
    }

    func testGetUuidRoundTripWithToByteArray() {
        let originalRaw = kk_uuid_random()
        let byteArrayRaw = kk_uuid_toByteArray(originalRaw)

        var thrown = 0
        let reconstructedRaw = kk_uuid_getUuid(byteArrayRaw, 0, &thrown)
        XCTAssertEqual(thrown, 0, "getUuid must not throw on toByteArray output at offset 0")

        XCTAssertEqual(
            kk_uuid_mostSignificantBits(originalRaw),
            kk_uuid_mostSignificantBits(reconstructedRaw),
            "MSB mismatch after getUuid round-trip"
        )
        XCTAssertEqual(
            kk_uuid_leastSignificantBits(originalRaw),
            kk_uuid_leastSignificantBits(reconstructedRaw),
            "LSB mismatch after getUuid round-trip"
        )
    }

    func testGetUuidMatchesFromByteArray() {
        // getUuid(0) and fromByteArray must yield identical UUIDs for the same 16 bytes.
        let bytes: [Int] = [
            0x12, 0x3e, 0x45, 0x67, 0xe8, 0x9b, 0x12, 0xd3,
            0xa4, 0x56, 0x42, 0x66, 0x14, 0x17, 0x40, 0x00,
        ]
        let arrayBox = RuntimeArrayBox(length: 16)
        for i in 0..<16 { arrayBox.elements[i] = bytes[i] }
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrownGet = 0, thrownFrom = 0
        let uuidGet = kk_uuid_getUuid(arrayRaw, 0, &thrownGet)
        let uuidFrom = kk_uuid_fromByteArray(arrayRaw, &thrownFrom)

        XCTAssertEqual(thrownGet, 0)
        XCTAssertEqual(thrownFrom, 0)
        XCTAssertEqual(
            kk_uuid_mostSignificantBits(uuidGet),
            kk_uuid_mostSignificantBits(uuidFrom)
        )
        XCTAssertEqual(
            kk_uuid_leastSignificantBits(uuidGet),
            kk_uuid_leastSignificantBits(uuidFrom)
        )
    }

    // MARK: - Boundary: last valid offset

    func testGetUuidAtLastValidOffset() {
        // 32-byte array: UUID starts exactly at byte 16 (offset 16, size 32)
        let arrayBox = RuntimeArrayBox(length: 32)
        let uuidBytes: [Int] = [
            0x55, 0x0e, 0x84, 0x00, 0xe2, 0x9b, 0x41, 0xd4,
            0xa7, 0x16, 0x44, 0x66, 0x55, 0x44, 0x00, 0x00,
        ]
        for i in 0..<16 { arrayBox.elements[16 + i] = uuidBytes[i] }
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let uuidRaw = kk_uuid_getUuid(arrayRaw, 16, &thrown)
        XCTAssertEqual(thrown, 0, "getUuid must not throw at last valid offset")
        XCTAssertNotEqual(uuidRaw, 0)
    }

    // MARK: - Error: negative offset

    func testGetUuidNegativeOffsetThrows() {
        let arrayBox = RuntimeArrayBox(length: 16)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let result = kk_uuid_getUuid(arrayRaw, -1, &thrown)
        XCTAssertEqual(result, 0, "getUuid must return 0 for negative offset")
        XCTAssertNotEqual(thrown, 0, "getUuid must set outThrown for negative offset")
    }

    // MARK: - Error: offset too large

    func testGetUuidOffsetOneBeyondEndThrows() {
        // offset 1 on a 16-byte array: needs bytes [1, 17) but size is 16
        let arrayBox = RuntimeArrayBox(length: 16)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let result = kk_uuid_getUuid(arrayRaw, 1, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "getUuid must throw when offset+16 > size")
    }

    func testGetUuidEmptyArrayThrows() {
        let arrayBox = RuntimeArrayBox(length: 0)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let result = kk_uuid_getUuid(arrayRaw, 0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "getUuid must throw for empty array")
    }

    func testGetUuidArrayTooSmallThrows() {
        // 15-byte array — one byte short even at offset 0
        let arrayBox = RuntimeArrayBox(length: 15)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let result = kk_uuid_getUuid(arrayRaw, 0, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "getUuid must throw for array smaller than 16 bytes")
    }

    func testGetUuidOffsetExactlyOnePastLastValidThrows() {
        // 32-byte array: offset 17 needs bytes [17, 33) but size is 32 — out of bounds
        let arrayBox = RuntimeArrayBox(length: 32)
        let arrayRaw = registerRuntimeObject(arrayBox)

        var thrown = 0
        let result = kk_uuid_getUuid(arrayRaw, 17, &thrown)
        XCTAssertEqual(result, 0)
        XCTAssertNotEqual(thrown, 0, "getUuid must throw when offset+16 > 32")
    }
}
