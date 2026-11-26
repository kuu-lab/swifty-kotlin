import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testListSumOfWithUnsignedSelectorExecutesThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                val values = listOf(1, 2, 3)
                println(values.sumOf { it.toUInt() })
                println(values.sumOf { it.toULong() })
                println(emptyList<Int>().sumOf { it.toUInt() })
                println(listOf("a").sumOf { UInt.MAX_VALUE })
            }
            """,
            expectedOutput: """
            6
            6
            0
            4294967295

            """
        )
    }
}
