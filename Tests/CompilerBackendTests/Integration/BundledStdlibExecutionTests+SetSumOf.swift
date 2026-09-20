#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    /// KUU-608 regression: Set.sumOf must use the generic Iterable body. The
    /// indexed List.sumOf body is not valid for a RuntimeSetBox.
    @Test
    func testSetSumOfUsesIterableIterator() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(listOf(3, 1, 2).sumOf { it })
                println(setOf(3, 1, 2).sumOf { it })
            }
            """,
            expectedOutput: "6\n6\n"
        )
    }
}
#endif
