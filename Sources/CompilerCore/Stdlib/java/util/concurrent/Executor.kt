package java.util.concurrent

import java.lang.Runnable

public fun interface Executor {
    public fun execute(command: Runnable)
}

// Nominal compatibility for dispatcher conversion, not a native thread pool.
public interface ExecutorService : Executor
