package kotlinx.coroutines.internal

import kotlin.coroutines.Continuation
import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlinx.coroutines.CoroutineDispatcher

internal fun <E : Throwable> recoverStackTrace(exception: E, continuation: Continuation<*>): E = exception

internal fun <E : Throwable> recoverStackTrace(exception: E): E = exception

internal suspend inline fun recoverAndThrow(exception: Throwable): Nothing {
    throw exception
}

@PublishedApi
internal fun <E : Throwable> unwrap(exception: E): E = exception

internal fun isDispatchNeeded(context: CoroutineContext): Boolean =
    when (val interceptor = context[ContinuationInterceptor]) {
        null -> false
        is CoroutineDispatcher -> interceptor.isDispatchNeeded(context)
        else -> true
    }
