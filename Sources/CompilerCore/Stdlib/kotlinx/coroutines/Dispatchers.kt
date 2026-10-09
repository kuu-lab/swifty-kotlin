package kotlinx.coroutines

import kotlin.internal.KsSymbolName

@KsSymbolName("__kk_dispatcher_named")
internal external fun __dispatcherNamed(kind: Int): CoroutineDispatcher

@KsSymbolName("kk_dispatcher_main")
internal external fun __dispatcherMain(): MainCoroutineDispatcher

public object Dispatchers {
    public val Default: CoroutineDispatcher
        get() = __dispatcherNamed(0)

    public val IO: CoroutineDispatcher
        get() = __dispatcherNamed(1)

    public val Unconfined: CoroutineDispatcher
        get() = __dispatcherNamed(2)

    public val Main: MainCoroutineDispatcher
        get() = __dispatcherMain()
}
