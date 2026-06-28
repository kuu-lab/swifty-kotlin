@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// STDLIB-SYSTEM-FN-001: exitProcess codegen integration tests.
///
/// exitProcess calls POSIX exit() and therefore cannot be called directly in tests
/// (it would terminate the test process). These tests verify the full codegen pipeline
/// by placing exitProcess calls on branches that are never executed at runtime, while
/// confirming the non-exit path produces the expected output.
extension CodegenBackendIntegrationTests {

    /// exitProcess reachable only through a dead conditional branch — normal output is produced.
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
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .newlines),
                "exit-process-codegen-ok"
            )
        }
    }

    /// exitProcess wrapped inside a helper function — the call site uses the helper but
    /// never actually invokes the exit path.  Verifies that Nothing-typed helper functions
    /// are correctly lowered through the ABI.
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
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .newlines),
                "helper-codegen-ok"
            )
        }
    }

    /// exitProcess used in a when expression — only the non-exit arm executes.
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
            XCTAssertEqual(
                result.stdout.trimmingCharacters(in: .newlines),
                "status-zero-ok"
            )
        }
    }
}
