// KUU-1980: runtime-backed key singletons retain their type after Any erasure.
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers

@OptIn(ExperimentalStdlibApi::class)
fun main() {
    val elementKey: Any = Dispatchers.Default.key
    println(elementKey is CoroutineContext.Key<*>)
    println(elementKey is ContinuationInterceptor.Key)
    val interceptorKey = ContinuationInterceptor.Key
    val dispatcherKey = CoroutineDispatcher.Key
    println(interceptorKey is CoroutineContext.Key<*>)
    println(dispatcherKey is CoroutineContext.Key<*>)

    val erasedInterceptor: Any = interceptorKey
    val erasedDispatcher: Any = dispatcherKey
    println(erasedInterceptor is CoroutineContext.Key<*>)
    println(erasedDispatcher is CoroutineContext.Key<*>)
    println(erasedInterceptor is ContinuationInterceptor.Key)
    println(erasedDispatcher is CoroutineDispatcher.Key)
    println(erasedInterceptor is CoroutineDispatcher.Key)
    println(erasedDispatcher is ContinuationInterceptor.Key)
    println(erasedInterceptor is CoroutineContext.Element)
    println(erasedDispatcher is ContinuationInterceptor)
    println((erasedInterceptor as? CoroutineContext.Key<*>) === interceptorKey)
    println((erasedDispatcher as? CoroutineContext.Key<*>) === dispatcherKey)
    println((erasedInterceptor as CoroutineContext.Key<*>) === interceptorKey)
    println((erasedDispatcher as CoroutineContext.Key<*>) === dispatcherKey)
    println(ContinuationInterceptor === interceptorKey)
    println(CoroutineDispatcher === dispatcherKey)
    println(erasedInterceptor === erasedDispatcher)
    println((Dispatchers.Default.key as Any) is CoroutineContext.Key<*>)
    println(Dispatchers.Default.key === interceptorKey)
}
