@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

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

