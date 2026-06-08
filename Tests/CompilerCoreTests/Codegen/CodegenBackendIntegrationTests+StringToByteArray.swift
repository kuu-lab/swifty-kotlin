// STDLIB-TEXT-FN-092: End-to-end execution tests for String.toByteArray().
// toByteArray() is typed as List<Int> by Sema (via kk_string_toByteArray), so
// .size and [i] use the list accessor path, not the ByteArray/array path.
@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // MARK: - String.toByteArray() no-arg

    func testCodegenStringToByteArrayNoArg() throws {
        let source = """
        fun main() {
            val bytes = "abc".toByteArray()
            println(bytes.size)
            println(bytes[0])
            println(bytes[1])
            println(bytes[2])
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToByteArrayNoArg",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            // "abc" in UTF-8: a=97, b=98, c=99
            XCTAssertEqual(out, "3\n97\n98\n99\n")
        }
    }

    // MARK: - String.toByteArray(charset) variants

    func testCodegenStringToByteArrayCharsets() throws {
        let source = """
        fun main() {
            val utf8 = "hello".toByteArray(Charsets.UTF_8)
            println(utf8.size)

            val latin1 = "hello".toByteArray(Charsets.ISO_8859_1)
            println(latin1.size)

            val ascii = "hello".toByteArray(Charsets.US_ASCII)
            println(ascii.size)

            // UTF-16BE: 2 bytes per BMP char, no BOM
            val utf16be = "ab".toByteArray(Charsets.UTF_16BE)
            println(utf16be.size)

            // UTF-16LE: 2 bytes per BMP char, no BOM
            val utf16le = "ab".toByteArray(Charsets.UTF_16LE)
            println(utf16le.size)
        }
        """
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringToByteArrayCharsets",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let out = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(out, "5\n5\n5\n4\n4\n")
        }
    }
}
