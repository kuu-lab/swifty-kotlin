// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.IncorrectDereferenceException

fun main() {
    val noArg = IncorrectDereferenceException()
    val message = IncorrectDereferenceException("native message")

    println(noArg.message ?: "null")
    println(message.message ?: "null")
    println(noArg is Throwable)
    println(message is RuntimeException)
    println(message is IllegalStateException)

    try {
        throw message
    } catch (exception: RuntimeException) {
        println("caught-runtime:" + (exception.message ?: "null"))
    }

    try {
        throw noArg
    } catch (exception: IllegalStateException) {
        println("caught-illegal-state")
    } catch (exception: Throwable) {
        println("caught-throwable:" + (exception.message ?: "null"))
    }
}
