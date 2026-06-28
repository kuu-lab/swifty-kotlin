@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenStringReplaceOverloads() throws {
        let source = """
        fun main() {
            println("hello world".replace('l', 'r'))
            println("Hello World".replace("hello", "Hi", ignoreCase = true))
            println("Hello World".replace("hello", "Hi", ignoreCase = false))
            println("Hello World".replace('h', 'J', ignoreCase = true))
            println("Hello World".replace('H', 'J', ignoreCase = false))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringReplaceOverloads",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                herro worrd
                Hi World
                Hello World
                Jello World
                Jello World
                """
                + "\n"
            )
        }
    }
}
