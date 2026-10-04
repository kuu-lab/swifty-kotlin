package kotlinx.coroutines

import kotlin.internal.KsSymbolName

public interface CompletableJob : Job {
    @KsSymbolName("kk_job_complete_unit")
    public fun complete(): Boolean

    @KsSymbolName("kk_job_complete_exceptionally")
    public fun completeExceptionally(exception: Throwable): Boolean
}
