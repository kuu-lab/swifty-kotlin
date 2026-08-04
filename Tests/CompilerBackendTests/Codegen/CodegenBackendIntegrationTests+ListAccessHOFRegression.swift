@testable import CompilerCore
@testable import CompilerBackend
import Foundation
#if canImport(Testing)
import Testing

private func runCodegenPipeline(
    inputPath: String,
    moduleName: String,
    emit: EmitMode,
    outputPath: String,
    irFlags: [String] = []
) throws -> CompilationContext {
    let options = CompilerOptions(
        moduleName: moduleName,
        inputs: [inputPath],
        outputPath: outputPath,
        emit: emit,
        target: defaultTargetTriple(),
        irFlags: irFlags
    )
    let ctx = CompilationContext(
        options: options,
        sourceManager: SourceManager(),
        diagnostics: DiagnosticEngine(),
        interner: StringInterner()
    )
    try runToKIR(ctx)
    try LoweringPhase().run(ctx)
    if emit == .kirDump {
        guard let kir = ctx.kir else {
            throw CompilerPipelineError.invalidInput("KIR not available for dump.")
        }
        let path = outputPath + ".kir"
        let dump = kir.dump(interner: ctx.interner, symbols: ctx.sema?.symbols)
        try dump.write(to: URL(fileURLWithPath: path), atomically: true, encoding: .utf8)
    } else {
        try CodegenPhase().run(ctx)
    }
    return ctx
}

// KSP-424 regression tests: List access helpers must lower to bundled Kotlin
// source rather than stale kk_* runtime entries.
@Suite
struct CodegenBackendListAccessHOFRegressionTests {
    private func assertKotlinOutput(
        _ source: String,
        moduleName: String,
        expected: String
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
            #expect(normalizedStdout == expected)
        }
    }

    @Test
    func testCodegenListGetOrNullAndGetOrElseUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            println(nums.getOrNull(1))
            println(nums.getOrNull(5))
            println(nums.getOrElse(1) { -1 })
            println(nums.getOrElse(5) { it * 10 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListGetOrNullSource",
            expected: "20\nnull\n20\n50\n"
        )
    }

    @Test
    func testCodegenListElementAtAndOrNullAndOrElseUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            println(nums.elementAt(1))
            println(nums.elementAtOrNull(1))
            println(nums.elementAtOrNull(5))
            println(nums.elementAtOrElse(1) { -1 })
            println(nums.elementAtOrElse(5) { it * 10 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListElementAtSource",
            expected: "20\n20\nnull\n20\n50\n"
        )
    }

    @Test
    func testCodegenListElementAtThrowsOnOutOfBounds() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            try {
                println(nums.elementAt(5))
            } catch (e: IndexOutOfBoundsException) {
                println("caught")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListElementAtThrows",
            expected: "caught\n"
        )
    }

    @Test
    func testCodegenListSingleAndSingleOrNullUseSourceImplementation() throws {
        let source = """
        fun main() {
            val one = listOf(42)
            println(one.single())
            println(one.singleOrNull())
            val nums = listOf(10, 20, 30)
            println(nums.singleOrNull())
            println(nums.single { it > 25 })
            println(nums.singleOrNull { it > 25 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListSingleSource",
            expected: "42\n42\nnull\n30\n30\n"
        )
    }

    @Test
    func testCodegenListFirstAndLastUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(10, 20, 30)
            println(nums.first())
            println(nums.last())
            println(nums.first { it > 15 })
            println(nums.last { it < 25 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListFirstLastSource",
            expected: "10\n30\n20\n20\n"
        )
    }
}
#endif
