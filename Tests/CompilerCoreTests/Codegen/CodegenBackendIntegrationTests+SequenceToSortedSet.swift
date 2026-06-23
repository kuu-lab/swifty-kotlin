@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenSequenceToSortedSetUsesCanonicalDiffCase() throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
        let sourceURL = repoRoot
            .appendingPathComponent("Scripts")
            .appendingPathComponent("diff_cases")
            .appendingPathComponent("sequence_tosortedset.kt")
        let source = try String(contentsOf: sourceURL, encoding: .utf8)

        try assertKotlinOutput(source, moduleName: "SequenceToSortedSetRuntime", expected: "[1, 2, 3]\ntrue\nfalse\n[]\n")
    }
}

