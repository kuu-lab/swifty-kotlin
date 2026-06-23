@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceSortedByDescendingUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_sorted_by_descending.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

