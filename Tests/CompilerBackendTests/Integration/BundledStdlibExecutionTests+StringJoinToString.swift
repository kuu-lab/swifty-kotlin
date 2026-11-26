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
