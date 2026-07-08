@testable import Runtime
import XCTest

/// Runtime tests for __kk_uuid_toKotlinUuid (KSP-476).
///
/// java.util.UUID and kotlin.uuid.Uuid share the same RuntimeUuidBox representation,
/// so toKotlinUuid is an identity-style conversion that copies the box.
final class RuntimeUuidToKotlinUuidTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    // MARK: - Bit preservation

    func testToKotlinUuidPreservesAllBits() {
        let msb = Int(bitPattern: UInt(0x550e8400e29b41d4))
        let lsb = Int(bitPattern: UInt(0xa716446655440000))
        let source = __kk_uuid_fromLongs(msb, lsb)

        let converted = __kk_uuid_toKotlinUuid(source)

        XCTAssertNotEqual(converted, 0)
        XCTAssertEqual(__kk_uuid_mostSignificantBits(converted), __kk_uuid_mostSignificantBits(source))
        XCTAssertEqual(__kk_uuid_leastSignificantBits(converted), __kk_uuid_leastSignificantBits(source))
    }

    func testToKotlinUuidNilUuidPreservesAllZeros() {
        let source = __kk_uuid_fromLongs(0, 0)
        let converted = __kk_uuid_toKotlinUuid(source)

        XCTAssertNotEqual(converted, 0)
        XCTAssertEqual(__kk_uuid_mostSignificantBits(converted), 0)
        XCTAssertEqual(__kk_uuid_leastSignificantBits(converted), 0)
    }

    // MARK: - Object identity

    func testToKotlinUuidReturnsNewObject() {
        let source = __kk_uuid_fromLongs(
            Int(bitPattern: UInt(0x550e8400e29b41d4)),
            Int(bitPattern: UInt(0xa716446655440000))
        )

        let converted = __kk_uuid_toKotlinUuid(source)

        XCTAssertNotEqual(converted, source, "toKotlinUuid must return a distinct object handle")
    }

    // MARK: - Null receiver defence

    func testToKotlinUuidNullReceiverReturnsNilUuid() {
        let converted = __kk_uuid_toKotlinUuid(0)

        XCTAssertNotEqual(converted, 0, "null receiver must not produce a zero handle")
        XCTAssertEqual(__kk_uuid_mostSignificantBits(converted), 0)
        XCTAssertEqual(__kk_uuid_leastSignificantBits(converted), 0)
    }
}
