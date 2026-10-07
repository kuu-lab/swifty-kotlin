package kotlinx.coroutines

public open class BlockingEventLoop(
    public val thread: Any? = null
) : CoroutineDispatcher()
