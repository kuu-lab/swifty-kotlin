package kotlinx.coroutines

import kotlin.coroutines.ContinuationInterceptor
import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName
import java.lang.Runnable

/**
 * Runtime bridge used to route coroutine resumptions through source-defined
 * dispatchers on the native backend.
 */
public interface CoroutineDispatcherRuntimeBridge {
    public fun dispatch(context: CoroutineContext, block: Runnable)
}

@KsSymbolName("__kk_dispatcher_default_execute")
internal external fun __dispatcherDefaultExecute(block: Runnable)

public abstract class CoroutineDispatcher :
    CoroutineContext.Element,
    ContinuationInterceptor,
    CoroutineDispatcherRuntimeBridge
{
    // KUU-1395: `CoroutineDispatcher`/`CoroutineDispatcher.Key` evaluates to a
    // runtime key singleton so `ctx[CoroutineDispatcher]` resolves the
    // context's dispatcher element (kotlinx's Key is a sub-key of
    // ContinuationInterceptor, which resolves there too).
    @KsSymbolName("kk_coroutine_dispatcher_key")
    public companion object Key : CoroutineContext.Key<CoroutineDispatcher>
    public override val key: CoroutineContext.Key<*> get() = ContinuationInterceptor.Key

    /** Dispatches a runnable. The default implementation uses the shared pool. */
    public open override fun dispatch(context: CoroutineContext, block: Runnable) {
        __dispatcherDefaultExecute(block)
    }

    /**
     * Upstream `public open fun isDispatchNeeded` (KUU-3910): whether resuming a
     * coroutine suspended in [context] must go through [dispatch]. The runtime
     * answers `false` for `Dispatchers.Unconfined` and for immediate-capable
     * dispatchers already executing on their queue (upstream `Main.immediate`
     * on the main thread); every other dispatcher defaults to `true`.
     */
    public open fun isDispatchNeeded(context: CoroutineContext): Boolean =
        __dispatcherIsDispatchNeeded(this)
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

@KsSymbolName("__kk_dispatcher_is_dispatch_needed")
internal external fun __dispatcherIsDispatchNeeded(dispatcher: CoroutineDispatcher): Boolean

public fun CoroutineDispatcher.limitedParallelism(
    parallelism: Int, name: String? = null
): CoroutineDispatcher {
    require(parallelism > 0) { "Expected positive parallelism level, but got $parallelism" }
    if (__dispatcherIsUnconfined(this)) {
        throw UnsupportedOperationException("limitedParallelism is not supported for Dispatchers.Unconfined")
    }
    return __dispatcherLimitedParallelism(this, parallelism, name)
}
