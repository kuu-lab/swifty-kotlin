package kotlin.coroutines

interface ContinuationInterceptor : CoroutineContext.Element {
    companion object Key : CoroutineContext.Key<ContinuationInterceptor>

    fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T>
    fun releaseInterceptedContinuation(continuation: Continuation<*>) {}

    @Suppress("UNCHECKED_CAST")
    override operator fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? {
        if (key is AbstractCoroutineContextKey<*, *>) {
            return if (key.isSubKey(this.key)) key.tryCast(this) as E? else null
        }
        return if (key === Key) this as E else null
    }

    override fun minusKey(key: CoroutineContext.Key<*>): CoroutineContext {
        val matches = if (key is AbstractCoroutineContextKey<*, *>) {
            key.isSubKey(this.key) && key.tryCast(this) != null
        } else {
            key === Key
        }
        return if (matches) EmptyCoroutineContext else this
    }
}

abstract class AbstractCoroutineContextKey<B : CoroutineContext.Element, E : B>(
    baseKey: CoroutineContext.Key<B>,
    private val safeCast: (CoroutineContext.Element) -> E?
) : CoroutineContext.Key<E> {
    private val rootKey: CoroutineContext.Key<*> =
        if (baseKey is AbstractCoroutineContextKey<*, *>) baseKey.rootKey else baseKey

    internal fun tryCast(element: CoroutineContext.Element): E? = safeCast(element)

    internal fun isSubKey(key: CoroutineContext.Key<*>): Boolean = key === this || key === rootKey
}
