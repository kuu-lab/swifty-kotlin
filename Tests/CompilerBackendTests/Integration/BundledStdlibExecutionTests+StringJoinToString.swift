import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testListOfStringJoinToStringDispatchesCharSequenceLength() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(listOf("A", "B").joinToString("|"))
            }
            """,
            expectedOutput: "A|B\n",
            moduleName: "KUU2430ListStringJoinToString"
        )
    }

    // KUU-3257: `lookupStdlibSymbol("List")` picked the `List(size, init)`
    // factory function over the interface when symbols arrive in sema-snapshot
    // order, so `sorted()` fabricated `List<T>` on a function symbol and the
    // following joinToString stayed unbound — linking a bare `_joinToString`.
    @Test(arguments: [true, false])
    func testSortedResultJoinToStringBindsIterableExtension(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(listOf(0.0, -0.0, 2.0).sorted().joinToString(","))
                val s = listOf(3.0, 1.0, 2.0).sorted()
                println(s.joinToString(","))
                println(listOf("b", "a").sorted().joinToString(","))
            }
            """,
            expectedOutput: "-0.0,0.0,2.0\n1.0,2.0,3.0\na,b\n",
            moduleName: "KUU3257SortedJoinToString",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
