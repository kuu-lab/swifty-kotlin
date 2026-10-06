#if canImport(Testing)
import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testIntRangeDotStepReturnsProgression(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            fun main() {
                println((1..10).step(3))
                println((1..10) step 3)
                println((1..3).step(2))
                println((1..10).step(4).toString())
                println((1..3).step(1))
                val range: IntRange = 1..10
                val progression = range.step(3)
                println(progression)
                println(progression.step)
                println(progression.toList())
                val erased: Any = progression
                println(erased)
                println(erased is IntProgression)
                println(erased is IntRange)
                println((1..10).step(3).step(2))
                println((10 downTo 1).step(3))
                println((5..3).step(2))
                println((1L..10L).step(3))
                println(('a'..'z').step(3))
                println((1u..10u).step(3))
                println((1uL..10uL).step(3))
            }
            """,
            expectedOutput: """
            1..10 step 3
            1..10 step 3
            1..3 step 2
            1..9 step 4
            1..3 step 1
            1..10 step 3
            3
            [1, 4, 7, 10]
            1..10 step 3
            true
            false
            1..9 step 2
            10 downTo 1 step 3
            5..3 step 2
            1..10 step 3
            a..y step 3
            1..10 step 3
            1..10 step 3

            """,
            moduleName: "KUU1260IntRangeDotStep",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
#endif
