package kotlinx.coroutines

import kotlin.coroutines.CoroutineContext
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_job_bind_wrapper")
internal external fun __kkJobBindWrapper(wrapper: Any, job: Job, parent: Job?): Job

@KsSymbolName("kk_job_complete")
internal external fun __kkJobComplete(job: Job, value: Any?): Boolean

@KsSymbolName("kk_job_complete_exceptionally")
internal external fun __kkJobCompleteExceptionally(job: Job, exception: Throwable): Boolean

@KsSymbolName("kk_job_join")
internal external suspend fun __kkJobJoin(job: Job)

public interface CompletableJob : Job {
    @KsSymbolName("kk_job_complete_unit")
    public fun complete(): Boolean
    @KsSymbolName("kk_job_complete_exceptionally")
    public fun completeExceptionally(exception: Throwable): Boolean
}

// KUU-1386: real kotlinx shapes Job() / SupervisorJob() results as JobImpl,
// a JobSupport subclass; the bound runtime job keeps the delegation identical
// to the previous explicit overrides.
internal class CompletableJobImpl(backingJob: Job, parent: Job?) : JobImpl(parent, backingJob), CompletableJob

public fun CompletableJob(parent: Job? = null): CompletableJob = Job(parent)
