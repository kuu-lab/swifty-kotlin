import RuntimeABI
import XCTest

final class RuntimeABISpecVersionTests: XCTestCase {
    /// `RuntimeABISpec.specVersion` is now derived from `allFunctions` at first access,
    /// so this test verifies the value is a valid 64-character SHA-256 hex string and stable.
    func testSpecVersionIsValidAndDeterministic() {
        let version = RuntimeABISpec.specVersion
        XCTAssertEqual(
            version.count,
            64,
            "specVersion must be a 64-character SHA-256 hex string"
        )
        XCTAssertTrue(
            version.allSatisfy { $0.isHexDigit },
            "specVersion must contain only hex digits"
        )
        XCTAssertEqual(
            version,
            RuntimeABISpec.specVersion,
            "specVersion must be deterministic across repeated accesses"
        )
    }
}
