package java.util.concurrent

public interface Future<V> {
    public fun cancel(mayInterruptIfRunning: Boolean): Boolean

    // isCancelled()/isDone() are Java isX getters: Kotlin sources address
    // them as properties on the JVM, so the bundled surface is a property
    // too — never parens-callable functions.
    public val isCancelled: Boolean
    public val isDone: Boolean
    public fun get(): V
    public fun get(timeout: Long, unit: TimeUnit): V
}
