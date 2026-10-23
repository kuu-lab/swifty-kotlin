#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

/// RF-LOWER-CALL-011: end-to-end counterpart of
/// `ListSortExtremaLoweringRoutingTests`.
///
/// The comparator/selector, empty-input, null-key and equal-rank contracts for
/// the List `sorted*` / `min*` / `max*` families are already covered by
/// `Scripts/diff_cases/{list_sort_max_min,list_sorted_variants,list_max_min_with,
/// list_maxby_minby}.kt` — but only there, and that `diff_kotlinc.sh` CI step is
/// `continue-on-error`.  The execution tests below make them blocking, and the
/// IR tests pin that neither the source nor the artifact stdlib path redirects
/// a resolved Kotlin declaration to the legacy `kk_list_*` sorting/extrema
/// exports — of which only `kk_list_sortedBy` still has a `@_cdecl`, so a
/// redirect would fail at link time rather than produce a wrong answer.
///
/// Expected outputs were taken from kotlinc 2.x on the same sources.
@Suite
struct CodegenBackendListSortExtremaTests {
    /// The legacy `kk_list_*` sorting/extrema ABI surface, in LLVM IR call /
    /// declaration form.  The trailing `(` keeps `@kk_list_sorted` from
    /// matching `@kk_list_sortedWith`.
    private static let legacyListSortExtremaIRCallees = [
        "@kk_list_sorted(", "@kk_list_sorted_primitive(",
        "@kk_list_sortedBy(", "@kk_list_sortedBy_primitive(",
        "@kk_list_sortedDescending(", "@kk_list_sortedDescending_primitive(",
        "@kk_list_sortedByDescending(", "@kk_list_sortedByDescending_primitive(",
        "@kk_list_sortedWith(",
        "@kk_list_max(", "@kk_list_maxOrNull(", "@kk_list_maxBy(",
        "@kk_list_maxByOrNull(", "@kk_list_maxOfOrNull(",
        "@kk_list_min(", "@kk_list_minOrNull(", "@kk_list_minBy(",
        "@kk_list_minByOrNull(", "@kk_list_minOfOrNull(",
        // KSP-1511
        "@kk_list_shuffled(", "@kk_list_shuffled_random(",
    ]

    private func expectNoLegacySortExtremaIR(_ ir: String) {
        for legacy in Self.legacyListSortExtremaIRCallees {
            #expect(!ir.contains(legacy), "the legacy rewrite \(legacy) must not reach codegen")
        }
    }

    private func readGeneratedIR(_ ctx: CompilationContext) throws -> String {
        #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
        let llvmPath = try #require(ctx.generatedLLVMIRPath)
        return try String(contentsOfFile: llvmPath, encoding: .utf8)
    }

    // MARK: - no redirect to the legacy runtime exports

