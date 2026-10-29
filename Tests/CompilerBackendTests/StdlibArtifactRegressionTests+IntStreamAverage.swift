@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3643: IntStream.average accumulates in a wide integer without changing sum wrapping.
    @Test
    func testIntStreamAverageOverflowThroughSourceAndFreshArtifact() throws {
        let repositoryRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let inputPath = repositoryRoot
            .appendingPathComponent("Scripts/diff_cases/java_util_stream_IntStream_average_overflow.kt")
            .path

        for (fromSource, optimization) in [(false, 0), (true, 0), (false, 2)] {
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
            let options = CompilerOptions(
                moduleName: "KUU3643IntStreamAverage_\(fromSource)_O\(optimization)",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: CompilerTestSupport.defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(makeTestDriver().runForTesting(options: options))

            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == """
        2.147483647E9
        -2
        -2.147483648E9
        -0.5
        2.147483647E9
        -1.0
        2.0
        6

        """, "Unexpected output from source: \(fromSource), optimization: \(optimization)")
        }
    }
}
