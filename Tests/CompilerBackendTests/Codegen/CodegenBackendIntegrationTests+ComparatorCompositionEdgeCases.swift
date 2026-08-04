#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
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

@Suite
struct CodegenBackendComparatorCompositionEdgeCasesTests {

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
    func testCodegenCompilesCompareByVarargSelectors() throws {
        let source = """
        fun main() {
            val cmp = compareBy<Int>({ it / 100 }, { it % 100 / 10 }, { it % 10 }, { -it })
            println(listOf(231, 132, 121, 221).sortedWith(cmp))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareByVarargSelectors", expected: "[121, 132, 221, 231]\n")
    }

    // The fixed-arity 2/3-selector compareBy overloads (kk_comparator_from_multi_selectors,
    // kk_comparator_from_multi_selectors3) were missing from the closure-argument expansion
    // switch entirely, so selectors were passed as bare fnPtrs with no closureRaw slot,
    // desyncing every argument after the first selector and crashing at runtime (SIGSEGV).
    // Only the vararg overload (4+ selectors) was covered above.
    @Test
    func testCodegenCompilesCompareByFixedTwoSelectors() throws {
        let source = """
        fun main() {
            val cmp = compareBy<Int>({ it / 100 }, { it % 100 / 10 })
            println(listOf(231, 132, 121, 221).sortedWith(cmp))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareByFixedTwoSelectors", expected: "[121, 132, 221, 231]\n")
    }

    @Test
    func testCodegenCompilesCompareByFixedThreeSelectors() throws {
        let source = """
        fun main() {
            val cmp = compareBy<Int>({ it / 100 }, { it % 100 / 10 }, { it % 10 })
            println(listOf(231, 132, 121, 221).sortedWith(cmp))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareByFixedThreeSelectors", expected: "[121, 132, 221, 231]\n")
    }

    @Test
    func testCodegenCompilesCompareValuesByVarargSelectors() throws {
        let source = """
        fun main() {
            println(compareValuesBy(231, 132, { it / 100 }, { it % 100 / 10 }, { it % 10 }, { -it }))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareValuesByVarargSelectors", expected: "1\n")
    }

    // A selector bound to a local variable (rather than an inline lambda literal at the
    // call site) lowers to a boxed Function1 value (kk_function_create_1) instead of a bare
    // fnPtr symbolRef. makeCollectionHOFSelectorArgument used to return that boxed reference
    // as-is instead of re-pointing it at the resolved callableInfo's raw fnPtr symbol, so the
    // runtime trampoline tried to invoke the boxed object as a function pointer and crashed
    // (SIGBUS). This affects every fixed-arity compareBy/compareValuesBy selector helper, not
    // just the 1-selector case exercised here.
    @Test
    func testCodegenCompilesCompareValuesByFixedOneSelectorCapturingVariable() throws {
        let source = """
        fun main() {
            val mul = 10
            val off = 1
            val selector: (Int) -> Int = { x -> x % mul + off }
            println(compareValuesBy(13, 25, selector))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareValuesByFixedOneSelectorCapturingVariable", expected: "-1\n")
    }

    @Test
    func testCodegenCompilesComparatorThenByComparatorSelector() throws {
        let source = """
        fun main() {
            val primary = compareBy<Int> { it % 10 }
            val secondary = compareBy<Int> { it }
            val cmp = primary.thenBy(secondary) { it / 10 }
            println(listOf(23, 15, 13).sortedWith(cmp))
        }
        """

        try assertKotlinOutput(source, moduleName: "ComparatorThenByComparatorSelector", expected: "[13, 23, 15]\n")
    }

    @Test
    func testCodegenCompilesCompareValuesByComparatorSelector() throws {
        let source = """
        fun main() {
            val ascending = compareBy<Int> { it }
            println(compareValuesBy(13, 25, ascending) { it % 10 })
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareValuesByComparatorSelector", expected: "-1\n")
    }

    @Test
    func testCodegenCompilesComparatorThenByDescendingComparatorSelector() throws {
        let source = """
        fun main() {
            val primary = compareBy<Int> { it % 10 }
            val secondary = compareBy<Int> { it }
            val cmp = primary.thenByDescending(secondary) { it / 10 }
            println(listOf(23, 15, 13).sortedWith(cmp))
        }
        """

        try assertKotlinOutput(source, moduleName: "ComparatorThenByDescendingComparatorSelector", expected: "[23, 13, 15]\n")
    }

    @Test
    func testCodegenCompilesCompareByDescendingComparatorSelector() throws {
        let source = """
        fun main() {
            val byLength = compareByDescending<String, Int>(compareBy<Int> { it }) { it.length }
            println(listOf("pear", "fig", "apple").sortedWith(byLength))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareByDescendingComparatorSelector", expected: "[apple, pear, fig]\n")
    }

    @Test
    func testCodegenCompilesCompareByComparatorSelector() throws {
        let source = """
        fun main() {
            val byLength = compareBy<String, Int>(compareBy<Int> { it }) { it.length }
            println(listOf("pear", "fig", "apple").sortedWith(byLength))
        }
        """

        try assertKotlinOutput(source, moduleName: "CompareByComparatorSelector", expected: "[fig, pear, apple]\n")
    }

    // The 1-arg composition variants (thenByDescending { selector }, thenDescending { a, b -> },
    // thenComparator { a, b -> }) now lower through bundled Kotlin comparator source and are
    // consumed by sortedWith as Comparator objects. These tests keep the composition behavior
    // covered after the old kk_comparator_then_* runtime helpers were removed.

    @Test
    func testCodegenCompilesComparatorThenByDescendingSelector() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )
            // thenByDescending { selector }: group ascending, then score descending.
            val cmp = compareBy<Entry> { it.group }
                .thenByDescending { it.score }
            println(values.sortedWith(cmp).map { "${it.group}:${it.score}" })
        }
        """

        try assertKotlinOutput(source, moduleName: "ComparatorThenByDescendingSelector", expected: "[1:30, 1:20, 2:40, 2:10]\n")
    }

    @Test
    func testCodegenCompilesComparatorThenDescending() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )
            // thenDescending { a, b -> ... }: the comparison fn is reversed for the tie-break,
            // so an ascending score comparison becomes a descending tie-break.
            val cmp = compareBy<Entry> { it.group }
                .thenDescending { a, b -> a.score - b.score }
            println(values.sortedWith(cmp).map { "${it.group}:${it.score}" })
        }
        """

        try assertKotlinOutput(source, moduleName: "ComparatorThenDescending", expected: "[1:30, 1:20, 2:40, 2:10]\n")
    }

    @Test
    func testCodegenCompilesComparatorThenComparator() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )
            // thenComparator { a, b -> ... }: the comparison fn is used as-is for the tie-break,
            // so an ascending score comparison keeps the tie-break ascending.
            val cmp = compareBy<Entry> { it.group }
                .thenComparator { a, b -> a.score - b.score }
            println(values.sortedWith(cmp).map { "${it.group}:${it.score}" })
        }
        """

        try assertKotlinOutput(source, moduleName: "ComparatorThenComparator", expected: "[1:20, 1:30, 2:10, 2:40]\n")
    }

