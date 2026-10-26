import Testing

@Suite(.serialized)
struct KUU3419SuspendDefaultArgumentTests {
    @Test
    func suspendLambdaCallsDefaultedSuspendFunctions() throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*

            private class Success : Throwable()
            private var counter = 0

            private suspend fun suspendThenThrow(): Nothing = throw Success()
            private suspend fun foo(x: Int = 1): Nothing = suspendThenThrow()

            fun main() {
                val continuation = object : Continuation<Unit> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Unit>) {
                        result.getOrThrow()
                        println(counter)
                    }
                }

                suspend {
                    try { foo() } catch (e: Success) { counter++ }
                    try {
                        object {
                            suspend fun foo(x: Int = 1): Nothing = suspendThenThrow()
                        }.foo()
                    } catch (e: Success) { counter++ }
                    Unit
                }.startCoroutine(continuation)
            }
            """,
            expectedOutput: "2\n",
            moduleName: "KUU3419SuspendDefaultArgument"
        )
    }
}
