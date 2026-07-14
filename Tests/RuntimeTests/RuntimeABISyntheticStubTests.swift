import RuntimeABI
import XCTest

final class RuntimeABISyntheticStubTests: XCTestCase {
    /// Vararg synthetic stubs pass their arguments as one packed array handle.
    func testSequenceOfUsesPackedArrayABI() throws {
        let extern = try XCTUnwrap(
            RuntimeABIExterns.externDecl(named: "kk_sequence_of")
        )

        XCTAssertEqual(
            extern.parameterTypes,
            [RuntimeABICType.intptr.rawValue],
            "kk_sequence_of must accept one packed array handle"
        )
    }
}
