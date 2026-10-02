package kotlinx.coroutines

public interface CompletableJob : Job {
    public fun complete(): Boolean = complete(Unit)
    public fun completeExceptionally(exception: Throwable): Boolean = completeExceptionally(exception as Any?)
}
