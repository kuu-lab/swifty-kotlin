package kotlin.coroutines

interface CoroutineContext {
    operator fun <E : Element> get(key: Key<E>): E?
    fun <R> fold(initial: R, operation: (R, Element) -> R): R
    fun minusKey(key: Key<*>): CoroutineContext
    operator fun plus(context: CoroutineContext): CoroutineContext = null!!

    interface Key<E : Element>

    interface Element : CoroutineContext {
        val key: Key<*>
        override operator fun <E : Element> get(key: Key<E>): E? = null
        override fun <R> fold(initial: R, operation: (R, Element) -> R): R = null!!
        override fun minusKey(key: Key<*>): CoroutineContext = null!!
    }
}

object EmptyCoroutineContext : CoroutineContext, java.io.Serializable {
    override operator fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? = null
    override fun <R> fold(initial: R, operation: (R, CoroutineContext.Element) -> R): R = null!!
    override fun plus(context: CoroutineContext): CoroutineContext = null!!
    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext = null!!
}

abstract class AbstractCoroutineContextElement(override val key: CoroutineContext.Key<*>) : CoroutineContext.Element

interface ContinuationInterceptor : CoroutineContext.Element {
    companion object Key : CoroutineContext.Key<ContinuationInterceptor>
    fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T>
    fun releaseInterceptedContinuation(continuation: Continuation<*>) {}
    override operator fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? = null
    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext = null!!
}

abstract class AbstractCoroutineContextKey<B : CoroutineContext.Element, E : B>(
    baseKey: CoroutineContext.Key<B>,
    safeCast: (CoroutineContext.Element) -> E?
) : CoroutineContext.Key<E>
