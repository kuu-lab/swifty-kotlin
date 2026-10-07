package java.util.concurrent

import java.lang.Runnable

public interface ExecutorService : Executor {
    public fun shutdown()
    public fun shutdownNow(): List<Runnable>
    public fun isShutdown(): Boolean
    public fun isTerminated(): Boolean
}
