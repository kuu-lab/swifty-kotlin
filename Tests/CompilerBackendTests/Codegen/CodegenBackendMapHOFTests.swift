#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Foundation
import Testing

/// RF-LOWER-CALL-012: end-to-end counterpart of `MapHOFLoweringRoutingTests`.
///
/// The IR tests pin that neither the source nor the artifact stdlib path
/// redirects a resolved Map HOF declaration to a legacy `kk_map_*` export —
/// none of which has a `@_cdecl` in `Sources/Runtime` any more, so a redirect
/// would fail at link time rather than produce a wrong answer. The execution
/// tests make the duplicate-key, insertion-order, List-vs-Map return
/// classification, and lambda-exception contracts blocking instead of only
/// covered by the `continue-on-error` `diff_kotlinc.sh` CI step
/// (`Scripts/diff_cases/map_hof.kt` and friends).
///
/// Expected outputs were taken from kotlinc 2.x on the same sources.
@Suite
struct CodegenBackendMapHOFTests {
    /// The legacy `kk_map_*` HOF ABI surface, in LLVM IR call / declaration
    /// form. The trailing `(` keeps `@kk_map_map` from matching a longer name
    /// with the same prefix.
    private static let legacyMapHOFIRCallees = [
        "@kk_map_map(", "@kk_map_filter(", "@kk_map_forEach(",
        "@kk_map_mapValues(", "@kk_map_mapKeys(",
        "@kk_map_filterKeys(", "@kk_map_filterValues(",
        "@kk_map_flatMap(", "@kk_map_any(", "@kk_map_all(", "@kk_map_none(",
        "@kk_map_maxByOrNull(", "@kk_map_minByOrNull(",
    ]

    private static let allFamiliesSource = """
    fun main() {
        val m: Map<String, Int> = mapOf("a" to 1, "b" to 2, "c" to 3)
        println(m.map { it.value })
        println(m.filter { it.value > 1 })
        println(m.filterNot { it.value > 1 })
        println(m.mapNotNull { if (it.value > 1) it.value else null })
        m.forEach { println(it.key) }
        println(m.mapValues { it.value * 2 })
        println(m.mapKeys { it.key + "!" })
        println(m.filterKeys { it != "a" })
        println(m.filterValues { it != 1 })
        println(m.flatMap { listOf(it.value, it.value) })
        println(m.any { it.value > 2 })
        println(m.all { it.value > 0 })
        println(m.none { it.value < 0 })
        println(m.maxByOrNull { it.value })
        println(m.minByOrNull { it.value })
    }
    """

    private func expectNoLegacyMapHOFIR(_ ir: String) {
        for legacy in Self.legacyMapHOFIRCallees {
            #expect(!ir.contains(legacy), "the legacy rewrite \(legacy) must not reach codegen")
        }
    }

    private func readGeneratedIR(_ ctx: CompilationContext) throws -> String {
        #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
        let llvmPath = try #require(ctx.generatedLLVMIRPath)
        return try String(contentsOfFile: llvmPath, encoding: .utf8)
    }

    // MARK: - no redirect to the legacy runtime exports

