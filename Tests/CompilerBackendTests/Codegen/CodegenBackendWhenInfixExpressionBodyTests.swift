#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendWhenInfixExpressionBodyTests {
    @Test(arguments: [0, 2], [false, true])
    func whenToPairAndFollowingDeclarations(optimization: Int, stdlibFromSource: Bool) throws {
        var root = URL(fileURLWithPath: #filePath)
        for _ in 0 ..< 4 { root.deleteLastPathComponent() }
        let source = try String(contentsOf: root.appendingPathComponent(
            "Scripts/diff_cases/when_expression_body_infix_to.kt"
        ), encoding: .utf8)
        let artifact = stdlibFromSource ? nil : try testStdlibArtifactPath()
        try withTemporaryFile(contents: source) { path in
            let output = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "WhenInfixExpressionBody",
                outputPath: output,
                optLevel: try #require(OptimizationLevel(rawValue: optimization)),
                allowDefaultStdlibLibrary: false,
                stdlibLibraryPath: artifact
            )
            #expect(!ctx.diagnostics.hasError)
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: output, arguments: [])
            #expect(result.exitCode == 0)
            #expect(result.stderr.isEmpty)
            #expect(result.stdout == "(1, 3)\n(1, 3)\n(2, 3)\n(1, 3)\n(2, 3)\n(1, 3)\n(2, 3)\n4\n5\n6\n")
        }
    }
}
#endif
