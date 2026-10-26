package java.lang

import kotlin.internal.KsSymbolName

public object Runtime {
    @KsSymbolName("__kk_runtime_getRuntime")
    private external fun __getRuntime(): Runtime

    @KsSymbolName("__kk_runtime_totalMemory")
    private external fun __totalMemory(): kotlin.Long

    @KsSymbolName("__kk_runtime_freeMemory")
    private external fun __freeMemory(): kotlin.Long

    @KsSymbolName("__kk_runtime_maxMemory")
    private external fun __maxMemory(): kotlin.Long

    @KsSymbolName("__kk_runtime_availableProcessors")
    private external fun __availableProcessors(): Int

    public fun getRuntime(): Runtime = __getRuntime()

    public fun totalMemory(): kotlin.Long = __totalMemory()

    public fun freeMemory(): kotlin.Long = __freeMemory()

    public fun maxMemory(): kotlin.Long = __maxMemory()

    public fun availableProcessors(): Int = __availableProcessors()
}
