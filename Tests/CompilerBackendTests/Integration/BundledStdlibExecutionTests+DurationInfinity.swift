import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testDurationDivisionPreservesCapturedNegativeZero() throws {
        try compileAndRunKotlin(
            """
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.seconds

            fun divideCaptured(duration: Duration, scale: Double): Duration {
                val operation: () -> Duration = { duration / scale }
                return operation()
            }

            fun main() {
                for (duration in listOf(Duration.INFINITE, -Duration.INFINITE, 1.seconds, (-1).seconds)) {
                    for (scale in listOf(-0.0, 0.0)) {
                        val operation: () -> Duration = { duration / scale }
                        val withParameter: (Double) -> Duration = { duration / it }
                        println(duration / scale)
                        println(operation())
                        println(divideCaptured(duration, scale))
                        println(withParameter(scale))
                    }
                }
            }
            """,
            expectedOutput: """
            -Infinity
            -Infinity
            -Infinity
            -Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            -Infinity
            -Infinity
            -Infinity
            -Infinity
            -Infinity
            -Infinity
            -Infinity
            -Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            Infinity
            -Infinity
            -Infinity
            -Infinity
            -Infinity

            """,
            moduleName: "KUU1185DurationCapturedNegativeZero"
        )
    }

    @Test
    func testDurationInfinityArithmeticPreservesInfinity() throws {
        try compileAndRunKotlin(
            """
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.seconds
            import kotlin.time.Duration.Companion.milliseconds

            fun main() {
                val negative = Duration.parse("-Infinity")
                val positive = Duration.parse("Infinity")
                println(negative + 1.seconds)
                println(1.seconds + negative)
                println(positive + (-1).seconds)
                println((-1).seconds + positive)
                println(negative - 1.seconds)
                println(1.seconds - negative)
                println(positive - positive.unaryMinus())
                println(negative + negative)
                println(positive + positive)
                println(negative + 4_611_686_018_427_387_902L.milliseconds)
                println(-negative)
                println(negative.absoluteValue)
                println(negative * 2)
                println(negative * -2)
                println(negative / 2)
                println(negative / -2)
                println(negative * 0.5)
                println(negative * -0.5)
                println(negative / 0.5)
                println(negative / -0.5)
                println((negative / positive).isNaN())
                println(1.seconds / Double.POSITIVE_INFINITY == 0.seconds)
            }
            """,
            expectedOutput: """
            -Infinity
            -Infinity
            Infinity
            Infinity
            -Infinity
            Infinity
            Infinity
            -Infinity
            Infinity
            -Infinity
            Infinity
            Infinity
            -Infinity
            Infinity
            -Infinity
            Infinity
            -Infinity
            Infinity
            -Infinity
            Infinity
            true
            true

            """,
            moduleName: "KUU1185DurationInfinity"
        )
    }

    @Test
    func testDurationInfinityUndefinedArithmeticThrowsIllegalArgumentException() throws {
        try compileAndRunKotlin(
            """
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.seconds

            fun report(operation: () -> Duration) {
                try {
                    println(operation())
                } catch (e: IllegalArgumentException) {
                    println(e.message)
                }
            }

            fun main() {
                val positive = Duration.INFINITE
                val negative = Duration.parse("-Infinity")
                report { positive + negative }
                report { negative + positive }
                report { positive - positive }
                report { negative - negative }
                report { positive * 0 }
                report { negative * 0.0 }
                report { 0.seconds / 0 }
                report { 0.seconds / 0.0 }
                report { positive / Double.POSITIVE_INFINITY }
                report { negative / Double.NEGATIVE_INFINITY }
                println(positive / 0)
                println(negative / 0)
                println(positive / -0.0)
                println(negative / -0.0)
            }
            """,
            expectedOutput: """
            Summing infinite durations of different signs yields an undefined result.
            Summing infinite durations of different signs yields an undefined result.
            Summing infinite durations of different signs yields an undefined result.
            Summing infinite durations of different signs yields an undefined result.
            Multiplying infinite duration by zero yields an undefined result.
            Multiplying infinite duration by zero yields an undefined result.
            Dividing zero duration by zero yields an undefined result.
            Duration value cannot be NaN.
            Duration value cannot be NaN.
            Duration value cannot be NaN.
            Infinity
            -Infinity
            -Infinity
            Infinity

            """,
            moduleName: "KUU1185DurationUndefinedArithmetic"
        )
    }
}
