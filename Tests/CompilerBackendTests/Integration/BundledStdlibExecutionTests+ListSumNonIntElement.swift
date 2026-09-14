import Testing

extension BundledStdlibExecutionTests {
    /// BUG-256: `ListCollectionOps.kt` only declares a concrete `List<Int>.sum()`
    /// overload. Calling `.sum()` directly on a `listOf(...)` chain (a
    /// concrete `List<T>` receiver) for any other element type never bound at
    /// all before this fix -- the generic `Iterable<T>.sum()` fallback
    /// refused List-like receivers by its own guard -- and leaked an
    /// unresolved `sum` callee through to the linker (KSWIFTK-LINK-0001).
    @Test
    func testListSumOnNonIntElementTypesExecutesThroughBundledKotlin() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println(listOf(1u, 2u, 3u).sum())
                println(listOf(1uL, 2uL, 3uL).sum())
                println(listOf(1L, 2L, 3L).sum())
                println(listOf(1.0, 2.0).sum())

                val emptyUInt: List<UInt> = listOf()
                println(emptyUInt.sum())

                val uintOverflow: List<UInt> = listOf(UInt.MAX_VALUE, 1u)
                println(uintOverflow.sum())
            }
            """,
            expectedOutput: """
            6
            6
            6
            3.0
            0
            0

            """
        )
    }
}
