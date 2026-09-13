#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-218: verify file-local helpers keep distinct call bindings and native
/// symbols when same-named private top-level functions span source files.
@Suite
struct Bug218PrivateTopLevelCodegenTests {
    @Test
    func testPrivateTopLevelFunctionsInDifferentFilesExecuteIndependently() throws {
        let sources = [
            """
            package demo

            private fun helper(): Int = 1
            fun callFromA(): Int = helper()
            """,
            """
            package demo

            private fun helper(): Int = 2
            fun callFromB(): Int = helper()
            """,
            """
            package demo

            fun main() {
                println(callFromA())
                println(callFromB())
            }
            """,
        ]

        try withTemporaryFiles(contents: sources) { paths in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer {
                try? FileManager.default.removeItem(atPath: outputBase)
                try? FileManager.default.removeItem(atPath: outputBase + ".o")
            }

            let options = makeTestOptions(
                moduleName: "Bug218PrivateTopLevel",
                inputs: paths,
                outputPath: outputBase,
                emit: .executable
            )
            let result = makeTestDriver().runForTesting(options: options)
            #expect(
                result.exitCode == 0,
                "Compilation failed"
            )

            let runResult = try CommandRunner.run(executable: outputBase, arguments: [], timeout: 30)
            let normalizedStdout = runResult.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == "1\n2\n")
        }
    }
}
#endif
