import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testMapDestructuringUnboxesPrimitiveValues(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val edgeWeights = mapOf("B" to 7.0)
                for ((vertex, edgeWeight) in edgeWeights) {
                    println("$vertex: ${5.0 + edgeWeight}")
                }
            }
            """,
            expectedOutput: "B: 12.0\n",
            moduleName: "MapDestructuringPrimitiveABI",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    // KUU-3242: `Map.entries`/`keys`/`values` (and `MutableMap.entries`)
    // resolve to the runtime ABI properties registered during stdlib
    // artifact builds. When the nested `Map.Entry`/`MutableEntry` shells are
    // absent at residual-registration time, `entries` ships without its
    // `__kk_map_entries` link and the runtime map box cannot answer the
    // virtual call. These views must stay iterable through the library path.
    @Test(arguments: [true, false])
    func testMapViewIterationUsesRuntimeLinks(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val m = mapOf("k" to "v")
                for (e in m.entries) { println("e:${e.key}->${e.value}") }
                for (k in m.keys) { println("k:$k") }
                for (v in m.values) { println("v:$v") }
                val mm = mutableMapOf("a" to 1)
                for (e in mm.entries) { println("me:${e.key}->${e.value}") }
            }
            """,
            expectedOutput: "e:k->v\nk:k\nv:v\nme:a->1\n",
            moduleName: "MapViewRuntimeLinks",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
