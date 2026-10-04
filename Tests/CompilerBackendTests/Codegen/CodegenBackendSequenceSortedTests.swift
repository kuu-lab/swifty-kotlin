#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceSortedTests {

    @Test
    func testCodegenSequenceSortedUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_sorted.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSorted",
            expected:
                """
                [1, 2, 3]
                [a, cc, bbb]
                [2, 1, 3]
                [3, 2, 1]
                """
                    + "\n"
        )
    }
}
#endif
