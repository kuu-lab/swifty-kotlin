import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testJsMapViewSharesBackingAndConversionsAreCopies(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)

            import kotlin.js.collections.JsMap
            import kotlin.js.collections.toMap
            import kotlin.js.collections.toMutableMap

            fun main() {
                val backing = mutableMapOf<String?, Int?>("a" to 1, "b" to null, null to 4)
                val view: JsMap<String?, Int?> = backing.asJsMapView()
                val snapshot = view.toMap()
                val copy = view.toMutableMap()

                backing["a"] = 7
                backing["c"] = 3
                backing.remove("b")
                println("${view.toMap().size}:${view.toMap()["a"]}:${view.toMap().containsKey("b")}:${view.toMap()["c"]}:${view.toMap()[null]}")

                copy.clear()
                println("${backing.size}:${snapshot.size}:${snapshot["a"]}:${copy.size}")
                backing.clear()
                println(view.toMap().size)

                val empty = mutableMapOf<String, Int>().asJsMapView()
                println(empty.toMap().size)
            }
            """,
            expectedOutput: "3:7:false:3:4\n3:3:1:0\n0\n0\n",
            moduleName: "KUU1608JsMapView",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
