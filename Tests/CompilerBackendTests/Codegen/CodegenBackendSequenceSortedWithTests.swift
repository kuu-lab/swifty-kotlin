@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendSequenceSortedWithTests {
    @Test
    func testCodegenSequenceSortedWithUsesCanonicalDiffCase() throws {
        let source = try diffCaseSource("sequence_sorted_with.kt")

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSortedWith",
            expected:
                """
                [1, 1, 2, 3]
                [3, 2, 1, 1]
                """
                    + "\n"
        )
    }
}

#endif
