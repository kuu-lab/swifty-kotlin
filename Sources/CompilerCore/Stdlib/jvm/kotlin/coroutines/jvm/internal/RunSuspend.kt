package kotlin.coroutines.jvm.internal
import kotlin.coroutines.*
import kotlin.jvm.internal.*
private class RunSuspend: Continuation<Unit> {
    private val latch: Any = __jvmLatch(1)
    private var outcome: Any? = null
    override val context: CoroutineContext get() = EmptyCoroutineContext
    override fun resumeWith(result: kotlin.Result<Unit>) {
        outcome = __jvmResultValue(result)
        __jvmCountDown(latch)
    }
    fun await() { __jvmAwait(latch); kotlin.throwOnFailure(outcome) }
}
fun runSuspend(block: (Continuation<Unit>) -> Any?) {
    val completion = RunSuspend()
    kotlin.coroutines.startEncoded(block, completion)
    completion.await()
}
