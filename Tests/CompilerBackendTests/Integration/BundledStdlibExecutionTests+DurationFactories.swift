import Testing

extension BundledStdlibExecutionTests {
    @Test(arguments: [true, false])
    func testDurationCompanionMillisecondsAndTimeout(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.time.Duration.Companion.milliseconds
            import kotlin.time.DurationUnit
            import kotlin.time.toDuration
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                println(1.milliseconds.inWholeNanoseconds)
                println(1L.milliseconds.inWholeNanoseconds)
                println(1.0.milliseconds.inWholeNanoseconds)
                println(0.milliseconds.inWholeNanoseconds)
                println((-1).milliseconds.inWholeNanoseconds)
                println(1.toDuration(DurationUnit.MILLISECONDS).inWholeNanoseconds)
                println(1L.toDuration(DurationUnit.MILLISECONDS).inWholeNanoseconds)
                println(1.0.toDuration(DurationUnit.MILLISECONDS).inWholeNanoseconds)
                println(withTimeoutOrNull(1.milliseconds) { delay(5000); 42 })
                println(withTimeoutOrNull(1L.milliseconds) { delay(5000); 42 })
                println(withTimeoutOrNull(1.0.milliseconds) { delay(5000); 42 })
                println(withTimeoutOrNull(1000.milliseconds) { 42 })
            }
            """,
            expectedOutput: "1000000\n1000000\n1000000\n0\n-1000000\n1000000\n1000000\n1000000\nnull\nnull\nnull\n42\n",
            moduleName: "KUU1341DurationFactories",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }

    @Test(arguments: [true, false])
    func testWithTimeoutNonPositiveDuration(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.time.Duration.Companion.milliseconds
            import kotlinx.coroutines.*

            fun main() = runBlocking {
                var negDurationRan = false
                val negDuration = withTimeoutOrNull((-1).milliseconds) { negDurationRan = true; "unreachable" }
                println(negDuration)
                println(negDurationRan)

                var zeroDurationRan = false
                val zeroDuration = withTimeoutOrNull(0.milliseconds) { zeroDurationRan = true; "unreachable" }
                println(zeroDuration)
                println(zeroDurationRan)

                var negLongRan = false
                val negLong = withTimeoutOrNull(-1L) { negLongRan = true; "unreachable" }
                println(negLong)
                println(negLongRan)

                var positiveRan = false
                val positive = withTimeoutOrNull(1000.milliseconds) { positiveRan = true; 42 }
                println(positive)
                println(positiveRan)

                var withTimeoutRan = false
                var withTimeoutMessage = ""
                var withTimeoutThrew = false
                try {
                    withTimeout((-1).milliseconds) { withTimeoutRan = true; "unreachable" }
                } catch (e: TimeoutCancellationException) {
                    withTimeoutThrew = true
                    withTimeoutMessage = e.message ?: ""
                }
                println(withTimeoutThrew)
                println(withTimeoutMessage)
                println(withTimeoutRan)
            }
            """,
            expectedOutput: "null\nfalse\nnull\nfalse\nnull\nfalse\n42\ntrue\ntrue\nTimed out immediately\nfalse\n",
            moduleName: "KUU4587NonPositiveTimeout",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
