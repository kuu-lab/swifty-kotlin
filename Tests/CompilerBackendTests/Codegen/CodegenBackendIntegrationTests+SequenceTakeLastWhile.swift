@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceTakeLastWhileUsesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("sequence_takelastwhile.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assertKotlinOutput(source, moduleName: "SequenceTakeLastWhileRuntime", expected: "[5, 6]\n[]\n[4, 5, 6]\n")
    }
}

