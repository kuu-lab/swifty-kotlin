@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceSortedByUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_sorted_by.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "SequenceSortedBy",
            expected:
                """
                [a, cc, bbb]
                [2, 1, 3]
                """
                    + "\n"
        )
    }
}

