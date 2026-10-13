#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendExitProcessTests {

    @Test(arguments: [0, 2], [false, true])
    func testJavaSystemExitPreservesJvmProcessStatus(optimization: Int, stdlibFromSource: Bool) throws {
        let optLevel = try #require(OptimizationLevel(rawValue: optimization))
        let stdlibLibraryPath = stdlibFromSource ? nil : try testStdlibArtifactPath()
        let source = """
        fun exitWithStatus(status: Int): Unit = System.exit(status)
        fun main(){System.exit(7);println("unreachable")}
        """

        try withTemporaryFile(contents: source) { inputPath in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }

            let options = CompilerOptions(
                moduleName: "JavaSystemExit",
                inputs: [inputPath],
                outputPath: outputPath,
                emit: .executable,
                target: defaultTargetTriple(),
                optLevel: optLevel,
                includeStdlib: stdlibFromSource,
                stdlibLibraryPath: stdlibLibraryPath,
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
            try LinkPhase().run(ctx)

            let result: CommandResult
            do {
                result = try CommandRunner.run(executable: outputPath, arguments: [])
            } catch let CommandRunnerError.nonZeroExit(failed) {
                result = failed
            }

            #expect(result.exitCode == 7)
            #expect(result.stdout.isEmpty)
            #expect(result.stderr.isEmpty)
        }
    }

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
