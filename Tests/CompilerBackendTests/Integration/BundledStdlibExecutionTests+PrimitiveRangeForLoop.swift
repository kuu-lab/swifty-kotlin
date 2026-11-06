import Testing

extension BundledStdlibExecutionTests {
    /// KUU-4349: `for (x in range)` must accept bundled primitive iterators whose
    /// `next`/`hasNext` overrides omit the `operator` keyword — Kotlin inherits the
    /// modifier through the `Iterator` supertype (KSP-452 removed the range-specific
    /// lowering, so loops go through the generic iterator convention).
    @Test(arguments: [true, false])
    func testPrimitiveRangeForLoop(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                for (i in 1..3) println(i)
                for (i in 1 until 4) println(i)
                for (i in 5 downTo 1 step 2) println(i)
                for (l in 1L..3L) println(l)
                for (c in 'a'..'c') println(c)
                for (u in 1u..3u) println(u)
                for (ul in 1uL..3uL) println(ul)
                val r: IntRange = 10..12
                for (i in r) println(i)
            }
            """,
            expectedOutput: """
            1
            2
            3
            1
            2
            3
            5
            3
            1
            1
            2
            3
            a
            b
            c
            1
            2
            3
            1
            2
            3
            10
            11
            12

            """,
            moduleName: "KUU4349PrimitiveRangeForLoop",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
