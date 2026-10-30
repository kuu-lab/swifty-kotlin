package java.lang

import java.io.InputStream
import java.io.PrintStream
import java.util.__identityHashCode
import kotlin.collections.buildMap
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

    @KsSymbolName("__kk_system_setProperty")
    private external fun __setProperty(propertyName: String, value: String): String?

    @KsSymbolName("__kk_system_clearProperty")
    private external fun __clearProperty(propertyName: String): String?

    @KsSymbolName("__kk_system_getenv")
    private external fun __getenv(variableName: String): String?

    @KsSymbolName("__kk_system_envCount")
    private external fun __environmentCount(): Int

    @KsSymbolName("__kk_system_envKeyAt")
    private external fun __environmentKeyAt(index: Int): String?

    @KsSymbolName("__kk_system_envValueAt")
    private external fun __environmentValueAt(index: Int): String?

    @KsSymbolName("__kk_system_currentTimeMillis")
    private external fun __currentTimeMillis(): kotlin.Long

    @KsSymbolName("__kk_system_nanoTime")
    private external fun __nanoTime(): kotlin.Long

    @KsSymbolName("__kk_system_process_start_nanos")
    private external fun __processStartNanos(): kotlin.Long

    public fun getProperty(propertyName: String): String? = __getProperty(propertyName)

    public fun getProperty(propertyName: String, defaultValue: String): String =
        __getProperty(propertyName) ?: defaultValue

    public fun setProperty(propertyName: String, value: String): String? =
        __setProperty(propertyName, value)

    public fun clearProperty(propertyName: String): String? = __clearProperty(propertyName)

    public fun getenv(variableName: String): String? = __getenv(variableName)

    public fun getenv(): Map<String, String> = buildMap(__environmentCount()) {
        for (index in 0 until __environmentCount()) {
            val name = __environmentKeyAt(index) ?: continue
            val value = __environmentValueAt(index) ?: continue
            put(name, value)
        }
    }

    public fun currentTimeMillis(): kotlin.Long = __currentTimeMillis()

    public fun nanoTime(): kotlin.Long = __nanoTime()

    public fun processStartNanos(): kotlin.Long = __processStartNanos()

    public fun identityHashCode(value: Any?): Int = __identityHashCode(value)

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
