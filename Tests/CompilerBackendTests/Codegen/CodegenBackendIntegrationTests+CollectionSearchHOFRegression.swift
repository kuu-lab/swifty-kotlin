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

// KSP-423 regression tests: predicate first/last and Array.contains must lower
// to bundled Kotlin source rather than stale kk_* runtime entries.
@Suite
struct CodegenBackendCollectionSearchHOFRegressionTests {

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
    func codegenListFirstAndLastPredicateUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(2, 4, 3, 4, 5)
            println(nums.first { it > 3 })
            println(nums.last { it < 4 })
            println(nums.find { it > 3 })
            println(nums.firstOrNull { it > 4 })
            println(nums.lastOrNull { it > 4 })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListFirstLastPredicateSource",
            expected: "4\n3\n4\n5\n5\n"
        )
    }

    @Test
    func codegenArrayContainsUsesSourceImplementation() throws {
        let source = """
        fun main() {
            val arr = arrayOf(1, 2, 3)
            println(arr.contains(2))
            println(arr.contains(4))
            println(arr.indexOf(2))
            println(arr.lastIndexOf(2))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ArrayContainsSource",
            expected: "true\nfalse\n1\n1\n"
        )
    }

    @Test
    func codegenListAnyNoneCountUseSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(1, 2, 3)
            println(nums.any())
            println(nums.none())
            println(nums.count())
            val empty = listOf<Int>()
            println(empty.any())
            println(empty.none())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListAnyNoneCountSource",
            expected: "true\nfalse\n3\nfalse\ntrue\n"
        )
    }

    @Test
    func codegenListBinarySearchUsesSourceImplementation() throws {
        let source = """
        fun main() {
            val nums = listOf(1, 3, 5, 7, 9)
            println(nums.binarySearch(5))
            println(nums.binarySearch(4))
            println(nums.binarySearch(5, 1, 4))
            println(nums.binarySearch { it - 7 })
            println(nums.binarySearchBy(7) { it })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListBinarySearchSource",
            expected: "2\n-3\n2\n3\n3\n"
        )
    }
}
#endif
