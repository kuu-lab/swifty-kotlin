package kotlin

import kotlin.jvm.internal.__jvmSuppressedExceptions

public fun Throwable.addSuppressed(exception: Throwable) {
    if (this !== exception) this.addSuppressed(exception)
}

public val Throwable.suppressedExceptions: List<Throwable>
    get() = __jvmSuppressedExceptions(this).asList()
