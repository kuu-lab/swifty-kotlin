#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceScanTests {

    @Test
    func testCodegenSequenceScanUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_scan.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceScan",
            expected:
                """
                [10, 11, 13, 16]
                [0, 1, 3, 6]
                [7]
                """
                    + "\n"
        )
    }
}
#endif
