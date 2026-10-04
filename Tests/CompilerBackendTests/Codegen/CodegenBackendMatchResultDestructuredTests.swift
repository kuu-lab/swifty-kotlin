#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runMatchResultDestructuredCodegen(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
        target: defaultTargetTriple(),
        irFlags: []
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    try CodegenPhase().run(ctx)
    return ctx
}

@Suite
struct CodegenBackendMatchResultDestructuredTests {
    @Test func testComponent10AndToListPreserveCaptureContract() throws {
        let source = """
        fun main() {
            val match = Regex("(a)(b)?(c)(d)(e)(f)(g)(h)(i)(j)").find("acdefghij")
            if (match != null) {
                val destructured = match.destructured
                val captures = destructured.toList()
                println(destructured.component10())
                println(captures)
                println(captures.size)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runMatchResultDestructuredCodegen(
                inputPath: path,
                moduleName: "MatchResultDestructured",
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == """
                j
                [a, , c, d, e, f, g, h, i, j]
                10
                """ + "\n"
            )
        }
    }
}
#endif
