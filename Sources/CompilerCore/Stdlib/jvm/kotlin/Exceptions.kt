package kotlin

import kotlin.jvm.internal.__jvmSuppressedExceptions
import kotlin.jvm.internal.__jvmStringWriter
import kotlin.jvm.internal.__jvmPrintWriter
import kotlin.jvm.internal.__jvmPrintStackTrace

public fun Throwable.addSuppressed(exception: Throwable) {
    if (this !== exception) this.addSuppressed(exception)
}

public val Throwable.suppressedExceptions: List<Throwable>
    get() = __jvmSuppressedExceptions(this).asList()

public fun Throwable.stackTraceToString(): String {
    val buffer = __jvmStringWriter()
    __jvmPrintStackTrace(this, __jvmPrintWriter(buffer))
    return buffer.toString()
}
