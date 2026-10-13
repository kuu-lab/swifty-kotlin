package java.lang

import java.io.InputStream
import java.io.PrintStream
import kotlin.internal.KsSymbolName

public object System {
    public val err: PrintStream = PrintStream()

    @KsSymbolName("__kk_system_in")
    private external fun __standardInput(): InputStream

    public val `in`: InputStream = __standardInput()

    @KsSymbolName("__kk_system_gc")
    private external fun __gc()

    public fun gc(): Unit = __gc()

    public fun exit(status: Int): Unit = kotlin.system.exitProcess(status)
}
