#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendAtomicEdgeCasesTests {

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
    func testCodegenCompilesAtomicEdgeCases() throws {
        let source = """
        @file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

        import kotlin.concurrent.atomics.AtomicInt
        import kotlin.concurrent.atomics.AtomicReference

        fun main() {
            val initial = "a"
            val updated = "b"
            val ref = AtomicReference(initial)
            println(ref.load())
            println(ref.compareAndSet("x", updated))
            println(ref.compareAndSet(initial, updated))
            println(ref.exchange("c"))
            println(ref.load())

            val count = AtomicInt(1)
            println(count.load())
            println(count.addAndFetch(4))
            println(count.fetchAndAdd(3))
            println(count.compareAndExchange(8, 10))
            println(count.compareAndExchange(9, 10))
            println(count.load())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AtomicEdgeCases",
            expected:
                """
                a
                false
                true
                b
                c
                1
                5
                5
                8
                10
                10
                """ + "\n"
        )
    }
}
#endif
