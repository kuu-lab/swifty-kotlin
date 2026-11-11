package kotlin.coroutines.jvm.internal
import kotlin.coroutines.*
abstract class ContinuationImpl(completion: Continuation<Any?>?): BaseContinuationImpl(completion) {
    private var providedContext: CoroutineContext? = null
    private var cachedInterception: Continuation<Any?>? = null

    constructor(completion: Continuation<Any?>?, context: CoroutineContext): this(completion) { providedContext = context }
    override val context: CoroutineContext get() = providedContext ?: super.context

    fun intercepted(): Continuation<Any?> {
        val cached = cachedInterception
        if (cached != null) return cached
        val interceptor = context[ContinuationInterceptor.Key]
        val intercepted = if (interceptor == null) this else interceptor.interceptContinuation<Any?>(this)
        cachedInterception = intercepted
        return intercepted
    }

    override fun releaseIntercepted() {
        val cached = cachedInterception
        cachedInterception = CompletedContinuation
        if (cached != null && cached !== this && cached !== CompletedContinuation) {
            context[ContinuationInterceptor.Key]!!.releaseInterceptedContinuation(cached)
        }
    }
}

private object CompletedContinuation : Continuation<Any?> {
    override val context: CoroutineContext get() = throw IllegalStateException("This continuation is already complete")
    override fun resumeWith(result: Result<Any?>) { throw IllegalStateException("This continuation is already complete") }
}

abstract class RestrictedContinuationImpl(completion: Continuation<Any?>?): BaseContinuationImpl(completion) {
    init { if (completion != null && completion.context !== EmptyCoroutineContext) throw IllegalArgumentException("Coroutines with restricted suspension must have EmptyCoroutineContext") }
    override val context: CoroutineContext get() = EmptyCoroutineContext
}
