package kotlinx.coroutines

import kotlin.internal.KsSymbolName

@KsSymbolName("kk_dispatcher_default")
internal external fun __dispatcherDefault(): CoroutineDispatcher

@KsSymbolName("kk_dispatcher_main")
internal external fun __dispatcherMain(): CoroutineDispatcher

public object Dispatchers {
    public val Default: CoroutineDispatcher
        get() = __dispatcherDefault()

    // Compatibility aliases: no separate IO pool or unconfined event loop.
    public val IO: CoroutineDispatcher
        get() = Default

    public val Unconfined: CoroutineDispatcher
        get() = Default

    public val Main: CoroutineDispatcher
        get() = __dispatcherMain()
}
