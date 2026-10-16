#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite(.serialized)
struct ExpectActualDefaultArgumentExecutionTests {
    @Test(arguments: [0, 2])
    func defaultArgumentStubForExpectCallsTheActualImplementation(
        optimization: Int
    ) throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }

        try withTemporaryFiles(contents: [
            """
            package kuu2350
            expect fun render(value: Int, suffix: String = "!"): String
            """,
            """
            package kuu2350
            actual fun render(value: Int, suffix: String): String = "$value$suffix"

            fun main() {
                println(render(7))
                println(render(8, "?"))
            }
            """,
        ]) { inputs in
            let output = directory.appendingPathComponent("expect-actual-defaults").path
            let options = CompilerOptions(
                moduleName: "KUU2350ExpectActualDefaults",
                inputs: inputs,
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                stdlibLibraryPath: try testStdlibArtifactPath()
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "expect/actual default argument dispatch"
            )

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution failed: \(result.stderr)")
            #expect(result.stdout == "7!\n8?\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
#endif
