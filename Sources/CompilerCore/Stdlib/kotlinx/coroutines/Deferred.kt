package kotlinx.coroutines

import kotlin.internal.KsSymbolName

// async still returns an opaque runtime task (KSP-1564). These residual
// bridges accept both that task and the source-backed completable wrapper.
public interface Deferred<out T> : Job {
    @KsSymbolName("kk_kxmini_async_await")
    public external suspend fun await(): T

    @KsSymbolName("__kk_deferred_get_completed")
    public external fun getCompleted(): T

    @KsSymbolName("__kk_deferred_completion_exception")
    public external fun getCompletionExceptionOrNull(): Throwable?
}
