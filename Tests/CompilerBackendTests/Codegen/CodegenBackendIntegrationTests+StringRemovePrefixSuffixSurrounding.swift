@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenStringRemovePrefixSuffixSurrounding() throws {
        let source = """
        fun main() {
            // removePrefix
            println("HelloWorld".removePrefix("Hello"))
            println("HelloWorld".removePrefix("Goodbye"))
            println("prefix".removePrefix("prefix"))

            // removeSuffix
            println("HelloWorld".removeSuffix("World"))
            println("HelloWorld".removeSuffix("Earth"))
            println("suffix".removeSuffix("suffix"))

            // removeSurrounding(delimiter) — both ends must match the same delimiter
            println("***star***".removeSurrounding("***"))
            println("[bracketed]".removeSurrounding("["))
            println("ab".removeSurrounding("ab"))

            // removeSurrounding(prefix, suffix) — prefix and suffix can differ
            println("<div>content</div>".removeSurrounding("<div>", "</div>"))
            println("[item]".removeSurrounding("[", "]"))
            println("no-match".removeSurrounding("<", ">"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringRemovePrefixSuffixSurrounding",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                "World\nHelloWorld\n\nHello\nHelloWorld\n\nstar\n[bracketed]\nab\ncontent\nitem\nno-match\n"
            )
        }
    }
}
