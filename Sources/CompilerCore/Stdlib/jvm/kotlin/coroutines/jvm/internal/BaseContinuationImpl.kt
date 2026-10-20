package kotlin.coroutines.jvm.internal
import kotlin.coroutines.*
import kotlin.jvm.internal.*
import kotlin.coroutines.intrinsics.COROUTINE_SUSPENDED
abstract class BaseContinuationImpl(val completion: Continuation<Any?>?): Continuation<Any?>, CoroutineStackFrame, java.io.Serializable {
    override val context: CoroutineContext get() = if (completion == null) EmptyCoroutineContext else completion!!.context
    override val callerFrame: CoroutineStackFrame? get() = completion as? CoroutineStackFrame
    override fun getStackTraceElement(): java.lang.StackTraceElement? = stackTraceElement(this)
    protected abstract fun invokeSuspend(result: Any?): Any?
    protected open fun releaseIntercepted() {}
    open fun create(completion: Continuation<*>): Continuation<Unit> = throw UnsupportedOperationException("create(Continuation) has not been overridden")
    open fun create(value: Any?, completion: Continuation<*>): Continuation<Unit> = throw UnsupportedOperationException("create(Any?, Continuation) has not been overridden")
    override fun resumeWith(result: kotlin.Result<Any?>) {
        var current: BaseContinuationImpl = this
        var value: Any? = __jvmResultValue(result)
        while (true) {
            val next = current.completion
            try { value = current.invokeSuspend(value) } catch (failure: Throwable) { value = kotlin.createFailure(failure) }
            if (value === COROUTINE_SUSPENDED) return
            current.releaseIntercepted()
            if (next is BaseContinuationImpl) { current = next }
            else {
                if (next != null) __jvmResume(next, value)
                return
            }
        }
    }
}
