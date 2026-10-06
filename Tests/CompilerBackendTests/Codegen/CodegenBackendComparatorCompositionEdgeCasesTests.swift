#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

@Suite
struct CodegenBackendComparatorCompositionEdgeCasesTests {

    @Test(arguments: [0, 2], [false, true])
    func testBundledComparatorFactoriesPreserveFunctionCaptures(optimization: Int, stdlibFromSource: Bool) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/kuu_1283_comparator_factories.kt"
        ), encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "BundledComparatorFactories",
            expected: "made\n-1\n[1, 2, 3]\n[3, 2, 1]\n[3, 2, 1]\n"
                + "[2, 4, 1, 3]\n[4, 2, 3, 1]\n[2, 4, 1, 3]\n-1\n-1\n",
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            allowDefaultStdlibLibrary: !stdlibFromSource
        )
    }

    @Test(arguments: [0, 2], [false, true])
    func testThenComparingBinaryLambda(optimization: Int, stdlibFromSource: Bool) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/comparator_then_comparing.kt"
        ), encoding: .utf8)
        try assertKotlinOutput(
            source,
            moduleName: "ComparatorThenComparing",
            expected: "0\n-1\n1\n0\n7\n1\n2\n-2\n0\n9\n-2\n2\n2\n-1\n",
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            allowDefaultStdlibLibrary: !stdlibFromSource
        )
    }

    @Test(arguments: [0, 2], [false, true])
    func testCodegenCompareByDataClassDirectCompare(optimization: Int, stdlibFromSource: Bool) throws {
        let repoRoot = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent().deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
        let source = try String(contentsOf: repoRoot.appendingPathComponent(
            "Scripts/diff_cases/kuu_1209_compareby_data_class.kt"
        ), encoding: .utf8)

        try assertKotlinOutput(
            source,
            moduleName: "CompareByDataClassDirectCompare",
            expected: "1\n-1\n1\n-1\n0\n1\n2:0\n1\n4:2\n-1\n-1\n0\n1\n-1\n1\n1\n0\n1\n-1\n0\n"
                + "[1:1, 1:2, 1:2, 2:1]\n[2:1, 1:2, 1:2, 1:1]\n"
                + "[1:1, 1:2, 1:2, 2:1]\n[1:1, 1:2, 1:2, 2:1]\n-1\n1\na,cc,bbb\n",
            optLevel: try #require(OptimizationLevel(rawValue: optimization)),
            allowDefaultStdlibLibrary: !stdlibFromSource
        )
    }

    @Test
    func testCompareBySortsStringsWithInferredAndExplicitSelectorTypes() throws {
        let source = """
        fun main() {
            val words = listOf("bb", "ccc", "a")
            println(words.sortedWith(compareBy { it.length }))
            println(words.sortedWith(compareBy<String> { it.length }))
            val cmp = compareBy<String> { it.length }
            println(cmp.compare("bb", "ccc"))
            println(cmp.compare("ccc", "a"))
            println(cmp.compare("bb", "zz"))
        }
        """
        try assertKotlinOutput(
            source, moduleName: "CompareByStringSelector",
            expected: "[a, bb, ccc]\n[a, bb, ccc]\n-1\n1\n0\n"
        )
    }

    @Test
    func testCompareByPropagatesSelectorExceptionsThroughSamWrapper() throws {
        let source = """
        fun main() {
            val message = "selector failed"
            val cmp = compareBy<String> {
                if (it == "bad") throw IllegalArgumentException(message)
                it.length
            }
            try {
                println(cmp.compare("bad", "a"))
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            try {
                println(cmp.compare("a", "bad"))
            } catch (e: IllegalArgumentException) {
                println(e.message)
            }
            println(cmp.compare("bb", "a"))
        }
        """
        try assertKotlinOutput(
            source, moduleName: "CompareBySelectorExceptions",
            expected: "selector failed\nselector failed\n1\n"
        )
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

    // The fixed-arity 2/3-selector compareBy overloads were missing from the old
    // closure-argument expansion switch entirely, so selectors were passed as bare
    // fnPtrs with no closureRaw slot, desyncing every argument after the first
    // selector and crashing at runtime (SIGSEGV). KSP-461 moved every overload to
    // bundled Kotlin source; these tests keep the behavior covered.
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
