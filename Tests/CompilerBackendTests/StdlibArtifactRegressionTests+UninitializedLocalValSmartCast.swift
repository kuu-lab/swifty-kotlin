@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2293: first assignment to an uninitialized local val narrows its flow type.
    @Test(arguments: [true, false], [0, 2])
    func testUninitializedLocalValSmartCastThroughSourceAndFreshArtifact(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()
        let publicInput = repoRoot.appendingPathComponent(
            "Tests/CompilerBackendTests/Fixtures/KUU-2293/kt52163_boolean.kt"
        ).path
        let minimalSource = """
        fun minimalBox(): String {
            val value: Any?
            value = "OK"
            return if (value.length == 2) "OK" else "FAIL"
        }
        """
        let runnerSource = """
        fun joinedBox(flag: Boolean): String {
            val value: Any?
            if (flag) value = "YES" else value = "OK"
            return if (value.length > 0) value else "FAIL"
        }
        fun main() {
            println(box())
            println(minimalBox())
            println(joinedBox(true))
            println(joinedBox(false))
        }
        """
        try withTemporaryFile(contents: minimalSource) { minimalInput in
            try withTemporaryFile(contents: runnerSource) { runnerInput in
                let output = directory.appendingPathComponent("kuu-2293").path
                let options = CompilerOptions(
                    moduleName: "KUU2293",
                    inputs: [publicInput, minimalInput, runnerInput],
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
                #expect(result.stderr.isEmpty, "Unexpected stderr: \(result.stderr)")
                #expect(result.stdout == "OK\nOK\nYES\nOK\n", "Unexpected output: \(result.stdout)")
            }
        }
    }
}
