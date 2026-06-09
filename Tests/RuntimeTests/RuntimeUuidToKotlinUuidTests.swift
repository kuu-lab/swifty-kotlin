@testable import Runtime
import XCTest

/// Runtime tests for kk_uuid_toKotlinUuid (STDLIB-UUID-FN-004).
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

    // MARK: - Bit preservation

    func testToKotlinUuidPreservesAllBits() {
        var thrown = 0
        let source = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)

        let converted = kk_uuid_toKotlinUuid(source)

        XCTAssertNotEqual(converted, 0)
        XCTAssertEqual(
            kk_uuid_mostSignificantBits(converted),
            kk_uuid_mostSignificantBits(source)
        )
        XCTAssertEqual(
            kk_uuid_leastSignificantBits(converted),
            kk_uuid_leastSignificantBits(source)
        )
    }

    func testToKotlinUuidToStringRoundTrip() {
        var thrown = 0
        let source = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)

        let converted = kk_uuid_toKotlinUuid(source)

        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(converted)),
            "550e8400-e29b-41d4-a716-446655440000"
        )
    }

    func testToKotlinUuidNilUuidPreservesAllZeros() {
        let source = kk_uuid_nil()
        let converted = kk_uuid_toKotlinUuid(source)

        XCTAssertNotEqual(converted, 0)
        XCTAssertEqual(kk_uuid_mostSignificantBits(converted), 0)
        XCTAssertEqual(kk_uuid_leastSignificantBits(converted), 0)
        XCTAssertEqual(
            extractRuntimeString(kk_uuid_toString(converted)),
            "00000000-0000-0000-0000-000000000000"
        )
    }

    // MARK: - Object identity

    func testToKotlinUuidReturnsNewObject() {
        var thrown = 0
        let source = kk_uuid_parse(makeRuntimeString("550e8400-e29b-41d4-a716-446655440000"), &thrown)
        XCTAssertEqual(thrown, 0)

        let converted = kk_uuid_toKotlinUuid(source)

        XCTAssertNotEqual(converted, source, "toKotlinUuid must return a distinct object handle")
    }

    // MARK: - Null receiver defence

    func testToKotlinUuidNullReceiverReturnsNilUuid() {
        let converted = kk_uuid_toKotlinUuid(0)

        XCTAssertNotEqual(converted, 0, "null receiver must not produce a zero handle")
        XCTAssertEqual(kk_uuid_mostSignificantBits(converted), 0)
        XCTAssertEqual(kk_uuid_leastSignificantBits(converted), 0)
    }
}