    /// Artifact path: explicitly select the shared precompiled `.kklib`
    /// so this test exercises imported stdlib symbols.
    @Test
    func listSortExtremaKeepSourceCalleesThroughStdlibArtifact() throws {
        try withTemporaryFile(contents: KotlinSourceFixtures.listSortExtremaCoverage) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "ListSortExtremaArtifactIR",
                emit: .llvmIR,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            expectNoLegacySortExtremaIR(try readGeneratedIR(ctx))
        }
    }

    /// Source path: the bundled stdlib is compiled alongside the module.
    @Test
    func listSortExtremaKeepSourceCalleesWithStdlibFromSource() throws {
        try withTemporaryFile(contents: KotlinSourceFixtures.listSortExtremaCoverage) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "ListSortExtremaSourceIR",
                emit: .llvmIR,
                outputPath: outputBase,
                allowDefaultStdlibLibrary: false
            )

            expectNoLegacySortExtremaIR(try readGeneratedIR(ctx))
        }
    }

    // MARK: - execution contracts

    /// KUU-553: compiling the bundled stdlib from source used to bind these
    /// calls to generic List<T>.min/minOrNull and return the first element.
    @Test
    func floatingPointListMinUsesIterableSpecializationsWithStdlibFromSource() throws {
        let source = """
        fun main() {
            println(listOf(3.0, 1.0).min())
            println(listOf(3.0f, 1.0f).min())
            println(listOf(3.0, 1.0).minOrNull())
            println(listOf(3.0f, 1.0f).minOrNull())
            println(listOf(Double.NaN, 1.0).min().isNaN())
            println(1.0 / listOf(0.0, -0.0).min())
            println(listOf(Float.NaN, 1.0f).min().isNaN())
            println(1.0f / listOf(0.0f, -0.0f).min())
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "FloatingPointListMinSourceRuntime",
            expected: "1.0\n1.0\n1.0\n1.0\ntrue\n-Infinity\ntrue\n-Infinity\n",
            allowDefaultStdlibLibrary: false
        )
    }

    /// Comparator- and selector-driven ordering, and the equal-rank rule:
    /// sorting is stable (equal keys keep input order) and the extrema pick the
    /// *first* element of an equal-ranked run.
    @Test
    func listSortExtremaPreserveComparatorSelectorAndEqualRankOrder() throws {
        let source = """
        fun main() {
            val words = listOf("bbb", "a", "cc")
            println(words.sortedBy { it.length })
            println(words.sortedByDescending { it.length })
            println(words.sortedWith(compareBy { it.length }))
            println(words.maxBy { it.length })
            println(words.minBy { it.length })
            println(words.maxOf { it.length })
            println(words.minOf { it.length })
            println(words.maxWith(compareBy { it.length }))
            println(words.minWith(compareBy { it.length }))
            println(words.maxOfWith(naturalOrder()) { it.length })
            println(words.minOfWith(naturalOrder()) { it.length })

            val ties = listOf("b2", "a1", "a2", "b1")
            println(ties.sortedBy { it[0] })
            println(ties.sortedWith(compareBy { it[0] }))
            println(ties.sortedByDescending { it[0] })
            println(ties.maxBy { it[0] })
            println(ties.minBy { it[0] })
            println(ties.maxWith(compareBy { it[0] }))
            println(ties.minWith(compareBy { it[0] }))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListSortExtremaComparatorRuntime",
            expected: """
            [a, cc, bbb]
            [bbb, cc, a]
            [a, cc, bbb]
            bbb
            a
            3
            1
            bbb
            a
            3
            1
            [a1, a2, b2, b1]
            [a1, a2, b2, b1]
            [b2, b1, a1, a2]
            b2
            a1
            b2
            a1

            """
        )
    }

    /// KUU-2749: a callable reference returning a primitive must cross the
    /// erased return ABI when captured by a generic sorting callback.
    @Test
    func genericListSortingBoxesCallableReferenceKeys() throws {
        let source = """
        fun <T, R : Comparable<R>> List<T>.swA(keyFn: (T) -> R): List<T> =
            this.sortedBy { keyFn(it) }

        fun <T, R : Comparable<R>> List<T>.swC(keyFn: (T) -> R): List<R> =
            this.map { keyFn(it) }.sortedBy { it }

        fun <T> List<T>.swConcrete(keyFn: (T) -> Int): List<Int> =
            this.map { keyFn(it) }.sortedBy { it }

        fun main() {
            val words = listOf("bbb", "a", "cc")
            println(words.swA(String::length))
            println(words.swC(String::length))
            println(words.swC { it.length })
            println(words.swConcrete(String::length))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KUU2749GenericCallableReferenceSorting",
            expected: "[a, cc, bbb]\n[1, 2, 3]\n[1, 2, 3]\n[1, 2, 3]\n"
        )
    }

    /// Comparator parameters erase their element type, so primitive candidates
    /// must be boxed before the Comparator bridge performs its generic cast.
    @Test
    func minMaxOfWithNaturalOrderBoxesPrimitiveCandidates() throws {
        let source = """
        import kotlin.comparisons.naturalOrder

        fun main() {
            println(minOf(3, 2, 1, comparator = naturalOrder<Int>()))
            println(maxOf(3, 2, 1, comparator = naturalOrder<Int>()))
            println(kotlin.comparisons.minOf(3, 2, 1, comparator = naturalOrder<Int>()))
            println(kotlin.comparisons.maxOf(3, 2, 1, comparator = naturalOrder<Int>()))
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "MinMaxOfNaturalOrderComparatorRuntime",
            expected: "1\n3\n1\n3\n"
        )
    }

    /// `sortedByDescending` takes a `R?` selector: null keys sort last in
    /// descending order, which `compareValues` — not a raw `compareTo` — has to
    /// supply.
    @Test
    func listSortedByDescendingOrdersNullKeysLast() throws {
        let source = """
        fun main() {
            val words = listOf("bb", "a", "ccc")
            println(words.sortedByDescending { if (it.length == 1) null else it.length })
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListSortedByDescendingNullKeyRuntime",
            expected: "[ccc, bb, a]\n"
        )
    }

    /// Empty input: every `*OrNull` form yields `null`, `sorted()` an empty
    /// list, and the non-null forms throw a catchable
    /// `NoSuchElementException`.
    @Test
    func listSortExtremaHandleEmptyInput() throws {
        let source = """
        fun main() {
            val empty = emptyList<String>()
            println(empty.sorted())
            println(empty.maxOrNull())
            println(empty.minOrNull())
            println(empty.maxByOrNull { it.length })
            println(empty.minByOrNull { it.length })
            println(empty.maxOfOrNull { it.length })
            println(empty.minOfOrNull { it.length })
            println(empty.maxWithOrNull(naturalOrder()))
            println(empty.minWithOrNull(naturalOrder()))
            println(empty.maxOfWithOrNull(naturalOrder()) { it.length })
            println(empty.minOfWithOrNull(naturalOrder()) { it.length })
            try { empty.max(); println("max-no-throw") } catch (e: NoSuchElementException) { println("max-throws") }
            try { empty.min(); println("min-no-throw") } catch (e: NoSuchElementException) { println("min-throws") }
            try { empty.maxOf { it.length }; println("maxOf-no-throw") } catch (e: NoSuchElementException) { println("maxOf-throws") }
            try { empty.maxWith(naturalOrder()); println("maxWith-no-throw") } catch (e: NoSuchElementException) { println("maxWith-throws") }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ListSortExtremaEmptyRuntime",
            expected: """
            []
            null
            null
            null
            null
            null
            null
            null
            null
            null
            null
            max-throws
            min-throws
            maxOf-throws
            maxWith-throws

            """
        )
    }
}
#endif
