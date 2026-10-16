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
}
