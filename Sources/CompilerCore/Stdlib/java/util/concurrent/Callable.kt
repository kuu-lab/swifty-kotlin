package java.util.concurrent

// KUU-3059: java.util.concurrent.Callable — the value-returning task type
// consumed by ExecutorService.submit and FutureTask.
public fun interface Callable<V> {
    public fun call(): V
}