    @Test
    func testCodegenCompilesComparatorCompositionAndNullOrderingEdgeCases() throws {
        let source = """
        data class Entry(val group: Int, val score: Int)

        fun main() {
            val values = listOf(
                Entry(1, 30),
                Entry(1, 20),
                Entry(2, 10),
                Entry(2, 40),
            )

            val chained = compareBy<Entry> { it.group }
                .thenBy { -it.score }
            println(values.sortedWith(chained).map { "${it.group}:${it.score}" })

            println(values.sortedWith(chained.reversed()).map { "${it.group}:${it.score}" })

            val words = listOf("pear", "fig", "apple")
            println(words.sortedWith(reverseOrder()))

            val nullableValues = listOf(14, null, 3, null, 25, 17, 4)
            println(nullableValues.sortedWith(compareBy<Int?> { it }.nullsFirst()))
            println(nullableValues.sortedWith(compareBy<Int?> { it }.nullsLast()))
            println(nullableValues.sortedWith(nullsFirst(compareBy<Int> { it })))
            println(nullableValues.sortedWith(nullsLast(compareBy<Int> { it })))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ComparatorCompositionEdgeCases",
            expected:
                """
                [1:30, 1:20, 2:40, 2:10]
                [2:10, 2:40, 1:20, 1:30]
                [pear, fig, apple]
                [null, null, 3, 4, 14, 17, 25]
                [3, 4, 14, 17, 25, null, null]
                [null, null, 3, 4, 14, 17, 25]
                [3, 4, 14, 17, 25, null, null]
                """
                + "\n"
        )
    }
}
#endif
