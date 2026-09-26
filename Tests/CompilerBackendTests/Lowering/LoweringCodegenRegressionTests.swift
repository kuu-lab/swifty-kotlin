#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct LoweringCodegenRegressionTests {
    @Test
    func testKxMiniRunBlockingDelayExecutableProducesSuspendResult() throws {
        // The suspend result is observed on stdout rather than through the
        // process status: `main`'s own value is discarded by the entry wrapper
        // (see `testEntryWrapperDiscardsNonUnitMainResult`).
        let source = """
        suspend fun delayedValue(): Int {
            delay(1)
            return 42
        }
        fun main() {
            println(runBlocking(delayedValue))
        }
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
            try runToLowering(ctx)
            do {
                try CodegenPhase().run(ctx)
                try LinkPhase().run(ctx)
            } catch {
                Issue.record("Compilation failed: \(error); diagnostics: \(ctx.diagnostics.diagnostics)")
                return
            }

            #expect(FileManager.default.fileExists(atPath: outputPath))
            let result = try CommandRunner.run(executable: outputPath, arguments: [])
            #expect(result.stdout.trimmingCharacters(in: .newlines) == "42")
        }
    }
}
#endif
