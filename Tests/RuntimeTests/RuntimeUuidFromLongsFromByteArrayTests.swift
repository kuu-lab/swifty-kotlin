@testable import Runtime
import XCTest

/// Tests for __kk_uuid_fromLongs (KSP-476). fromByteArray is now pure Kotlin
/// (Sources/CompilerCore/Stdlib/kotlin/uuid/Uuid.kt); its coverage lives in
/// Scripts/diff_cases/uuid_basic.kt and the Sema/KIR wiring tests instead.
final class RuntimeUuidFromLongsFromByteArrayTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testFromLongsRoundTripWithMostAndLeastSignificantBits() {
        let msb = Int(bitPattern: UInt(0x550e8400e29b41d4))
        let lsb = Int(bitPattern: UInt(0xa716446655440000))

        let uuidRaw = __kk_uuid_fromLongs(msb, lsb)
        XCTAssertNotEqual(uuidRaw, 0, "fromLongs must return a valid handle")

        XCTAssertEqual(__kk_uuid_mostSignificantBits(uuidRaw), msb, "MSB round-trip mismatch")
        XCTAssertEqual(__kk_uuid_leastSignificantBits(uuidRaw), lsb, "LSB round-trip mismatch")
    }

    func testFromLongsZeroProducesZeroBits() {
        let uuidRaw = __kk_uuid_fromLongs(0, 0)
        XCTAssertNotEqual(uuidRaw, 0, "fromLongs(0, 0) must return a valid handle (Uuid.NIL)")

        XCTAssertEqual(__kk_uuid_mostSignificantBits(uuidRaw), 0)
        XCTAssertEqual(__kk_uuid_leastSignificantBits(uuidRaw), 0)
    }

    func testFromLongsAllBitsSetRoundTrips() {
        let allOnes = Int(bitPattern: UInt.max)
        let uuidRaw = __kk_uuid_fromLongs(allOnes, allOnes)

        XCTAssertEqual(UInt64(bitPattern: Int64(__kk_uuid_mostSignificantBits(uuidRaw))), UInt64.max)
        XCTAssertEqual(UInt64(bitPattern: Int64(__kk_uuid_leastSignificantBits(uuidRaw))), UInt64.max)
    }

    func testFromLongsProducesDistinctHandlesForDistinctCalls() {
        let first = __kk_uuid_fromLongs(1, 2)
        let second = __kk_uuid_fromLongs(1, 2)
        XCTAssertNotEqual(first, second, "each fromLongs call must allocate a fresh handle")
        XCTAssertEqual(__kk_uuid_mostSignificantBits(first), __kk_uuid_mostSignificantBits(second))
        XCTAssertEqual(__kk_uuid_leastSignificantBits(first), __kk_uuid_leastSignificantBits(second))
    }
}
