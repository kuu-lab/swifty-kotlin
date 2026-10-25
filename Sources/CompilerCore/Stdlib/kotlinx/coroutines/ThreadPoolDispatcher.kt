package kotlinx.coroutines

import java.util.concurrent.ExecutorService
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_coroutine_new_thread_pool_executor")
private external fun newNativeThreadPoolExecutor(nThreads: Int, name: String, scheduled: Boolean): ExecutorService

public fun newSingleThreadContext(name: String): CoroutineDispatcher =
    ExecutorCoroutineDispatcherImpl(newNativeThreadPoolExecutor(1, name, false))

public fun newFixedThreadPoolContext(nThreads: Int, name: String): CoroutineDispatcher {
    require(nThreads > 0) { "Expected at least one thread, but got $nThreads" }
    return ExecutorCoroutineDispatcherImpl(newNativeThreadPoolExecutor(nThreads, name, false))
}

public fun newScheduledThreadPoolContext(nThreads: Int, name: String): CoroutineDispatcher {
    require(nThreads > 0) { "Expected at least one thread, but got $nThreads" }
    return ExecutorCoroutineDispatcherImpl(newNativeThreadPoolExecutor(nThreads, name, true))
}
