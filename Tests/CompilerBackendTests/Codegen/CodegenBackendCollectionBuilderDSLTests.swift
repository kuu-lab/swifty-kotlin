#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
@testable import CompilerTestSupport
import Foundation
import Testing

@Suite
struct CodegenBackendCollectionBuilderDSLTests {
    /// Legacy runtime entry points the `CollectionLiteralLoweringPass` rewrite
    /// substitutes.  The trailing `(` keeps `__kk_build_list` from matching
    /// `__kk_build_list_with_capacity`, and none of them match the source-backed
    /// `__kk_builder_*` helpers.  The `set` pair is kept after
    /// RF-LOWER-CALL-005 deleted that rewrite, as a guard against its return.
    private static let legacyBuilderIRCallees = [
        "@__kk_build_list(", "@__kk_build_list_with_capacity(",
        "@__kk_build_set(", "@__kk_build_set_with_capacity(",
        "@__kk_build_map(", "@__kk_build_map_with_capacity(",
    ]

    private static let allOverloadsSource = """
    fun main() {
        val listNoCapacity = buildList { add(1) }
        val listWithCapacity = buildList(4) { add(2) }
        val setNoCapacity = buildSet { add("x") }
        val setWithCapacity = buildSet(4) { add("y") }
        val mapNoCapacity = buildMap { put("k", 1) }
        val mapWithCapacity = buildMap(4) { put("k", 2) }
        println(listNoCapacity.size + listWithCapacity.size)
        println(setNoCapacity.size + setWithCapacity.size)
        println(mapNoCapacity.size + mapWithCapacity.size)
    }
    """

    private func expectSourceBackedBuilderIR(_ ir: String) {
        for kind in ["list", "set", "map"] {
            #expect(ir.contains("@__kk_builder_\(kind)_new("), "expected the CollectionBuilders.kt allocator for \(kind)")
            #expect(ir.contains("@__kk_builder_\(kind)_freeze("), "expected the CollectionBuilders.kt freeze for \(kind)")
        }
        for legacy in Self.legacyBuilderIRCallees {
            #expect(!ir.contains(legacy), "the legacy rewrite \(legacy) must not reach codegen")
        }
    }

    private func readGeneratedIR(_ ctx: CompilationContext) throws -> String {
        #expect(!ctx.diagnostics.hasError, "diagnostics: \(ctx.diagnostics.diagnostics)")
        let llvmPath = try #require(ctx.generatedLLVMIRPath)
        return try String(contentsOfFile: llvmPath, encoding: .utf8)
    }

    @Test
    func builderDSLLowersToSourceBackedHelpersThroughStdlibArtifact() throws {
        try withTemporaryFile(contents: Self.allOverloadsSource) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try makeArtifactCompilationContext(
                inputs: [path],
                moduleName: "BuilderDSLArtifactIR",
                emit: .llvmIR,
                outputPath: outputBase
            )
            try runToKIR(ctx)
            try LoweringPhase().run(ctx)
            try CodegenPhase().run(ctx)

            expectSourceBackedBuilderIR(try readGeneratedIR(ctx))
        }
    }

    @Test
    func builderDSLLowersToSourceBackedHelpersWithStdlibFromSource() throws {
        try withTemporaryFile(contents: Self.allOverloadsSource) { path in
            let outputBase = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString)
                .path
            let ctx = try runCodegenPipeline(
                inputPath: path,
                moduleName: "BuilderDSLSourceIR",
                emit: .llvmIR,
                outputPath: outputBase,
                allowDefaultStdlibLibrary: false
            )

            expectSourceBackedBuilderIR(try readGeneratedIR(ctx))
        }
    }

    @Test
    func buildFamilyCapacityOverloadsPreserveContents() throws {
        let source = """
        fun main() {
            val list = buildList(4) { add(1); add(2) }
            println(list)
            println(list.size)
            val set = buildSet(4) { add("a"); add("a"); add("b") }
            println(set)
            println(set.size)
            val map = buildMap(4) { put("a", 1); put("a", 2); put("b", 3) }
            println(map)
            println(map.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildFamilyCapacityRuntime",
            expected: "[1, 2]\n2\n[a, b]\n2\n{a=2, b=3}\n2\n"
        )
    }

    @Test
    func buildFamilyNegativeCapacityThrowsIllegalArgumentException() throws {
        let source = """
        fun main() {
            try {
                buildList(-1) { add(1) }
                println("list-not-thrown")
            } catch (e: IllegalArgumentException) {
                println("list-thrown")
            }
            try {
                buildSet(-1) { add(1) }
                println("set-not-thrown")
            } catch (e: IllegalArgumentException) {
                println("set-thrown")
            }
            try {
                buildMap(-1) { put("a", 1) }
                println("map-not-thrown")
            } catch (e: IllegalArgumentException) {
                println("map-thrown")
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildFamilyNegativeCapacityRuntime",
            expected: "list-thrown\nset-thrown\nmap-thrown\n"
        )
    }

    @Test
    func buildFamilyFreezesReceiverLeakedFromBuilder() throws {
        let source = """
        fun main() {
            var leakedList: MutableList<Int>? = null
            val readOnlyList = buildList { leakedList = this; add(7) }
            try {
                leakedList!!.add(8)
                println("list-mutated")
            } catch (e: UnsupportedOperationException) {
                println("list-read-only")
            }
            println(readOnlyList)

            var leakedSet: MutableSet<Int>? = null
            val readOnlySet = buildSet { leakedSet = this; add(9) }
            try {
                leakedSet!!.add(10)
                println("set-mutated")
            } catch (e: UnsupportedOperationException) {
                println("set-read-only")
            }
            println(readOnlySet)

            var leakedMap: MutableMap<String, Int>? = null
            val readOnlyMap = buildMap { leakedMap = this; put("x", 1) }
            try {
                leakedMap!!.put("y", 2)
                println("map-mutated")
            } catch (e: UnsupportedOperationException) {
                println("map-read-only")
            }
            println(readOnlyMap)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "BuildFamilyFreezeRuntime",
            expected: "list-read-only\n[7]\nset-read-only\n[9]\nmap-read-only\n{x=1}\n"
        )
    }

    @Test
    func readOnlyMapRejectsMutableMapCastAndFrozenMutation() throws {
        let source = """
        fun main() {
            val m = mapOf("a" to 1)
            try {
                val mm = m as MutableMap<String, Int>
                mm.remove("a")
                println("mapOf-mutated size=" + m.size)
            } catch (e: ClassCastException) {
                println("mapOf-cce")
            } catch (e: UnsupportedOperationException) {
                println("mapOf-uoe")
            }
            println("mapOf-size=" + m.size)

            val bm = buildMap { put("x", 1) }
            try {
                (bm as MutableMap<String, Int>).clear()
                println("buildMap-mutated size=" + bm.size)
            } catch (e: ClassCastException) {
                println("buildMap-cce")
            } catch (e: UnsupportedOperationException) {
                println("buildMap-uoe")
            }
            println("buildMap-size=" + bm.size)

            val mutable = mutableMapOf("a" to 1)
            mutable["b"] = 2
            mutable.remove("a")
            println("mutable-size=" + mutable.size)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "ReadOnlyMapMutationRuntime",
            expected: "mapOf-cce\nmapOf-size=1\nbuildMap-uoe\nbuildMap-size=1\nmutable-size=1\n"
        )
    }
}
#endif
