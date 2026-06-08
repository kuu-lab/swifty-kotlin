// TEST-CHAR-019: End-to-end execution tests for Char arithmetic and CharRange.forEach.
// Char.plus(Int) and Char.minus(Int) have no dedicated runtime symbol — they lower to
// kk_op_add/kk_op_sub via the IR, so codegen is the only layer that can verify them.
@testable import CompilerCore
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // MARK: - isISOControl

    func testCodegenCharIsISOControlBoundaries() throws {
        let source = """
        fun main() {
            println('\\u001f'.isISOControl())
            println(' '.isISOControl())
            println('\\u007f'.isISOControl())
            println('\\u009f'.isISOControl())
            println('\\u00a0'.isISOControl())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharIsISOControlExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                true
                false
                true
                true
                false
                """
                + "\n"
            )
        }
    }

    // MARK: - Char + Int

    func testCodegenCharPlusInt() throws {
        // Char.plus(Int) lowers to kk_op_add; .code extracts the result as Int for safe printing
        let source = """
        fun main() {
            println(('a' + 1).code)
            println(('A' + 25).code)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharPlusIntExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                98
                90
                """
                + "\n"
            )
        }
    }

    // MARK: - Char - Int

    func testCodegenCharMinusInt() throws {
        // Char.minus(Int) lowers to kk_op_sub; result type is Char, printed via .code
        let source = """
        fun main() {
            println(('b' - 1).code)
            println(('z' - 25).code)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharMinusIntExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                97
                97
                """
                + "\n"
            )
        }
    }

    // MARK: - Char - Char

    func testCodegenCharMinusChar() throws {
        // Char.minus(Char) dispatches to kk_char_minus and returns Int
        let source = """
        fun main() {
            println('b' - 'a')
            println('a' - 'b')
            println('z' - 'a')
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharMinusCharExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                1
                -1
                25
                """
                + "\n"
            )
        }
    }

    // MARK: - String[i]

    func testCodegenStringGetByIndex() throws {
        // String.get dispatches to kk_string_get; result is Char, printed via .code
        let source = """
        fun main() {
            println("hello"[1].code)
            println("world"[0].code)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "StringGetIndexExecution",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                101
                119
                """
                + "\n"
            )
        }
    }

    // MARK: - CharRange.forEach

    func testCodegenCharRangeForEachAscending() throws {
        let source = """
        fun main() {
            ('a'..'e').forEach { c -> println(c.code) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharRangeForEachAscending",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                97
                98
                99
                100
                101
                """
                + "\n"
            )
        }
    }

    func testCodegenCharRangeForEachEmpty() throws {
        // ('e'..'a') with implicit step=1 — first > last, so forEach iterates zero times
        let source = """
        fun main() {
            ('e'..'a').forEach { c -> println(c.code) }
            println("done")
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharRangeForEachEmpty",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "done\n")
        }
    }

    func testCodegenCharProgressionForEachDescending() throws {
        // 'e' downTo 'a' produces a CharProgression with step=-1
        let source = """
        fun main() {
            ('e' downTo 'a').forEach { c -> println(c.code) }
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharProgressionForEachDescending",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                """
                101
                100
                99
                98
                97
                """
                + "\n"
            )
        }
    }
}
