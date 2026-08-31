@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.IncorrectDereferenceException

fun noArg(): IncorrectDereferenceException = IncorrectDereferenceException()

fun message(message: String): IncorrectDereferenceException =
    IncorrectDereferenceException(message)

fun isRuntimeException(exception: IncorrectDereferenceException): Boolean =
    exception is RuntimeException

fun isException(exception: IncorrectDereferenceException): Boolean =
    exception is Exception

fun isIllegalStateException(exception: IncorrectDereferenceException): Boolean =
    exception is IllegalStateException

fun catchRuntimeException(): String =
    try {
        throw IncorrectDereferenceException("runtime")
    } catch (exception: RuntimeException) {
        exception.message ?: "caught"
    }

fun catchThrowable(): String =
    try {
        throw IncorrectDereferenceException("throwable")
    } catch (exception: Throwable) {
        exception.message ?: "caught"
    }
