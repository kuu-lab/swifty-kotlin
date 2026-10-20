package kotlin.coroutines
import kotlin.jvm.internal.*
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
private object Undecided
private object Resumed
class SafeContinuation<in T>(private val delegate: Continuation<T>): Continuation<T> {
    private val state: Any = __jvmAtomicReference(Undecided)
    override val context: CoroutineContext get() = delegate.context
    override fun resumeWith(result: kotlin.Result<T>) {
        val value = __jvmResultValue(result)
        while (true) {
            val current = __jvmAtomicGet(state)
            if (current === Undecided) {
                if (__jvmAtomicCAS(state, Undecided, value)) return
            } else if (current === COROUTINE_SUSPENDED) {
                if (__jvmAtomicCAS(state, current, Resumed)) {
                    __jvmResume(delegate, value)
                    return
                }
            } else throw IllegalStateException("Already resumed")
        }
    }
    fun getOrThrow(): Any? {
        var current = __jvmAtomicGet(state)
        if (current === Undecided) {
            if (__jvmAtomicCAS(state, Undecided, COROUTINE_SUSPENDED)) return COROUTINE_SUSPENDED
            current = __jvmAtomicGet(state)
        }
        if (current === Resumed) return COROUTINE_SUSPENDED
        kotlin.throwOnFailure(current)
        return current
    }
}
