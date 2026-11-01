@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

extension StdlibArtifactRegressionTests {
    /// KUU-3918: `Regex.matches` is declared `infix` in the Kotlin stdlib, so
    /// `regex matches input` must compile and run identically through both the
    /// source-injected bundled stdlib and a freshly compiled .kklib artifact.
    /// The case also covers the `infix` `String.matches(regex)` /
    /// `CharSequence.matches(regex)` overloads and `IntProgression.step`.
    @Test(arguments: [false, true])
    func testRegexInfixMatchesThroughSourceAndFreshArtifact(fromSource: Bool) throws {
        let artifactPath = fromSource ? nil : try Self.buildStdlibArtifact()
        let source = try diffCaseSource("regex_infix_matches.kt", file: #filePath)

        try withTemporaryFile(contents: source) { userPath in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = makeCompilationContext(
                inputs: [userPath],
                moduleName: "TestModule",
                emit: .executable,
                outputPath: outputBase,
                includeStdlib: fromSource,
                stdlibLibraryPath: artifactPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(result.exitCode == 0, "Execution stderr: \(result.stderr)")
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == """
            true
            false
            true
            match
            true
            true
            1
            3
            5

            """)
        }
    }
}
