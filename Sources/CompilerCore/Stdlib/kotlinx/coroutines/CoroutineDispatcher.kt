package kotlinx.coroutines

import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName

public abstract class CoroutineDispatcher : CoroutineContext.Element, ContinuationInterceptor {
    @KsSymbolName("kk_coroutine_dispatcher_key")
    public companion object Key : CoroutineContext.Key<CoroutineDispatcher>
    public override val key: CoroutineContext.Key<*> get() = ContinuationInterceptor.Key
}

// Dispatcher handles use the existing scheduler; these views do not change it.
public val CoroutineDispatcher.immediate: CoroutineDispatcher
    get() = this

public fun CoroutineDispatcher.limitedParallelism(parallelism: Int): CoroutineDispatcher {
    require(parallelism > 0) { "Expected positive parallelism level, but got $parallelism" }
    return this
}
