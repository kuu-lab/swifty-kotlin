@testable import CompilerCore
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-2205: binary operator calls forward both hidden reified ABI tokens.
    @Test(arguments: [true, false], [0, 2])
    func testReifiedInlineExtensionBinaryOperatorsThroughSourceAndFreshArtifact(
        fromSource: Bool,
        optimization: Int
    ) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let source = try diffCaseSource("reified_inline_extension_binary_operator.kt", file: #filePath)
        try withTemporaryFile(contents: source) { input in
            let output = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: output) }

            let options = CompilerOptions(
                moduleName: "KUU2205ReifiedInlineOperatorTokens",
                inputs: [input],
                outputPath: output,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath,
                allowDefaultStdlibLibrary: false
            )
            try assertCompilationSucceeded(
                makeTestDriver().runForTesting(options: options),
                context: "KUU-2205 source/artifact O\(optimization) compilation"
            )

            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "1\n1\n3\n3\n1\n1\n2\n2\n")
        }
    }
}
