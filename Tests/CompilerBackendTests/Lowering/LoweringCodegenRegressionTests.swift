@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

final class LoweringCodegenRegressionTests: XCTestCase {
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
            try CodegenPhase().run(ctx)
            try LinkPhase().run(ctx)

            XCTAssertTrue(FileManager.default.fileExists(atPath: outputPath))
            do {
                _ = try CommandRunner.run(executable: outputPath, arguments: [])
                XCTFail("Expected non-zero exit")
                return
            } catch let CommandRunnerError.nonZeroExit(failed) {
                XCTAssertEqual(failed.exitCode, 42)
            } catch {
                XCTFail("Unexpected error: \(error)")
            }
        }
    }
}
