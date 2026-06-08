@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenArrayJoinToStringUsesDefaultSeparator() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayJoinToStringDefault",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1, 2, 3\n")
        }
    }

    func testCodegenArrayJoinToStringWithCustomSeparator() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString(" | "))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayJoinToStringSeparator",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "1 | 2 | 3\n")
        }
    }

    func testCodegenArrayJoinToStringWithPrefixAndPostfix() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.joinToString(separator = ":", prefix = "[", postfix = "]"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayJoinToStringPrefixPostfix",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "[1:2:3]\n")
        }
    }

    func testCodegenArrayJoinToStringOnEmptyArray() throws {
        let source = """
        fun main() {
            val empty = emptyArray<Int>()
            println(empty.joinToString())
            println(empty.joinToString(prefix = "<", postfix = ">"))
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ArrayJoinToStringEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "\n<>\n")
        }
    }
}
