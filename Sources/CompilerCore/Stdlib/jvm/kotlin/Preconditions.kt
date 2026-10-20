@file:kotlin.jvm.JvmName("PreconditionsKt")
package kotlin

public inline fun check(value: Boolean): Unit {
    if (!value) throw IllegalStateException("Check failed.")
}

public inline fun check(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalStateException(lazyMessage().toString())
}

public inline fun error(message: Any): Nothing =
    throw IllegalStateException(message.toString())
