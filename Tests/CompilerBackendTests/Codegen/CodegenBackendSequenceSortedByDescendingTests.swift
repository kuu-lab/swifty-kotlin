#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceSortedByDescendingTests {

    @Test
    func testCodegenSequenceSortedByDescendingUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_sorted_by_descending.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSortedByDescending",
            expected:
                """
                [bbb, cc, a]
                [3, 1, 2]
                """
                    + "\n"
        )
    }
}
#endif
