package kotlinx.coroutines

import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService

// Executor scheduling and lifecycle are not owned by the native dispatcher.
public fun Executor.asCoroutineDispatcher(): CoroutineDispatcher = Dispatchers.Default

public fun ExecutorService.asCoroutineDispatcher(): CoroutineDispatcher = Dispatchers.Default
