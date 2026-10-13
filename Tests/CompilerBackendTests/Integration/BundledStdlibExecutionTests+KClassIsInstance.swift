import Foundation
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [false, true])
    func projectedKClassReceiversIssue1988(fromArtifact: Bool) throws {
        let sourceURL = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .deletingLastPathComponent()
            .appendingPathComponent("Scripts/diff_cases/kclass_projected_receivers.kt")
        try compileAndRunKotlin(
            String(contentsOf: sourceURL, encoding: .utf8),
            expectedOutput: """
            true
            true
            false
            false
            Int
            42
            42
            null
            null
            true
            false
            42
            42
            true
            false
            true
            false
            42
            true
            null
            cast rejected

            """,
            moduleName: "KUU1988ProjectedKClassReceivers",
            allowDefaultStdlibLibrary: fromArtifact
        )
    }
}
