package kotlin.system

import java.io.InputStream
import java.io.PrintStream
import kotlin.internal.KsSymbolName

// Compatibility object retained for the JVM-shaped system API used by existing
// diff cases.
public object System {
    // The default-import compatibility object must expose the JVM stderr stream too.
    public val err: PrintStream = java.lang.System.err

    public val `in`: InputStream = java.lang.System.`in`

    @KsSymbolName("__kk_system_currentTimeMillis")
    private external fun __currentTimeMillis(): Long

    @KsSymbolName("__kk_system_nanoTime")
    private external fun __nanoTime(): Long

    @KsSymbolName("__kk_system_process_start_nanos")
    private external fun __processStartNanos(): Long

    public fun currentTimeMillis(): Long = __currentTimeMillis()

    public fun nanoTime(): Long = __nanoTime()

    public fun processStartNanos(): Long = __processStartNanos()

    public fun getProperty(propertyName: String): String? =
        java.lang.System.getProperty(propertyName)

    public fun getProperty(propertyName: String, defaultValue: String): String =
        java.lang.System.getProperty(propertyName, defaultValue)

    public fun lineSeparator(): String = java.lang.System.lineSeparator()

    public fun identityHashCode(value: Any?): Int = java.lang.System.identityHashCode(value)

    public fun arraycopy(
        src: Any?,
        srcPos: Int,
        dest: Any?,
        destPos: Int,
        length: Int
    ): Unit = java.lang.System.arraycopy(src, srcPos, dest, destPos, length)

    public fun exit(status: Int): Unit = java.lang.System.exit(status)
}
