#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LoweringCodegenRegressionTests {
    @Test
    func testKxMiniRunBlockingDelayExecutableReturnsExpectedExitCode() throws {
        let source = """
        suspend fun delayedValue(): Int {
            delay(1)
            return 42
        }
        fun main(): Any? = runBlocking(delayedValue)
        """

        try withTemporaryFile(contents: source) { path in
            let outputPath = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            defer { try? FileManager.default.removeItem(atPath: outputPath) }
            let ctx = makeCompilationContext(
                inputs: [path],
                moduleName: "KxMiniExecutable",
                emit: .executable,
                outputPath: outputPath
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            do {
                try CodegenPhase().run(ctx)
                try LinkPhase().run(ctx)
            } catch {
                Issue.record("Compilation failed: \(error); diagnostics: \(ctx.diagnostics.diagnostics)")
                return
            }

            #expect(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                Issue.record("Expected non-zero exit")
            } catch let CommandRunnerError.nonZeroExit(failed) {
                #expect(failed.exitCode == 42)
            } catch {
                Issue.record("Unexpected error: \(error)")
            }
        }
    }
}
#endif
