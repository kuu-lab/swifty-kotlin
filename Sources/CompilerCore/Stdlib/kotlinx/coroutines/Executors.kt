package kotlinx.coroutines

import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService

// Executor scheduling and lifecycle are not owned by the native dispatcher.
public fun Executor.asCoroutineDispatcher(): CoroutineDispatcher =
    ExecutorCoroutineDispatcherImpl(this)

public fun ExecutorService.asCoroutineDispatcher(): ExecutorCoroutineDispatcher =
    ExecutorCoroutineDispatcherImpl(this)

public fun CoroutineDispatcher.asExecutor(): Executor =
    (this as? ExecutorCoroutineDispatcher)?.executor ?: Executor { command -> command.run() }
