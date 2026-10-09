package java.util.concurrent

public interface Future<V> {
    public fun cancel(mayInterruptIfRunning: Boolean): Boolean
    public fun isCancelled(): Boolean
    public fun isDone(): Boolean
    public fun get(): V
}
