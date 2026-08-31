#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceSingleOrNullTests {

    @Test
    func testCodegenSequenceSingleOrNullUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_single_or_null.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSingleOrNull",
            expected:
                """
                42
                -1
                -1
                only
                """
                + "\n"
        )
    }
}
#endif
