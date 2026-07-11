@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import XCTest

final class UsePinnedEdgeCaseTests: XCTestCase {
    // Regression for the same beginFinallyGuard/endFinallyGuard gap fixed for
    // scopeUse: usePinned nested inside an outer try/catch must still let the
    // exception propagate to that catch after its own finally (unpin()) runs.
    func testCodegenCompilesUsePinnedEdgeCases() throws {
        let source = """
        import kotlinx.cinterop.ExperimentalForeignApi
        import kotlinx.cinterop.Pinned
        import kotlinx.cinterop.usePinned

        class Box(var value: Int)

        @ExperimentalForeignApi
        fun main() {
            val ok = Box(1)
            val result = ok.usePinned { pinned: Pinned<Box> ->
                println("use:ok")
                pinned.get().value
            }
            println(result)

            val fail = Box(2)
            try {
                fail.usePinned { pinned: Pinned<Box> ->
                    println("use:fail")
                    error("boom")
                }
            } catch (e: Throwable) {
                println("caught:${e.message}")
            }
            println("after")
        }
        """

        try assertUsePinnedKotlinOutput(
            source,
            moduleName: "UsePinnedEdgeCases",
            expected:
                """
                use:ok
                1
                use:fail
                caught:boom
                after
                """
                + "\n"
        )
    }
}

private func runUsePinnedCodegenPipeline(
    inputPath: String,
    moduleName: String,
    outputPath: String
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: .executable,
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

private func assertUsePinnedKotlinOutput(
    _ source: String,
    moduleName: String,
    expected: String,
    file: StaticString = #filePath,
    line: UInt = #line
) throws {
    try withTemporaryFile(contents: source) { path in
        let outputBase = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString).path
        let ctx = try runUsePinnedCodegenPipeline(
            inputPath: path,
            moduleName: moduleName,
            outputPath: outputBase
        )
        try LinkPhase().run(ctx)
        let result = try CommandRunner.run(executable: outputBase, arguments: [])
        let normalizedStdout = result.stdout
            .replacingOccurrences(of: "\r\n", with: "\n")
        XCTAssertEqual(normalizedStdout, expected, file: file, line: line)
    }
}
