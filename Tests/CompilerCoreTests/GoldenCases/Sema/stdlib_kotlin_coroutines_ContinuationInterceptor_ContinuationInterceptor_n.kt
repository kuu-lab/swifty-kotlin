package golden.sema

import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext

fun <E : CoroutineContext.Element> lookup(interceptor: ContinuationInterceptor, key: CoroutineContext.Key<E>): E? =
    interceptor[key]

fun <T> intercept(interceptor: ContinuationInterceptor, continuation: Continuation<T>): Continuation<T> =
    interceptor.interceptContinuation(continuation)

fun remove(interceptor: ContinuationInterceptor, key: CoroutineContext.Key<*>): CoroutineContext =
    interceptor.minusKey(key)

fun release(interceptor: ContinuationInterceptor, continuation: Continuation<*>) {
    interceptor.releaseInterceptedContinuation(continuation)
}
