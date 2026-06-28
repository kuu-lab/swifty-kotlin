// STDLIB-TEXT-PROP-003: End-to-end execution tests for Char.directionality.
// kk_char_directionality returns the Kotlin CharDirectionality enum ordinal as a raw Int.
// Synthetic enums have no $enumOrdinalToName helper, so println prints the ordinal integer.
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

extension CodegenBackendIntegrationTests {

    // MARK: - Char.directionality ordinals

    func testCodegenCharDirectionalityOrdinals() throws {
        let source = """
        fun main() {
            println('A'.directionality)
            println('\\u05D0'.directionality)
            println('5'.directionality)
            println(' '.directionality)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharDirectionalityOrdinals",
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
                2
                4
                13
                """
                + "\n",
                "Expected LEFT_TO_RIGHT=1, RIGHT_TO_LEFT=2, EUROPEAN_NUMBER=4, WHITESPACE=13"
            )
        }
    }

    func testCodegenCharDirectionalityArabic() throws {
        let source = """
        fun main() {
            println('\\u0627'.directionality)
        }
        """

        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "CharDirectionalityArabic",
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)

            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout.replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, "3\n", "Arabic Alef should be RIGHT_TO_LEFT_ARABIC (ordinal 3)")
        }
    }
}
