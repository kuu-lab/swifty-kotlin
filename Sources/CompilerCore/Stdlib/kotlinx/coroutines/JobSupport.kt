package kotlinx.coroutines

public abstract class JobSupport(active: Boolean) : Job, ChildJob, ParentJob {
    private var activeState: Boolean = active
    private var completedState: Boolean = false
    private var cancelledState: Boolean = false
    private var cancellationCause: Throwable? = null

    public final override val key: kotlin.coroutines.CoroutineContext.Key<*> get() = Job.Key
    public override val isActive: Boolean get() = activeState && !completedState
    public final override val isCompleted: Boolean get() = completedState
    public final override val isCancelled: Boolean get() = cancelledState
    public var parent: Job? = null
        private set

    protected fun initParentJob(parent: Job?) {
        this.parent = parent
    }

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

    public override fun cancel() {
        cancel(null)
    }

    public override fun cancel(cause: Any?) {
        if (completedState) return
        cancellationCause = cause as? Throwable
        cancelledState = true
        completedState = true
        onCancelling(cancellationCause)
    }

    public override suspend fun join() {}
    public override suspend fun awaitCompletion() {}

    public override fun complete(value: Any): Boolean {
        if (completedState) return false
        completedState = true
        onCompletionInternal(value)
        afterCompletion(value)
        return true
    }

    public override fun completeExceptionally(exception: Any?): Boolean {
        if (completedState) return false
        cancel(exception)
        return true
    }

    public final override fun parentCancelled(parentJob: ParentJob) {
        cancel(parentJob.getChildJobCancellationCause())
    }

    public final override fun getChildJobCancellationCause(): CancellationException =
        CancellationException("Job was cancelled", cancellationCause)

    public open fun childCancelled(cause: Throwable): Boolean = completeExceptionally(cause)

    public fun attachChild(child: ChildJob): ChildHandle = NonDisposableHandle
}

public class JobImpl(parent: Job? = null) : JobSupport(true), CompletableJob {
    init {
        initParentJob(parent)
    }

    public override fun complete(): Boolean = complete(Unit)
    public override fun completeExceptionally(exception: Throwable): Boolean =
        super<JobSupport>.completeExceptionally(exception)
}
