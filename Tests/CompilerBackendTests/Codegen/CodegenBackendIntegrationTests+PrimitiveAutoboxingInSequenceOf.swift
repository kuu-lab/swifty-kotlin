@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

/// Keeps this regression test out of the monolithic XCTest discovery expression
/// generated for CodegenBackendIntegrationTests.
final class PrimitiveAutoboxingInSequenceOfTests: XCTestCase {
    private func runCodegenPipeline(
        inputPath: String,
        moduleName: String,
        emit: EmitMode,
        outputPath: String
    ) throws -> CompilationContext {
        let options = CompilerOptions(
            moduleName: moduleName,
            inputs: [inputPath],
            outputPath: outputPath,
            emit: emit,
            target: defaultTargetTriple()
        )
        let ctx = CompilationContext(
            options: options,
            sourceManager: SourceManager(),
            diagnostics: DiagnosticEngine(),
            interner: StringInterner()
        )
        try runToKIR(ctx)
        try LoweringPhase().run(ctx)
        try CodegenPhase().run(ctx)
        return ctx
    }

    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) throws {
        try withTemporaryFile(contents: source) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString).path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: moduleName,
                emit: .executable,
                outputPath: outputBase
            )
            try LinkPhase().run(ctx)
            let result = try CommandRunner.run(executable: outputBase, arguments: [])
            let normalizedStdout = result.stdout
                .replacingOccurrences(of: "\r\n", with: "\n")
            XCTAssertEqual(normalizedStdout, expected, file: file, line: line)
        }
    }

    func testPrimitiveArgumentBoxedWhenPassedToSequenceOf() throws {
        let source = """
        fun main() {
            // Reported bug: sequenceOf(...) stores its elements into the same
            // erased-to-Any backing array as listOf/setOf, but skipped boxing.
            val chars = sequenceOf('a', 'b', 'c').toList()
            println(chars)

            // Boolean elements must render as true/false, not 0/1.
            val flags = sequenceOf(true, false).toList()
            println(flags)

            // Double elements must render as their value, not the raw bit pattern.
            val reals = sequenceOf(1.5, 2.5).toList()
            println(reals)

            // Regression: Int elements still render as their decimal value.
            val nums = sequenceOf(100, 200).toList()
            println(nums)

            // `is` checks against Any must see the concrete boxed type, not a
            // raw unboxed word.
            val firstInt: Any = sequenceOf(1, 2, 3).first()
            println(firstInt is Int)

            val firstChar: Any = sequenceOf('x', 'y').first()
            println(firstChar is Char)
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "PrimitiveAutoboxingInSequenceOf",
            expected:
                """
                [a, b, c]
                [true, false]
                [1.5, 2.5]
                [100, 200]
                true
                true
                """
                + "\n"
        )
    }
}
