package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.internal.KsSymbolName

// A blocking boundary owns a fresh Job and applies the supplied context.
// Keep this canonical contract in Kotlin source so generic/default metadata
// and source/artifact consumers follow the same function-value path.
public fun <T> runBlocking(
    context: CoroutineContext = EmptyCoroutineContext,
    block: suspend CoroutineScope.() -> T
): T = __kkRunBlockingContext(context, block)

@KsSymbolName("__kk_run_blocking_context")
internal external fun <T> __kkRunBlockingContext(
    context: CoroutineContext,
    block: suspend CoroutineScope.() -> T
): T

@KsSymbolName("kk_coroutine_scope_async")
public external fun <T> CoroutineScope.async(
    context: CoroutineContext = EmptyCoroutineContext,
    start: CoroutineStart = CoroutineStart.DEFAULT,
    block: suspend CoroutineScope.() -> T
): Deferred<T>

@KsSymbolName("__kk_coroutine_scope_launch_context")
public external fun CoroutineScope.launch(
    context: CoroutineContext = EmptyCoroutineContext,
    start: CoroutineStart = CoroutineStart.DEFAULT,
    block: suspend CoroutineScope.() -> Unit
): Job
