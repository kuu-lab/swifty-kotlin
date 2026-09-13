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
struct CodegenBackendExitProcessTests {

    @Test
    func testExitProcessCodegenInDeadBranch() throws {
        let source = """
        import kotlin.system.exitProcess

        fun main() {
            val code = 0
            if (code < 0) {
                exitProcess(code)
            }
            println("exit-process-codegen-ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ExitProcessDeadBranch",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.trimmingCharacters(in: .newlines) == "exit-process-codegen-ok"
            )
        }
    }

    @Test
    func testExitProcessCodegenThroughHelperFunction() throws {
        let source = """
        import kotlin.system.exitProcess

        fun failFast(msg: String): Nothing {
            println(msg)
            exitProcess(1)
        }

        fun main() {
            val ok = true
            if (!ok) {
                failFast("should not reach")
            }
            println("helper-codegen-ok")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ExitProcessHelper",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.trimmingCharacters(in: .newlines) == "helper-codegen-ok"
            )
        }
    }

    @Test
    func testExitProcessCodegenInWhenExpression() throws {
        let source = """
        import kotlin.system.exitProcess

        fun main() {
            val status = 0
            when {
                status == 0 -> println("status-zero-ok")
                else -> exitProcess(status)
            }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ExitProcessWhen",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            #expect(
                result.stdout.trimmingCharacters(in: .newlines) == "status-zero-ok"
            )
        }
    }
}
#endif
