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

internal object CompletableJobKey : CoroutineContext.Key<Job>

public interface CompletableJob : Job {
    @KsSymbolName("kk_job_complete_unit")
    public fun complete(): Boolean
    @KsSymbolName("kk_job_complete_exceptionally")
    public fun completeExceptionally(exception: Throwable): Boolean
}

internal class CompletableJobImpl(backingJob: Job, parent: Job?) : CompletableJob {
    private val job: Job = __kkJobBindWrapper(this, backingJob, parent)

    override val isActive: Boolean get() = job.isActive
    override val isCompleted: Boolean get() = job.isCompleted
    override val isCancelled: Boolean get() = job.isCancelled

    override val key: CoroutineContext.Key<*>
        get() = CompletableJobKey

    override fun complete(): Boolean = __kkJobComplete(job, Unit)

    override fun completeExceptionally(exception: Throwable): Boolean =
        __kkJobCompleteExceptionally(job, exception)
}

public fun CompletableJob(parent: Job? = null): CompletableJob = Job(parent)
