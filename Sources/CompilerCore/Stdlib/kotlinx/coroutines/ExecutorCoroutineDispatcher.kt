package kotlinx.coroutines

import java.io.Closeable
import java.util.concurrent.Executor
import java.util.concurrent.ExecutorService

public abstract class ExecutorCoroutineDispatcher : CoroutineDispatcher(), Closeable {
    public abstract val executor: Executor
    public abstract override fun close()
}

internal class ExecutorCoroutineDispatcherImpl(
    override val executor: Executor
) : ExecutorCoroutineDispatcher() {
    override fun close() {
        (executor as? Closeable)?.close()
        (executor as? ExecutorService)?.shutdown()
    }

    override fun toString(): String = executor.toString()
}
