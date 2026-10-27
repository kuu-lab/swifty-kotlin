@testable import CompilerCore
import TestStdlibCache
import Testing

@Suite(.serialized)
struct KUU3310ContinuationTypeTests {
    @Test
    func continuationTypeChecks() throws {
        TestStdlibCache.shared.prepare()
        try compileAndRunKotlin(
            """
            import kotlin.coroutines.*
            import kotlin.coroutines.intrinsics.*

            private suspend fun raw(): Boolean = suspendCoroutineUninterceptedOrReturn { continuation ->
                val value: Any = continuation
                println(value is Continuation<*>)
                println(Continuation::class.isInstance(value))
                println(value is String)
                continuation.resume(value is Continuation<*>)
                COROUTINE_SUSPENDED
            }

            private suspend fun safe(): Boolean = suspendCoroutine { continuation ->
                val value: Any = continuation
                println(value is Continuation<*>)
                println(Continuation::class.isInstance(value))
                continuation.resume(value is Continuation<*>)
            }

            fun main() {
                val completion = object : Continuation<Unit> {
                    override val context: CoroutineContext = EmptyCoroutineContext
                    override fun resumeWith(result: Result<Unit>) { result.getOrThrow() }
                }
                val block: suspend () -> Unit = { println(raw()); println(safe()) }
                block.startCoroutine(completion)
            }
            """,
            expectedOutput: "true\ntrue\nfalse\ntrue\ntrue\ntrue\ntrue\n",
            moduleName: "KUU3310ContinuationType"
        )
    }
}
