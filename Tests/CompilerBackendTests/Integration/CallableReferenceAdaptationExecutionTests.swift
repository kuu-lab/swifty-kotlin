import Testing

@Suite(.serialized)
struct CallableReferenceAdaptationExecutionTests {
    @Test func adaptsVarargAndTrailingDefaultArgumentsAtRuntime() throws {
        try compileAndRunKotlin(
            """
            import kotlin.reflect.KCallable

            fun useArray(factory: (Int, Int) -> Array<Int>): Array<Int> = factory(11, 22)
            fun combine(first: Int = 3, second: Int = 4): Int = first * 10 + second
            fun collect(vararg values: Int) {}
            fun isCallable(value: Any): Boolean = value is KCallable<*>

            fun main() {
                val factory: (Int, Int) -> Array<Int> = ::arrayOf
                val values = useArray(factory)
                println(values[0])
                println(values[1])

                val noArguments: () -> Int = ::combine
                val oneArgument: (Int) -> Int = ::combine
                val packed: (IntArray) -> Unit = ::collect
                println(noArguments())
                println(oneArgument(8))
                println(isCallable(factory))
                println(isCallable(noArguments))
                println(isCallable(packed))
            }
            """,
            expectedOutput: "11\n22\n34\n84\nfalse\nfalse\ntrue\n",
            moduleName: "KUU2098CallableReference"
        )
    }
}
