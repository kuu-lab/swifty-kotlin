import kotlin.coroutines.*
import kotlinx.coroutines.*

object MissingKey : CoroutineContext.Key<CoroutineContext.Element>

@OptIn(ExperimentalStdlibApi::class)
object NativeKey : AbstractCoroutineContextKey<ContinuationInterceptor, ContinuationInterceptor>(
    ContinuationInterceptor.Key, { element: CoroutineContext.Element -> if (element === Dispatchers.Default) Dispatchers.Default else null }
)

@OptIn(ExperimentalStdlibApi::class)
object NestedKey : AbstractCoroutineContextKey<ContinuationInterceptor, ContinuationInterceptor>(
    NativeKey, { element: CoroutineContext.Element -> if (element === Dispatchers.Default) Dispatchers.Default else null }
)

@OptIn(ExperimentalStdlibApi::class)
object RejectedKey : AbstractCoroutineContextKey<ContinuationInterceptor, ContinuationInterceptor>(
    ContinuationInterceptor.Key, { _: CoroutineContext.Element -> null }
)

@OptIn(ExperimentalStdlibApi::class)
object OtherKey : AbstractCoroutineContextKey<CoroutineContext.Element, ContinuationInterceptor>(
    MissingKey, { element: CoroutineContext.Element ->
        println("other cast")
        element as? ContinuationInterceptor
    }
)

class OtherInterceptor : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> get() = MissingKey
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> = continuation
}

class CustomInterceptor : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> get() = ContinuationInterceptor.Key
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> = continuation
    override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? {
        println("custom get")
        return null
    }
}

class ThrowingInterceptor : ContinuationInterceptor {
    override val key: CoroutineContext.Key<*> get() = ContinuationInterceptor.Key
    override fun <T> interceptContinuation(continuation: Continuation<T>): Continuation<T> = continuation
    override fun <E : CoroutineContext.Element> get(key: CoroutineContext.Key<E>): E? =
        throw IllegalStateException("custom failure")
}

@OptIn(ExperimentalStdlibApi::class)
fun main() {
    println(Dispatchers.Default[MissingKey] == null)
    println(Dispatchers.Main[MissingKey] == null)
    println(Dispatchers.Default.get(MissingKey) == null)
    val interceptor: ContinuationInterceptor = Dispatchers.Default
    println(interceptor[MissingKey] == null)
    println(interceptor[ContinuationInterceptor.Key] === interceptor)
    println(Dispatchers.Default[NativeKey] === Dispatchers.Default)
    println(Dispatchers.Default[NestedKey] === Dispatchers.Default)
    println(Dispatchers.Default[RejectedKey] == null)
    println(interceptor.minusKey(NativeKey) === EmptyCoroutineContext)
    println(interceptor.minusKey(RejectedKey) === interceptor)
    println(Dispatchers.Default[OtherKey] == null)
    println(interceptor.minusKey(OtherKey) === interceptor)
    val other: ContinuationInterceptor = OtherInterceptor()
    println(other[OtherKey] === other)
    println(other.minusKey(OtherKey) === EmptyCoroutineContext)
    val nullable: CoroutineDispatcher? = Dispatchers.Default
    println(nullable?.get(MissingKey) == null)
    val custom: ContinuationInterceptor = CustomInterceptor()
    println(custom[MissingKey] == null)
    val throwing: ContinuationInterceptor = ThrowingInterceptor()
    try { throwing[MissingKey] } catch (e: IllegalStateException) { println(e.message) }
}
