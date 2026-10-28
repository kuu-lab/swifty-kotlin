@file:kotlin.jvm.JvmName("PreconditionsKt")
package kotlin

public class NotImplementedError : Error {
    public constructor() : super("An operation is not implemented.")
    public constructor(message: String) : super(message)
}

public inline fun TODO(): Nothing = throw NotImplementedError()

public inline fun TODO(reason: String): Nothing =
    throw NotImplementedError("An operation is not implemented: " + reason)

public inline fun require(value: Boolean): Unit {
    if (!value) throw IllegalArgumentException("Failed requirement.")
}

public inline fun require(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalArgumentException(lazyMessage().toString())
}

public inline fun check(value: Boolean): Unit {
    if (!value) throw IllegalStateException("Check failed.")
}

public inline fun check(value: Boolean, lazyMessage: () -> Any): Unit {
    if (!value) throw IllegalStateException(lazyMessage().toString())
}

public inline fun error(message: Any): Nothing =
    throw IllegalStateException(message.toString())

public inline fun <T : Any> requireNotNull(value: T?): T {
    if (value == null) throw IllegalArgumentException("Required value was null.")
    return value as T
}

public inline fun <T : Any> requireNotNull(value: T?, lazyMessage: () -> Any): T {
    if (value == null) throw IllegalArgumentException(lazyMessage().toString())
    return value as T
}

public inline fun <T : Any> checkNotNull(value: T?): T {
    if (value == null) throw IllegalStateException("Required value was null.")
    return value as T
}

public inline fun <T : Any> checkNotNull(value: T?, lazyMessage: () -> Any): T {
    if (value == null) throw IllegalStateException(lazyMessage().toString())
    return value as T
}
