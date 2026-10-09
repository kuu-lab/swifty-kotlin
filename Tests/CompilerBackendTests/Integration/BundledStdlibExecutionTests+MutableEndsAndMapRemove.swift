import Testing

// KUU-1394: MutableList.addFirst/addLast and MutableMap.remove(key, value)
// are real JVM APIs (java.util.SequencedCollection members on List /
// java.util.Map.remove(key, value)) that the bundled stdlib lacks. Both are
// source-backed Kotlin extensions — pin them in the source and artifact
// stdlib profiles.
extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testMutableListAddFirstAddLastExecuteThroughBundledKotlin(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val l = mutableListOf(2, 3)
                l.addFirst(1)
                l.addLast(4)
                println(l)
                val e = mutableListOf<Int>()
                e.addLast(5)
                e.addFirst(0)
                println(e)
                val d = ArrayDeque<Int>()
                d.addFirst(1)
                d.addLast(2)
                println(d)
            }
            """,
            expectedOutput: "[1, 2, 3, 4]\n[0, 5]\n[1, 2]\n",
            moduleName: "KUU1394MutableListEnds",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testMutableMapRemoveKeyValueExecutesThroughBundledKotlin(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val m = mutableMapOf(1 to "a", 2 to "b")
                println(m.remove(1, "a"))
                println(m.remove(1, "a"))
                println(m.remove(2, "x"))
                println(m.remove(9, "a"))
                val n = mutableMapOf<String, Int?>("a" to null, "b" to 2)
                println(n.remove("a", null))
                println(n.remove("b", null))
                val p: MutableMap<out Int, String> = mutableMapOf(5 to "v")
                println(p.remove(5, "v"))
                println(m)
            }
            """,
            expectedOutput: "true\nfalse\nfalse\nfalse\ntrue\nfalse\ntrue\n{2=b}\n",
            moduleName: "KUU1394MapRemoveKeyValue",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
