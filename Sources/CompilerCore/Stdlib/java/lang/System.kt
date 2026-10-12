package java.lang

import java.io.PrintStream
import kotlin.internal.KsSymbolName

public object System {
    public val err: PrintStream = PrintStream()

    @KsSymbolName("__kk_system_gc")
    private external fun __gc()

    public fun gc(): Unit = __gc()

    public fun exit(status: Int): Unit = kotlin.system.exitProcess(status)
}
