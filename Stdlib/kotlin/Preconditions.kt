package kotlin

import kswiftk.internal.*

fun require(condition: Boolean): Unit {
    if (!condition) {
        throw IllegalArgumentException("Failed requirement.")
    }
}

fun require(condition: Boolean, lazyMessage: () -> Any): Unit {
    if (!condition) {
        __requireLazy(false, lazyMessage)
    }
}

fun check(condition: Boolean): Unit {
    if (!condition) {
        throw IllegalStateException("Check failed.")
    }
}

fun check(condition: Boolean, lazyMessage: () -> Any): Unit {
    if (!condition) {
        __checkLazy(false, lazyMessage)
    }
}

fun assert(value: Boolean): Unit = __assert(value)

fun assert(value: Boolean, lazyMessage: () -> Any): Unit = __assertLazy(value, lazyMessage)

fun error(message: Any): Nothing = throw IllegalStateException(message.toString())

fun TODO(): Nothing = __todo()

fun TODO(reason: String): Nothing = __todo(reason)
