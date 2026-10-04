#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// BUG-214: source-backed Pair/Triple accessors must unbox Double elements
/// before the primitive value is passed to the caller.
@Suite
struct CodegenBackendBug214PairTripleDoubleABITests {
    @Test
    func testPairAndTripleDoubleElementsSurviveSourceBackedAccessors() throws {
        let source = try diffCaseSource("bug_214_pair_double.kt")

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let options = CompilerOptions(
                moduleName: "Bug214PairTripleDoubleABI",
                inputs: [path],
                outputPath: outputBase,
                emit: .executable,
                target: defaultTargetTriple(),
                allowDefaultStdlibLibrary: false
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

            let errors = ctx.diagnostics.diagnostics.filter { $0.severity == .error }
            #expect(errors.isEmpty, "Unexpected diagnostics: \(errors.map(\.message))")

            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == "1.0\n1.0\n1.0\n[1, s, 1.0]\n"
            )
        }
    }
}
#endif
