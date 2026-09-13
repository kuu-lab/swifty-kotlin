#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendAnnotationEdgeCasesTests {

    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
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

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenCompilesAnnotationEdgeCases() throws {
        let source = """
        @Target(AnnotationTarget.CLASS, AnnotationTarget.PROPERTY)
        @Retention(AnnotationRetention.RUNTIME)
        annotation class RuntimeMark(val label: String = "default")

        @Target(AnnotationTarget.FIELD)
        annotation class FieldMark

        @RuntimeMark("box")
        class Box(
            @field:FieldMark
            val value: Int,
        )

        @RuntimeMark
        class DefaultBox(
            val name: String,
        )

        fun main() {
            val box = Box(10)
            val defaultBox = DefaultBox("ok")
            println(box.value)
            println(defaultBox.name)
            println("annotation-edge-ok")
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AnnotationEdgeCases",
            expected:
                """
                10
                ok
                annotation-edge-ok
                """
                + "\n"
        )
    }
}
#endif
