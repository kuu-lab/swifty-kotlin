@testable import CompilerCore
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

    func testCodegenCharCaseConversionHelpersHandleUnicodeMappings() throws {
        throw XCTSkip("Char case conversion feature not yet implemented")
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
