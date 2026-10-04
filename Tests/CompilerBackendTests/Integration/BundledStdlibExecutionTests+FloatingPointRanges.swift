import Testing

extension BundledStdlibExecutionTests {
    // KUU-574 regression: floating-point ranges use opaque runtime handles while
    // their source-level expression type remains scalar. Membership, emptiness,
    // and string conversion must therefore all select the floating-point bridge.
    @Test
    func testFloatingPointRangesMembershipAndStringification() throws {
        try compileAndRunKotlin(
            """
            fun main() {
                // KUU-748 regression: a range literal used directly as the
                // `in` receiver must keep its floating-point element type.
                println(0.5 in 0.0..1.0)
                println(0.0 in 0.0..1.0)
                println(1.0 in 0.0..1.0)
                println(1.5 in 0.0..1.0)
                println(0.5f in 0.0f..1.0f)
                println(1.5 in 1.0..2.0)

                val doubleClosed = 1.0..10.50
                println(10.50 in doubleClosed)
                println(doubleClosed.contains(10.50))
                println(doubleClosed.isEmpty())
                println(doubleClosed.toString())
                println(doubleClosed)
                println(0.5 !in doubleClosed)
                println((1.0..Double.NaN).isEmpty())

                val floatClosed = 1.0f..10.50f
                println(10.50f in floatClosed)
                println(floatClosed.contains(10.50f))
                println(floatClosed.isEmpty())
                println(floatClosed.toString())
                println(floatClosed)
                println(0.5f !in floatClosed)
                println((1.0f..Float.NaN).isEmpty())

                val doubleOpen = 1.0..<10.50
                println(10.0 in doubleOpen)
                println(5.0f in doubleOpen)
                println(doubleOpen.contains(5.0f))
                println(10.50 in doubleOpen)
                println(doubleOpen.contains(10.50))
                println(doubleOpen.isEmpty())
                println(doubleOpen.toString())
                println(doubleOpen)

                val floatOpen = 1.0f..<10.50f
                println(10.0f in floatOpen)
                println(10.50f in floatOpen)
                println(floatOpen.contains(10.50f))
                println(floatOpen.isEmpty())
                println(floatOpen.toString())
                println(floatOpen)
            }
            """,
            expectedOutput: """
            true
            true
            true
            false
            true
            true
            true
            true
            false
            1.0..10.5
            1.0..10.5
            true
            true
            true
            true
            false
            1.0..10.5
            1.0..10.5
            true
            true
            true
            true
            true
            false
            false
            false
            1.0..<10.5
            1.0..<10.5
            true
            false
            false
            false
            1.0..<10.5
            1.0..<10.5

            """,
            moduleName: "FloatingPointRanges"
        )
    }
}