    /// Artifact path: the stdlib comes from a precompiled `.kklib`. The
    /// process-wide default artifact only applies to `emit == .executable`
    /// (`CompilerOptions.shouldUseDefaultStdlib`), so an IR-emitting test has
    /// to name the artifact itself to exercise this path at all.
    @Test
    func mapHOFKeepSourceCalleesThroughStdlibArtifact() throws {
        try withTemporaryFile(contents: Self.allFamiliesSource) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "MapHOFArtifactIR",
                emit: .llvmIR,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            expectNoLegacyMapHOFIR(try readGeneratedIR(ctx))
        }
    }

    /// Source path: the bundled stdlib is compiled alongside the module.
    @Test
    func mapHOFKeepSourceCalleesWithStdlibFromSource() throws {
        try withTemporaryFile(contents: Self.allFamiliesSource) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "MapHOFSourceIR",
                emit: .llvmIR,
                outputPath: outputBase,
                allowDefaultStdlibLibrary: false
            )

            expectNoLegacyMapHOFIR(try readGeneratedIR(ctx))
        }
    }

    // MARK: - execution contracts

    /// Duplicate transformed keys in `mapKeys`: last write wins, matching
    /// `LinkedHashMap` put semantics. `11 to "eleven"` and `1 to "one"` both
    /// transform to key `1`; the later source entry (`1 to "one"`) is the one
    /// that survives, overwriting the value from `11 to "eleven"`.
    @Test
    func mapKeysCollapsesDuplicateTransformedKeysKeepingTheLastWrite() throws {
        let source = """
        fun main() {
            val m = mapOf(11 to "eleven", 1 to "one", 2 to "two")
            val collapsed = m.mapKeys { it.key % 10 }
            println(collapsed.size)
            println(collapsed[1])
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MapKeysDuplicateRuntime",
            expected: """
            2
            one

            """
        )
    }

    /// Insertion order survives `filterKeys` / `filterValues` / `mapValues`:
    /// the surviving entries keep the receiver's original iteration order,
    /// not sorted or reversed.
    @Test
    func filterAndTransformPreserveInsertionOrder() throws {
        let source = """
        fun main() {
            val m = linkedMapOf(3 to "c", 1 to "a", 2 to "b", 4 to "d")
            println(m.filterKeys { it != 1 }.keys.joinToString(","))
            println(m.filterValues { it != "a" }.keys.joinToString(","))
            println(m.mapValues { it.value.uppercase() }.keys.joinToString(","))
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MapHOFInsertionOrderRuntime",
            expected: """
            3,2,4
            3,2,4
            3,1,2,4

            """
        )
    }

    /// `map` / `flatMap` return a `List` in receiver iteration order, and
    /// `filter` / `mapValues` / `mapKeys` return a `Map` — the classification
    /// this Lowering pass' `+PreScan.swift` seeding (not the deleted rewrite
    /// branch) is responsible for keeping correct downstream.
    @Test
    func mapAndFlatMapReturnListsInIterationOrderWhileFilterAndTransformReturnMaps() throws {
        let source = """
        fun main() {
            val m = linkedMapOf(1 to "a", 2 to "bb", 3 to "ccc")
            val mapped: List<Int> = m.map { it.value.length }
            println(mapped)
            val flatMapped: List<Int> = m.flatMap { listOf(it.key, it.value.length) }
            println(flatMapped)
            val filtered: Map<Int, String> = m.filter { it.key > 1 }
            println(filtered.size)
            println(filtered[2])
            val transformed: Map<Int, Int> = m.mapValues { it.value.length }
            println(transformed.size)
            println(transformed[3])
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MapHOFReturnClassificationRuntime",
            expected: """
            [1, 2, 3]
            [1, 1, 2, 2, 3, 3]
            2
            bb
            3
            3

            """
        )
    }

    /// A lambda exception thrown from inside `mapValues` / `filter` must
    /// propagate out of the call as a normal catchable exception, not be
    /// swallowed or turned into a different failure mode.
    @Test
    func lambdaExceptionsPropagateOutOfMapValuesAndFilter() throws {
        let source = """
        fun main() {
            val m = mapOf("a" to 1, "b" to 2, "c" to 3)
            try {
                m.mapValues { if (it.key == "b") throw RuntimeException("mapValues-boom") else it.value }
                println("mapValues-no-throw")
            } catch (e: RuntimeException) {
                println("mapValues-caught: ${e.message}")
            }
            try {
                m.filter { if (it.key == "c") throw RuntimeException("filter-boom") else it.value > 0 }
                println("filter-no-throw")
            } catch (e: RuntimeException) {
                println("filter-caught: ${e.message}")
            }
        }
        """
        try assertKotlinOutput(
            source,
            moduleName: "MapHOFLambdaExceptionRuntime",
            expected: """
            mapValues-caught: mapValues-boom
            filter-caught: filter-boom

            """
        )
    }
}
#endif
