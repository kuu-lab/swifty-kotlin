#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

@Suite
struct CodegenBackendAutoCloseableFactoryTests {

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
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenCompilesAutoCloseableFactory() throws {
        let source = """
        fun main() {
            var closed = 0
            val resource: AutoCloseable = AutoCloseable {
                closed = closed + 1
                println("closed:" + closed)
            }
            resource.close()
            println("after-close:" + closed)
            AutoCloseable {
                println("use-close")
            }.use {
                println("use-body")
            }
        }
        """

        try assertKotlinOutput(source, moduleName: "AutoCloseableFactory", expected: "closed:1\nafter-close:1\nuse-body\nuse-close\n")
    }

    @Test
    func testCodegenCompilesNullableAutoCloseableUse() throws {
        let source = """
        fun main() {
            var closed = 0
            val missing: AutoCloseable? = null
            val missingResult = missing.use { resource ->
                if (resource == null) "missing" else "bad"
            }
            println(missingResult)
            println("closed:" + closed)

            val present: AutoCloseable? = AutoCloseable {
                closed = closed + 1
                println("closed:" + closed)
            }
            val presentResult = present.use { resource ->
                if (resource == null) "bad" else "present"
            }
            println(presentResult)
            println("after:" + closed)
        }
        """

        try assertKotlinOutput(source, moduleName: "NullableAutoCloseableUse", expected: "missing\nclosed:0\nclosed:1\npresent\nafter:1\n")
    }

    @Test
    func testCodegenPreservesPrimaryAndSuppressedCloseExceptions() throws {
        let source = """
        class ThrowingResource(private val throwOnClose: Boolean) : AutoCloseable {
            override fun close() {
                if (throwOnClose) throw IllegalStateException("close")
            }
        }

        fun main() {
            try {
                ThrowingResource(false).use {
                    throw IllegalStateException("primary-only")
                }
            } catch (e: Throwable) {
                println(e.message)
                println(e.suppressedExceptions.size)
            }

            try {
                ThrowingResource(true).use {
                    throw IllegalStateException("primary")
                }
            } catch (e: Throwable) {
                println(e.message)
                println(e.suppressedExceptions.size)
                println(e.suppressedExceptions[0].message)
            }

            try {
                ThrowingResource(true).use { "body" }
            } catch (e: Throwable) {
                println(e.message)
                println(e.suppressedExceptions.size)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "AutoCloseableCloseFinallyExceptions",
            expected: "primary-only\n0\nprimary\n1\nclose\nclose\n0\n"
        )
    }
}
#endif
