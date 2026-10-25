package java.util.concurrent

import java.lang.Runnable

public interface ExecutorService : Executor {
    public fun shutdown()
    public fun shutdownNow(): List<Runnable>

    // Java isX() methods surface as Kotlin properties — keep them vals so
    // `executor.isShutdown` resolves identically under kswiftc and kotlinc.
    public val isShutdown: Boolean
    public val isTerminated: Boolean

    // KUU-3059: the remaining ExecutorService surface. awaitTermination is
    // blocking; submit/invokeAll/invokeAny are implemented by the bundled
    // Executors pools.
    public fun awaitTermination(timeout: Long, unit: TimeUnit): Boolean
    public fun <T> submit(task: Callable<T>): Future<T>
    public fun <T> submit(task: Runnable, result: T): Future<T>
    public fun submit(task: Runnable): Future<*>
    public fun <T> invokeAll(tasks: Collection<Callable<T>>): List<Future<T>>
    public fun <T> invokeAny(tasks: Collection<Callable<T>>): T
}
