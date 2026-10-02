package kotlinx.coroutines

// Dispatcher handles use the existing scheduler; these views do not change it.
public val CoroutineDispatcher.immediate: CoroutineDispatcher
    get() = this

public fun CoroutineDispatcher.limitedParallelism(parallelism: Int): CoroutineDispatcher {
    require(parallelism > 0) { "Expected positive parallelism level, but got $parallelism" }
    return this
}
