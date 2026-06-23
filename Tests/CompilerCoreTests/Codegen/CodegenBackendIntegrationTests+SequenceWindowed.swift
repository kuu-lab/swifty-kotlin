@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceWindowedUsesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("sequence_windowed.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assertKotlinOutput(source, moduleName: "SequenceWindowedRuntime", expected: "[[1, 2, 3], [3, 4, 5], [5]]\n[]\n")
    }
}

