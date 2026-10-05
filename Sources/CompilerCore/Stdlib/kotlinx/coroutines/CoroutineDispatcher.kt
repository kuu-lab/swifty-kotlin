package kotlinx.coroutines

import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext

public abstract class CoroutineDispatcher : CoroutineContext.Element, ContinuationInterceptor {
    public companion object Key : CoroutineContext.Key<CoroutineDispatcher>
    public override val key: CoroutineContext.Key<*> get() = Key
}

// Dispatcher handles use the existing scheduler; these views do not change it.
public val CoroutineDispatcher.immediate: CoroutineDispatcher
    get() = this

public fun CoroutineDispatcher.limitedParallelism(parallelism: Int): CoroutineDispatcher {
    require(parallelism > 0) { "Expected positive parallelism level, but got $parallelism" }
    return this
}
