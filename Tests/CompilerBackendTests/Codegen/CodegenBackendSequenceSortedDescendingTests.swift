#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendSequenceSortedDescendingTests {

    @Test
    func testCodegenSequenceSortedDescendingUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_sorted_descending.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSortedDescending",
            expected:
                """
                [3, 2, 1, 1]
                [c, b, a]
                """
                    + "\n"
        )
    }
}
#endif
