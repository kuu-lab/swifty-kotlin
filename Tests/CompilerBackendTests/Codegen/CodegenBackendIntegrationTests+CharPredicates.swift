@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {
    func testCodegenCharPredicateHelpersMatchExpectedOutput() throws {
        let source = """
        fun main() {
            println('A'.isLetter())
            println('1'.isDigit())
            println(' '.isWhitespace())
            println('7'.isLetterOrDigit())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharPredicatesRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\ntrue\ntrue\ntrue\n")
        }
    }

    // STDLIB-TEXT-PROP-008: Char.isIdentifierIgnorable end-to-end execution test
    func testCodegenCharIsIdentifierIgnorableMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\u00AD'.isIdentifierIgnorable())
            println('A'.isIdentifierIgnorable())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharIsIdentifierIgnorableRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\nfalse\n")
        }
    }

    // STDLIB-TEXT-PROP-015: Char.isSurrogate end-to-end execution test
    func testCodegenCharIsSurrogateMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\uD800'.isSurrogate())
            println('\\uDFFF'.isSurrogate())
            println('A'.isSurrogate())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharIsSurrogateRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(
                normalizedStdout,
                "true\ntrue\nfalse\n",
                "0xD800 and 0xDFFF are surrogates; 'A' is not"
            )
        }
    }

    // STDLIB-TEXT-PROP-016: Char.isTitleCase end-to-end execution test
    func testCodegenCharIsTitleCaseMatchesExpectedOutput() throws {
        let source = """
        fun main() {
            println('\\u01C5'.isTitleCase())
            println('A'.isTitleCase())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharIsTitleCaseRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "true\nfalse\n")
        }
    }

    func testCodegenCharCaseConversionHelpersHandleUnicodeMappings() throws {
        let source = """
        fun main() {
            println('ß'.uppercase())
            println('ǆ'.titlecase())
            println('İ'.lowercase())
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharCaseConversionRuntime",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "SS\nǅ\ni̇\n")
        }
    }
}
