package kotlinx.coroutines

// Compatibility factories; names do not create or identify native pools.
public fun newSingleThreadContext(name: String): CoroutineDispatcher = Dispatchers.Default

public fun newFixedThreadPoolContext(nThreads: Int, name: String): CoroutineDispatcher {
    require(nThreads > 0) { "Expected at least one thread, but got $nThreads" }
    return Dispatchers.Default
}

public fun newScheduledThreadPoolContext(nThreads: Int, name: String): CoroutineDispatcher {
    require(nThreads > 0) { "Expected at least one thread, but got $nThreads" }
    return Dispatchers.Default
}
