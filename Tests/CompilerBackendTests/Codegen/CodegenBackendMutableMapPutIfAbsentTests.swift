#if canImport(Testing)
@testable import CompilerCore
@testable import CompilerBackend
import Testing

@Suite
struct CodegenBackendMutableMapPutIfAbsentTests {
    @Test
    func testPutIfAbsentReferenceReproWithArtifactAtO0() throws {
        try assertReferenceRepro(optimization: .O0, allowDefaultStdlibLibrary: true)
    }

    @Test
    func testPutIfAbsentReferenceReproWithArtifactAtO2() throws {
        try assertReferenceRepro(optimization: .O2, allowDefaultStdlibLibrary: true)
    }

    @Test
    func testPutIfAbsentReferenceReproWithSourceStdlibAtO0() throws {
        try assertReferenceRepro(optimization: .O0, allowDefaultStdlibLibrary: false)
    }

    @Test
    func testPutIfAbsentReferenceReproWithSourceStdlibAtO2() throws {
        try assertReferenceRepro(optimization: .O2, allowDefaultStdlibLibrary: false)
    }

    private func assertReferenceRepro(
        optimization: OptimizationLevel,
        allowDefaultStdlibLibrary: Bool
    ) throws {
        let source = try diffCaseSource("kuu_1860_mutable_map_put_if_absent.kt", file: #filePath)
        try assertKotlinOutput(
            source,
            moduleName: "KUU1860MutableMapPutIfAbsent",
            expected: "null\nold\nnull\nnull=filled,present=old,new=first\n",
            optLevel: optimization,
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testPutIfAbsentUsesCustomDataClassKeyEquality(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        data class Vertex(val value: Int)
        fun main() {
            val adjacency: MutableMap<Vertex, MutableList<Int>> = linkedMapOf()
            val original = mutableListOf(2)
            println(adjacency.putIfAbsent(Vertex(1), original) == null)
            println(adjacency.putIfAbsent(Vertex(1), mutableListOf(3)) === original)
            println(adjacency[Vertex(1)] === original)
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KUU1860MutableMapCustomKey",
            expected: "true\ntrue\ntrue\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [false, true])
    func testPutIfAbsentPropagatesPutException(allowDefaultStdlibLibrary: Bool) throws {
        let source = """
        class PutFailureMap : AbstractMutableMap<String, String>() {
            override val entries: MutableSet<MutableMap.MutableEntry<String, String>>
                get() = mutableSetOf()
            override fun put(key: String, value: String): String? {
                throw IllegalStateException("put failed")
            }
        }
        fun main() {
            try {
                PutFailureMap().putIfAbsent("key", "value")
                println("missing exception")
            } catch (error: IllegalStateException) {
                println(error.message)
            }
        }
        """

        try assertKotlinOutput(
            source,
            moduleName: "KUU1860MutableMapPutException",
            expected: "put failed\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
