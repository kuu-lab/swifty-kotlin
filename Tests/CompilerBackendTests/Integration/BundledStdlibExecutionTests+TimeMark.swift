import Testing

extension BundledStdlibExecutionTests {
    @Test
    func testSameArityOverloadDoesNotReplaceInterfaceDefault() throws {
        try compileAndRunKotlin(
            """
            interface Base {
                fun describe(value: Int): String = "int"
            }

            interface Derived : Base {
                fun describe(value: String): String
            }

            class Impl : Derived {
                override fun describe(value: String): String = value
            }

            fun main() {
                val derived: Derived = Impl()
                val base: Base = derived
                println(base.describe(1))
                println(derived.describe(2))
                println(derived.describe("string"))
            }
            """,
            expectedOutput: "int\nint\nstring\n",
            allowDefaultStdlibLibrary: false
        )
    }

    @Test(arguments: [false, true])
    func testTimeMarksUseTheirOwnSource(allowDefaultStdlibLibrary: Bool) throws {
        try compileAndRunKotlin(
            """
            import kotlin.time.Duration
            import kotlin.time.Duration.Companion.milliseconds
            import kotlin.time.TestTimeSource
            import kotlin.time.TimeMark
            import kotlin.time.TimeSource
            import kotlin.time.measureTime

            class CustomMark(var elapsed: Duration) : TimeMark {
                override fun elapsedNow(): Duration = elapsed
            }

            fun main() {
                val source = TestTimeSource()
                val start = source.markNow()
                val erased: TimeMark = start
                source += 5.milliseconds
                println(start.elapsedNow().inWholeMilliseconds)
                println(erased.elapsedNow().inWholeMilliseconds)
                println((source.markNow() - start).inWholeMilliseconds)
                val future = start + 10.milliseconds
                println(future.elapsedNow().inWholeMilliseconds)
                println(future.hasNotPassedNow())
                println((erased - 2.milliseconds).elapsedNow().inWholeMilliseconds)
                source += 10.milliseconds
                println(future.elapsedNow().inWholeMilliseconds)
                println(future.hasPassedNow())
                val timeSource: TimeSource = source
                println(timeSource.measureTime { source += 3.milliseconds }.inWholeMilliseconds)
                val custom = CustomMark(5.milliseconds)
                val mark: TimeMark = custom
                val adjusted = (mark + 10.milliseconds) - 2.milliseconds
                println(adjusted.elapsedNow().inWholeMilliseconds)
                custom.elapsed = 9.milliseconds
                println(adjusted.elapsedNow().inWholeMilliseconds)
            }
            """,
            expectedOutput: "5\n5\n5\n-5\ntrue\n7\n5\ntrue\n3\n-3\n1\n",
            allowDefaultStdlibLibrary: allowDefaultStdlibLibrary
        )
    }
}
