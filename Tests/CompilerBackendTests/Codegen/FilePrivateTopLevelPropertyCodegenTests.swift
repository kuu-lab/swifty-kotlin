#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

/// KUU-1335: private properties must retain independent file-local storage.
@Suite
struct FilePrivateTopLevelPropertyCodegenTests {
    @Test(arguments: ["", "package demo"], ["private val", "private var", "private const val"])
    func propertiesExecuteIndependently(package: String, declaration: String) throws {
        let sources = [
            """
            \(package)

            \(declaration) secret = "f1"
            fun useSecret(): String = secret
            """,
            """
            \(package)

            \(declaration) secret = "f2-diff"
            fun useLocal(): String = secret
            """,
            """
            \(package)

            fun main() {
                println(useSecret())
                println(useLocal())
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
                moduleName: "FilePrivateTopLevelProperty",
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
            #expect(normalizedStdout == "f1\nf2-diff\n")
        }
    }
}
#endif
