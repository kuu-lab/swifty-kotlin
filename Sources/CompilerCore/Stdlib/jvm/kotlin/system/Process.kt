@file:kotlin.jvm.JvmName("ProcessKt")
package kotlin.system

@kotlin.internal.InlineOnly
inline fun exitProcess(status: Int): Nothing {
    java.lang.System.exit(status)
    throw IllegalStateException("System.exit returned normally")
}
