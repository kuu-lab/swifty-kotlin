// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent APIs are only available on Kotlin/Native targets.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.FreezingException

fun main() {
    val exception = FreezingException("target", "blocker")
    println(exception.message)
    try {
        throw exception
    } catch (caught: FreezingException) {
        println(caught.message)
    }
}
