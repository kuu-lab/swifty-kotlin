@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceScanUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerCoreTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/sequence_scan.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)

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

