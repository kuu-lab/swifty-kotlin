@testable import CompilerCore
import Testing

@Suite(.serialized)
struct KUU2924CallerContinuationTests {
    @Test
    func dynamicUninterceptedStartResumesThroughCallerContinuation() throws {
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.Continuation
            import kotlin.coroutines.CoroutineContext
            import kotlin.coroutines.EmptyCoroutineContext
            import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
            import kotlin.coroutines.intrinsics.suspendCoroutineUninterceptedOrReturn
            import kotlin.coroutines.intrinsics.startCoroutineUninterceptedOrReturn
            import kotlin.coroutines.startCoroutine

            private class CallerContinuation : Continuation<String> {
                var result: String? = null
                override val context: CoroutineContext = EmptyCoroutineContext
                override fun resumeWith(result: Result<String>) {
                    this.result = result.getOrThrow()
                }
            }

            private var parked: Continuation<String>? = null

            private suspend fun park(): String = suspendCoroutineUninterceptedOrReturn { continuation ->
                parked = continuation
                COROUTINE_SUSPENDED
            }

            private suspend fun startInner(inner: suspend () -> String): String =
                suspendCoroutineUninterceptedOrReturn { completion ->
                    inner.startCoroutineUninterceptedOrReturn(completion)
                }

            fun main() {
                val caller = CallerContinuation()
                val operation: suspend () -> String = { startInner { park() + "!" } }
                operation.startCoroutine(caller)

                val continuation = parked
                if (continuation == null) {
                    println("not parked")
                    return
                }
                continuation.resumeWith(Result.success("OK"))
                println(caller.result ?: "incomplete")
            }
            """,
            expectedOutput: "OK!\n",
            moduleName: "KUU2924CallerContinuation",
            allowDefaultStdlibLibrary: false
        )
    }
}
