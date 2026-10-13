// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_IncorrectDereferenceException_n_n.expected.stdout
// JVM kotlinc has no kotlin.native reference API for this fixture.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.IncorrectDereferenceException

fun main() {
    val noArg = IncorrectDereferenceException()
    val message = IncorrectDereferenceException("native message")

    println(noArg.message ?: "null")
    println(message.message ?: "null")
    println(noArg is Throwable)
    println(message is RuntimeException)
    // Widen the static type to exercise the runtime check without a disjoint-type diagnostic.
    val messageAsThrowable: Throwable = message
    println(messageAsThrowable is IllegalStateException)

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
