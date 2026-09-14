#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
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
    ]

    private static let allFamiliesSource = """
    fun main() {
        val nums = listOf(3, 1, 4, 1, 5)
        println(nums.sorted())
        println(nums.sortedDescending())
        println(nums.sortedBy { it })
        println(nums.sortedByDescending { it })
        println(nums.sortedWith { a, b -> a - b })
        println(nums.max())
        println(nums.min())
        println(nums.maxOrNull())
        println(nums.minOrNull())
        println(nums.maxBy { it })
        println(nums.minBy { it })
        println(nums.maxByOrNull { it })
        println(nums.minByOrNull { it })
        println(nums.maxOf { it })
        println(nums.minOf { it })
        println(nums.maxOfOrNull { it })
        println(nums.minOfOrNull { it })
        println(nums.maxWith { a, b -> a - b })
        println(nums.minWith { a, b -> a - b })
        println(nums.maxWithOrNull(naturalOrder()))
        println(nums.minWithOrNull(naturalOrder()))
        println(nums.maxOfWith(naturalOrder()) { it })
        println(nums.minOfWith(naturalOrder()) { it })
        println(nums.maxOfWithOrNull(naturalOrder()) { it })
        println(nums.minOfWithOrNull(naturalOrder()) { it })
    }
    """

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

    /// Artifact path: the stdlib comes from a precompiled `.kklib`.  The
    /// process-wide default artifact only applies to `emit == .executable`
    /// (`CompilerOptions.shouldUseDefaultStdlib`), so an IR-emitting test has
    /// to name the artifact itself to exercise this path at all.
    @Test
    func listSortExtremaKeepSourceCalleesThroughStdlibArtifact() throws {
        try withTemporaryFile(contents: Self.allFamiliesSource) { path in
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
        try withTemporaryFile(contents: Self.allFamiliesSource) { path in
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
