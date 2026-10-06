package kotlinx.coroutines

import kotlin.internal.KsSymbolName

public abstract class JobSupport(active: Boolean) : Job, ChildJob, ParentJob {
    private var activeState: Boolean = active
    private var completedState: Boolean = false
    private var cancelledState: Boolean = false
    private var cancellationCause: Throwable? = null

    @KsSymbolName("kk_job_key_get")
    public final override val key: kotlin.coroutines.CoroutineContext.Key<*>
    @KsSymbolName("kk_job_is_active")
    public override val isActive: Boolean get() = activeState && !completedState
    @KsSymbolName("kk_job_is_completed")
    public final override val isCompleted: Boolean get() = completedState
    @KsSymbolName("kk_job_is_cancelled")
    public final override val isCancelled: Boolean get() = cancelledState

    // KUU-1386: `job as JobSupport` now yields the real runtime job handle, so
    // the public Job-family members are runtime bridges like on Job itself;
    // Kotlin bodies stay for source-level super calls.
    @KsSymbolName("__kk_job_parent")
    public var parent: Job? = null
        private set

    protected fun initParentJob(parent: Job?) {
        __kkJobAttachToParent(this, parent)
    }

    @KsSymbolName("kk_job_start")
    public final override fun start(): Boolean {
        if (activeState || completedState) return false
        activeState = true
        onStart()
        return true
    }

    protected open fun onStart() {}
    protected open fun onCancelling(cause: Throwable?) {}
    protected open fun onCompletionInternal(state: Any?) {}
    protected open fun afterCompletion(state: Any?) {}

    @KsSymbolName("kk_job_cancel")
    public override fun cancel() {
        cancel(null)
    }

    @KsSymbolName("kk_job_cancel_with_cause")
    public override fun cancel(cause: Any?) {
        if (completedState) return
        cancellationCause = cause as? Throwable
        cancelledState = true
        completedState = true
        onCancelling(cancellationCause)
    }

    @KsSymbolName("kk_job_join")
    public override suspend fun join() {}
    @KsSymbolName("kk_job_await_completion")
    public override suspend fun awaitCompletion() {}

    @KsSymbolName("kk_job_complete")
    public override fun complete(value: Any): Boolean {
        if (completedState) return false
        completedState = true
        onCompletionInternal(value)
        afterCompletion(value)
        return true
    }

    @KsSymbolName("kk_job_complete_exceptionally")
    public override fun completeExceptionally(exception: Any?): Boolean {
        if (completedState) return false
        cancel(exception)
        return true
    }

    // KUU-1386: kotlinx declares `childCancelled` on JobSupport itself
    // (`parentCancelled`/`getChildJobCancellationCause`/`attachChild` are
    // inherited runtime-bridged defaults from ChildJob, ParentJob and Job).
    @KsSymbolName("kk_job_child_cancelled")
    public open fun childCancelled(cause: Throwable): Boolean = completeExceptionally(cause)
}

public open class JobImpl(parent: Job? = null, backingJob: Job = __kkJobNew()) : JobSupport(true), CompletableJob {
    init {
        __kkJobBindWrapper(this, backingJob, parent)
        initParentJob(parent)
    }

    public override fun complete(): Boolean = complete(Unit)
    public override fun completeExceptionally(exception: Throwable): Boolean =
        __kkJobCompleteExceptionally(this, exception)
}
