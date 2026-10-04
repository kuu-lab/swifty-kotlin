// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent is a Kotlin/Native-only API unavailable in JVM kotlinc.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.concurrent.InvalidMutabilityException

fun main() {
    try {
        throw InvalidMutabilityException("mutation blocked")
    } catch (e: InvalidMutabilityException) {
        println(e.message)
        println(e.cause == null)
        println(e is RuntimeException)
    }
}
