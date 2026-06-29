@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceToCollectionUsesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("sequence_tocollection.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assertKotlinOutput(source, moduleName: "SequenceToCollectionRuntime", expected: "[0, 1, 2, 3, 4]\n[10, 2, 1, 3, 4]\n")
    }
}

