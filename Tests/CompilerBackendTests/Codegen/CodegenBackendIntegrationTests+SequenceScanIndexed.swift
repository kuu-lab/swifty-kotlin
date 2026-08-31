#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceScanIndexedTests {

    @Test
    func testCodegenSequenceScanIndexedUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_scan_indexed.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceScanIndexed",
            expected:
                """
                [100, 100, 102, 108, 120]
                [0, 1, 4, 9]
                [7]
                """
                    + "\n"
        )
    }
}
#endif
