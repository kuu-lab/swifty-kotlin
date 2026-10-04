@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

package golden.sema

import kotlin.native.concurrent.InvalidMutabilityException

fun construct(message: String): RuntimeException = InvalidMutabilityException(message)

fun catchMessage(): String =
    try {
        throw InvalidMutabilityException("mutation blocked")
    } catch (e: InvalidMutabilityException) {
        e.message ?: "missing"
    }
