@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    // PARITY-CODEGEN-005: Char.compareTo(Char)
    func testCodegenCompilesCharCompareTo() throws {
        let source = """
        fun main() {
            println('Z'.compareTo('A'))
            println('A'.compareTo('Z'))
            println('A'.compareTo('A'))
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharCompareTo",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "25\n-25\n0\n")
        }
    }
}
