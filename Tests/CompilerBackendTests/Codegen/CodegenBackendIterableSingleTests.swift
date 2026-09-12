@testable import CompilerCore
@testable import CompilerBackend
import Foundation

#if canImport(Testing)
import Testing

@Suite
struct CodegenBackendIterableSingleTests {
    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: .executable,
            target: defaultTargetTriple()
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

    @Test
    func codegenIterableSingleUsesCanonicalDiffCase() throws {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent() // Codegen/
            .deletingLastPathComponent() // CompilerBackendTests/
            .deletingLastPathComponent() // Tests/
            .deletingLastPathComponent() // repo root
        let caseURL = root.appendingPathComponent(
            "Scripts/diff_cases/stdlib_kotlin_collections_Iterable_single.kt",
            isDirectory: false
        )
        let source = try String(contentsOf: caseURL, encoding: .utf8)
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "IterableSingle",
                outputPath: outputBase
            )
            #expect(
                !ctx.diagnostics.hasError,
                "Expected canonical Iterable.single case to compile, got: \(ctx.diagnostics.diagnostics.map(\.message))"
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(
                normalizedStdout == """
                7
                1/1
                NoSuchElementException:Collection is empty.
                IllegalArgumentException:Collection has more than one element.:1
                3
                4/4
                NoSuchElementException:Collection contains no element matching the predicate.:3/3
                IllegalArgumentException:Collection contains more than one matching element.:3/3
                null
                1/1
                null
                null
                1/1
                null
                3/3
                IllegalStateException:predicate boom:2/2
                """
                + "\n"
            )
        }
    }
}
#endif
