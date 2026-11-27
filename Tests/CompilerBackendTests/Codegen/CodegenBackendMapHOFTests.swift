#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

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
