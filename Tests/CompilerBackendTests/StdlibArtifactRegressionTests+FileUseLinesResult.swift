@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// BUG-238: a generic File.useLines result keeps its List type through .kklib import.
    @Test
    func testFileUseLinesListResultMemberAccessThroughArtifact() throws {
        let artifactPath = try Self.buildStdlibArtifact()
        let fixtureURL = FileManager.default.temporaryDirectory
            .appendingPathComponent("KSwiftK-FileUseLines-\(UUID().uuidString).txt")
        try Data("alpha\nbeta\n".utf8).write(to: fixtureURL)
        defer { try? FileManager.default.removeItem(at: fixtureURL) }

        let source = """
        import java.io.File

        fun main() {
            val file = File("\(fixtureURL.path)")
            val collected = file.useLines { it.toList() }
            println(collected.size)
            println(collected.first())
        }
        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputBase) }

            let ctx = makeCompilationContext(
                inputs: [inputPath],
                moduleName: "Bug238FileUseLinesArtifact",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: false,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try runToKIR(ctx)
            try assertNoDiagnosticErrors(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "\(result.stderr)")
            #expect(result.stdout.replacingOccurrences(of: "\r\n", with: "\n") == "2\nalpha\n")
            #expect(result.stderr.isEmpty)
        }
    }
}
