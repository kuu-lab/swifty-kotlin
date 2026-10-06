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
}
