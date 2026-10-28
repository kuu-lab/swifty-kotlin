import Testing

@Suite(.serialized)
struct KUU3680ContextOperatorCrashRegressionTests {
    @Test
    func contextualMemberExtensionDefaultArgumentRuns() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.ExperimentalContextParameters::class)

            class Context; class Extended
            class Containing {
                context(_: Context) fun Extended.foo(obj: Any? = null) {}
            }
            fun main() {
                with(Containing()) { with(Context()) { Extended().foo(); println("OK") } }
            }
            """,
            expectedOutput: "OK\n",
            moduleName: "KUU3680ContextMemberExtensionDefault"
        )
    }

    @Test
    func contextualIncReceivesItsReceiverDuringPostfixIncrement() throws {
        try compileAndRunKotlin(
            """
            @file:OptIn(kotlin.ExperimentalContextParameters::class)

            class C(var i: Int)
            context(c: Int)
            operator fun C.inc() = C(i + 1)
            fun main() {
                var b = C(0)
                with(9) { b++ }
                println(b.i)
            }
            """,
            expectedOutput: "1\n",
            moduleName: "KUU3680ContextIncOperator"
        )
    }
}
