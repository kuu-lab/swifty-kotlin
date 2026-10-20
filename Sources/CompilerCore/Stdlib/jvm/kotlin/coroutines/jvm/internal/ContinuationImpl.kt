package kotlin.coroutines.jvm.internal
import kotlin.coroutines.*
abstract class ContinuationImpl(completion: Continuation<Any?>?): BaseContinuationImpl(completion) {
    private var providedContext: CoroutineContext? = null
    constructor(completion: Continuation<Any?>?, context: CoroutineContext): this(completion) { providedContext = context }
    override val context: CoroutineContext get() = providedContext ?: super.context
    fun intercepted(): Continuation<Any?> = this
}
abstract class RestrictedContinuationImpl(completion: Continuation<Any?>?): BaseContinuationImpl(completion) {
    init { if (completion != null && completion.context !== EmptyCoroutineContext) throw IllegalArgumentException("Coroutines with restricted suspension must have EmptyCoroutineContext") }
    override val context: CoroutineContext get() = EmptyCoroutineContext
}
