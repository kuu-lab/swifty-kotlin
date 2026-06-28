// STDLIB-TEXT-FN-101: End-to-end execution tests for CharSequence.toList().
// kk_string_toList materialises each Unicode scalar as a boxed Char and returns
// a List<Char>, so println renders it with the standard list format [a, b, c].
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // MARK: - String.toList()

    func testCodegenStringToList() throws {
        let source = """
        fun main() {
            // String literal receiver
            println("hello".toList())

            // empty string yields an empty list
            println("".toList())

            // CharSequence receiver resolves to the same conversion
            val cs: CharSequence = "abc"
            println(cs.toList())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToList",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                [h, e, l, l, o]
                []
                [a, b, c]
                """
                + "\n"
            )
        }
    }

    func testCodegenStringToListSupportsListOperations() throws {
        // The result is a genuine List<Char>, so size/first/last behave as expected.
        // (Indexing via chars[0] is intentionally avoided here: the get-operator
        // lowering mis-dispatches List<Char>[i] to kk_string_get — a pre-existing
        // bug unrelated to toList, reproducible with listOf('h','i')[0].)
        let source = """
        fun main() {
            val chars = "hi".toList()
            println(chars.size)
            println(chars.first())
            println(chars.last())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToListOps",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                out,
                """
                2
                h
                i
                """
                + "\n"
            )
        }
    }
}
