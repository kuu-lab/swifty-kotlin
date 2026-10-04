package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.internal.KsSymbolName

// Deferred is currently non-generic; await() narrows the Any contract using
// the async block's inferred result type, as it does for the residual builder.
@KsSymbolName("kk_coroutine_scope_async")
public external fun CoroutineScope.async(
    context: CoroutineContext = EmptyCoroutineContext,
    start: CoroutineStart = CoroutineStart.DEFAULT,
    block: suspend () -> Any
): Deferred
