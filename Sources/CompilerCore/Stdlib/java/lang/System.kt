package java.lang

import kotlin.internal.KsSymbolName

public object System {
    @KsSymbolName("__kk_system_gc")
    private external fun __gc()

    public fun gc(): Unit = __gc()

    public fun exit(status: Int): Unit = kotlin.system.exitProcess(status)
}
