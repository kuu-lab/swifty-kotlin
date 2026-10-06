package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.internal.KsSymbolName

// Matches the JVM signature: the block runs with the receiver scope as `this`
// and its result type feeds `Deferred<T>`.
@KsSymbolName("kk_coroutine_scope_async")
public external fun <T> CoroutineScope.async(
    context: CoroutineContext = EmptyCoroutineContext,
    start: CoroutineStart = CoroutineStart.DEFAULT,
    block: suspend CoroutineScope.() -> T
): Deferred<T>

// The block receives the child scope; context and start match kotlinx.coroutines.
@KsSymbolName("__kk_coroutine_scope_launch_context")
public external fun CoroutineScope.launch(
    context: CoroutineContext = EmptyCoroutineContext,
    start: CoroutineStart = CoroutineStart.DEFAULT,
    block: suspend CoroutineScope.() -> Unit
): Job
