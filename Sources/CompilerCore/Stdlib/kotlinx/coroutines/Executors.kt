package kotlinx.coroutines

import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService
import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_dispatcher_as_executor")
private external fun dispatcherAsExecutor(dispatcher: CoroutineDispatcher): Executor

public fun Executor.asCoroutineDispatcher(): CoroutineDispatcher =
    ExecutorCoroutineDispatcherImpl(this)

public fun ExecutorService.asCoroutineDispatcher(): ExecutorCoroutineDispatcher =
    ExecutorCoroutineDispatcherImpl(this)

public fun CoroutineDispatcher.asExecutor(): Executor =
    (this as? ExecutorCoroutineDispatcher)?.executor ?: dispatcherAsExecutor(this)
