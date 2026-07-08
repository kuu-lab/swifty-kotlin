@testable import Runtime
import XCTest

/// version()/variant() are now pure Kotlin (Sources/CompilerCore/Stdlib/kotlin/uuid/Uuid.kt);
/// their coverage lives in Scripts/diff_cases/uuid_basic.kt. This file keeps only the
/// coverage for the surviving native bridges (fromLongs / mostSignificantBits /
/// leastSignificantBits / nameUUIDFromBytes / random).
final class RuntimeUuidAdvancedTests: XCTestCase {
    override func setUp() {
        super.setUp()
        kk_runtime_force_reset()
    }

    override func tearDown() {
        kk_runtime_force_reset()
        super.tearDown()
    }

    func testRandomProducesDistinctHandles() {
        let first = __kk_uuid_random()
        let second = __kk_uuid_random()
        XCTAssertNotEqual(first, 0)
        XCTAssertNotEqual(second, 0)
        XCTAssertTrue(
            __kk_uuid_mostSignificantBits(first) != __kk_uuid_mostSignificantBits(second)
                || __kk_uuid_leastSignificantBits(first) != __kk_uuid_leastSignificantBits(second),
            "two random UUIDs must not collide"
        )
    }

    func testMostSignificantBitsMatchesExpected() {
        let msb = Int(bitPattern: UInt(0x550e8400e29b41d4))
        let lsb = Int(bitPattern: UInt(0xa716446655440000))
        let uuidRaw = __kk_uuid_fromLongs(msb, lsb)
        // 550e8400-e29b-41d4 -> msb = 0x550e8400e29b41d4
        XCTAssertEqual(UInt64(bitPattern: Int64(__kk_uuid_mostSignificantBits(uuidRaw))), 0x550e8400e29b41d4)
    }

    func testLeastSignificantBitsMatchesExpected() {
        let msb = Int(bitPattern: UInt(0x550e8400e29b41d4))
        let lsb = Int(bitPattern: UInt(0xa716446655440000))
        let uuidRaw = __kk_uuid_fromLongs(msb, lsb)
        // a716-446655440000 -> lsb = 0xa716446655440000
        XCTAssertEqual(UInt64(bitPattern: Int64(__kk_uuid_leastSignificantBits(uuidRaw))), 0xa716446655440000)
    }

    func testNameUUIDFromBytesIsDeterministic() {
        let nameArr = RuntimeArrayBox(length: 5)
        for i in 0..<5 {
            nameArr.elements[i] = i + 1
        }
        let rawArr = registerRuntimeObject(nameArr)

        let uuid1 = __kk_uuid_nameUUIDFromBytes(rawArr)
        let uuid2 = __kk_uuid_nameUUIDFromBytes(rawArr)

        XCTAssertEqual(__kk_uuid_mostSignificantBits(uuid1), __kk_uuid_mostSignificantBits(uuid2))
        XCTAssertEqual(__kk_uuid_leastSignificantBits(uuid1), __kk_uuid_leastSignificantBits(uuid2))
    }
}
