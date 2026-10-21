package kotlinx.coroutines

import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName

public abstract class CoroutineDispatcher : CoroutineContext.Element, ContinuationInterceptor {
    // KUU-1395: `CoroutineDispatcher`/`CoroutineDispatcher.Key` evaluates to a
    // runtime key singleton so `ctx[CoroutineDispatcher]` resolves the
    // context's dispatcher element (kotlinx's Key is a sub-key of
    // ContinuationInterceptor, which resolves there too).
    @KsSymbolName("kk_coroutine_dispatcher_key")
    public companion object Key : CoroutineContext.Key<CoroutineDispatcher>
    public override val key: CoroutineContext.Key<*> get() = ContinuationInterceptor.Key
}

// KUU-2687: dispatcher views resolve in the runtime — the returned handle is a
// real dispatcher object (limited-view gate, named wrapper, or the immediate
// peer) rather than the bare scheduler tag.
@KsSymbolName("__kk_dispatcher_limited_parallelism")
internal external fun __dispatcherLimitedParallelism(
    dispatcher: CoroutineDispatcher, parallelism: Int, name: String?
): CoroutineDispatcher

@KsSymbolName("__kk_dispatcher_is_unconfined")
internal external fun __dispatcherIsUnconfined(dispatcher: CoroutineDispatcher): Boolean

public fun CoroutineDispatcher.limitedParallelism(
    parallelism: Int, name: String? = null
): CoroutineDispatcher {
    require(parallelism > 0) { "Expected positive parallelism level, but got $parallelism" }
    if (__dispatcherIsUnconfined(this)) {
        throw UnsupportedOperationException("limitedParallelism is not supported for Dispatchers.Unconfined")
    }
    return __dispatcherLimitedParallelism(this, parallelism, name)
}
