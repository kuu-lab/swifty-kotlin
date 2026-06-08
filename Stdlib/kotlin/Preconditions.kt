package kotlin

import kswiftk.internal.*

fun require(condition: Boolean): Unit {
    if (!condition) {
        throw IllegalArgumentException("Failed requirement.")
    }
}

fun require(condition: Boolean, lazyMessage: () -> Any): Unit {
    if (!condition) {
        throw IllegalArgumentException(lazyMessage().toString())
    }
}

fun check(condition: Boolean): Unit {
    if (!condition) {
        throw IllegalStateException("Check failed.")
    }
}

fun check(condition: Boolean, lazyMessage: () -> Any): Unit {
    if (!condition) {
        throw IllegalStateException(lazyMessage().toString())
    }
}

fun assert(value: Boolean): Unit {
    // Assert is typically no-op in non-debug builds
}

fun assert(value: Boolean, lazyMessage: () -> Any): Unit {
    // Assert is typically no-op in non-debug builds
}

fun error(message: Any): Nothing = throw IllegalStateException(message.toString())

fun TODO(): Nothing = __todo()

fun TODO(reason: String): Nothing = __todo(reason)
