import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testJsReadonlyArrayViewSharesBackingAndConversionsAreCopies(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.js.ExperimentalJsExport::class, kotlin.js.ExperimentalJsCollectionsApi::class)

            import kotlin.js.collections.JsReadonlyArray
            import kotlin.js.collections.toList
            import kotlin.js.collections.toMutableList

            fun main() {
                val backing = mutableListOf<Int?>(1, null, 3, 4)
                val view: JsReadonlyArray<Number?> = backing.asJsReadonlyArrayView()
                val snapshot = view.toList()
                val copy = view.toMutableList()

                backing[0] = 7
                backing.add(5)
                println("${view.toList().joinToString(",")}:${snapshot.joinToString(",")}:${copy.size}")

                copy.clear()
                println("${backing.size}:${snapshot.size}:${copy.size}")

                val immutableView = listOf(1, 2, 3, 4).asJsReadonlyArrayView()
                println(immutableView.toList().joinToString(","))

                val empty = listOf<Int>().asJsReadonlyArrayView()
                println(empty.toList().size)
            }
            """,
            expectedOutput: "7,null,3,4,5:1,null,3,4:4\n5:4:0\n1,2,3,4\n0\n",
            moduleName: "KUU1610JsReadonlyArrayView",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
