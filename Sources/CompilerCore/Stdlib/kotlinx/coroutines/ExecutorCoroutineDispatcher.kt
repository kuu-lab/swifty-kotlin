package kotlinx.coroutines

import java.io.Closeable
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService

public abstract class ExecutorCoroutineDispatcher : CoroutineDispatcher(), Closeable {
    public abstract val executor: Executor
    public abstract override fun close()
}

public fun Executor.asCoroutineDispatcher(): CoroutineDispatcher =
    ExecutorCoroutineDispatcherImpl(this)

public fun ExecutorService.asCoroutineDispatcher(): ExecutorCoroutineDispatcher =
    ExecutorCoroutineDispatcherImpl(this)

public fun CoroutineDispatcher.asExecutor(): Executor =
    (this as? ExecutorCoroutineDispatcher)?.executor ?: Executor { command -> command.run() }

private class ExecutorCoroutineDispatcherImpl(
    override val executor: Executor
) : ExecutorCoroutineDispatcher() {
    override fun close() {
        (executor as? Closeable)?.close()
        (executor as? ExecutorService)?.shutdown()
    }

    override fun toString(): String = executor.toString()
}
