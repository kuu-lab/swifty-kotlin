#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceRunningFoldIndexedTests {

    @Test
    func testCodegenSequenceRunningFoldIndexedUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_running_fold_indexed.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceRunningFoldIndexed",
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
