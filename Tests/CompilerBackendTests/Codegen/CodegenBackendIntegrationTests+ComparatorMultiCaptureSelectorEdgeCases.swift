#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// Follow-up to the closure-capture ABI fix in
/// CallLowerer+ClosureAdapters.swift: selector lambdas passed to
/// compareBy/compareValuesBy go through makeCollectionHOFSelectorArgument,
/// whose captureArguments were previously forwarded via the raw-only
/// makeClosureRawArgument instead of makeClosureRawOrBoxedArgument. A
/// selector capturing 2+ distinct locals would silently drop everything
/// but the first capture. These tests lock in the fix for all three
/// affected call sites (vararg compareBy/compareValuesBy selectors via
/// appendCollectionHOFSelectorPair, and the compareValuesBy(a, b, comparator)
/// { selector } path).
@Suite
struct CodegenBackendComparatorMultiCaptureSelectorEdgeCasesTests {

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
    func testCodegenCompilesCompareByVarargSelectorsWithMultiCaptureSelector() throws {
        let source = """
        fun main() {
            val hundredsDiv: Int = 100
            val tensBonus: Int = 3
            val cmp = compareBy<Int>(
                { x -> x / hundredsDiv + tensBonus },
                { x -> x % 100 / 10 },
                { x -> x % 10 },
                { x -> -x }
            )
            println(listOf(231, 132, 121, 221).sortedWith(cmp))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "CompareByVarargMultiCaptureSelector",
            expected: "[121, 132, 221, 231]\n"
        )
    }

    @Test
    func testCodegenCompilesCompareValuesByVarargSelectorsWithMultiCaptureSelector() throws {
        let source = """
        fun main() {
            val hundredsDiv: Int = 100
            val tensBonus: Int = 3
            println(compareValuesBy(231, 132,
                { x -> x / hundredsDiv + tensBonus },
                { x -> x % 100 / 10 },
                { x -> x % 10 },
                { x -> -x }
            ))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareValuesByVarargMultiCaptureSelector", expected: "1\n")
    }

    @Test
    func testCodegenCompilesCompareValuesByComparatorSelectorWithMultiCaptureSelector() throws {
        let source = """
        fun main() {
            val mul: Int = 10
            val off: Int = 1
            val ascending = compareBy<Int> { it }
            println(compareValuesBy(13, 25, ascending) { x -> x % mul + off })
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareValuesByComparatorMultiCaptureSelector", expected: "-1\n")
    }
}

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
#endif
