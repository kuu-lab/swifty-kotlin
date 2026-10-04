import Testing

extension BundledStdlibExecutionTests {
    /// BUG-256 sibling: `List<T>.sumOf` (`ListAggregateHOF.kt`) only declares
    /// Int/Long/Double overloads. A UInt/ULong selector on a concrete List
    /// receiver used to silently arity-match onto the wrong (Int) overload --
    /// it linked, but reinterpreted the UInt/ULong bits as Int, so
    /// `listOf("a").sumOf { UInt.MAX_VALUE }` printed `-1` instead of
    /// `4294967295`.
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
