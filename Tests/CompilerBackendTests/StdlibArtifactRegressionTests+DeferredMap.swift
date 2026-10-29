@testable import CompilerCore
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-1977: preserve the original async/await/awaitAll reproducer and
    /// exercise both map receiver types through source and fresh metadata.
    @Test(arguments: [false, true], [0, 2])
    func testDeferredMapThroughSourceAndFreshArtifact(fromSource: Bool, optimization: Int) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let cases = [
            ("coroutine_deferred", "deferred: 16\nresults: 55\nre-await: 99\nawaitAll: a,b,c\ndone\n"),
            ("coroutine_deferred_map", String(repeating: "[1, 4, 9]\n", count: 5)),
        ]
        for (name, expected) in cases {
            let input = repoRoot.appendingPathComponent("Scripts/diff_cases/\(name).kt").path
            let output = directory.appendingPathComponent(name).path
            let options = CompilerOptions(
                moduleName: "DeferredMap",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stdout == expected, "Unexpected output for \(name)")
        }
    }
}
