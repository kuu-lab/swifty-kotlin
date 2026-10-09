import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testJsSetViewSharesBackingAndConversionsAreCopies(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)

            import kotlin.js.collections.JsSet
            import kotlin.js.collections.toMutableSet
            import kotlin.js.collections.toSet

            fun main() {
                val minimum = mutableSetOf("x", "y", "z").asJsSetView()
                println("minimum:${minimum.toSet().size}")

                val backing = linkedSetOf<String?>("x", "y", "z", "y", null)
                val view: JsSet<String?> = backing.asJsSetView()
                val snapshot = view.toSet()
                val copy = view.toMutableSet()
                println("${view.toSet().joinToString(",")}:${view.toSet().size}")

                val added = backing.add("w")
                val duplicateAdded = backing.add("x")
                val removed = backing.remove("y")
                val missingRemoved = backing.remove("missing")
                println("${view.toSet().joinToString(",")}:$added:$duplicateAdded:$removed:$missingRemoved")

                copy.add("copy")
                copy.remove("x")
                copy.clear()
                println("${view.toSet().joinToString(",")}:${copy.size}:${snapshot.joinToString(",")}")

                backing.clear()
                println("${view.toSet().size}:${snapshot.size}")
                backing.add(null)
                backing.add("nullable")
                println(view.toMutableSet().joinToString("|"))

                val empty = mutableSetOf<String>().asJsSetView()
                println("empty:${empty.toSet().size}")
            }
            """,
            expectedOutput: "minimum:3\nx,y,z,null:4\nx,z,null,w:true:false:true:false\nx,z,null,w:0:x,y,z,null\n0:4\nnull|nullable\nempty:0\n",
            moduleName: "KUU1609JsSetView",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
