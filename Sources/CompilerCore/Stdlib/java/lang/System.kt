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

    @KsSymbolName("__kk_system_getProperty")
    private external fun __getProperty(propertyName: String): String?

    public fun getProperty(propertyName: String): String? = __getProperty(propertyName)

    public fun getProperty(propertyName: String, defaultValue: String): String =
        __getProperty(propertyName) ?: defaultValue

    public fun lineSeparator(): String = __getProperty("line.separator") ?: "\n"

    public fun gc(): Unit = __gc()

    public fun arraycopy(
        src: Any?,
        srcPos: Int,
        dest: Any?,
        destPos: Int,
        length: Int
    ): Unit = __arraycopy(src, srcPos, dest, destPos, length)

    public fun exit(status: Int): Unit = kotlin.system.exitProcess(status)
}

@KsSymbolName("__kk_system_arraycopy")
private external fun __arraycopy(
    src: Any?,
    srcPos: Int,
    dest: Any?,
    destPos: Int,
    length: Int
)
