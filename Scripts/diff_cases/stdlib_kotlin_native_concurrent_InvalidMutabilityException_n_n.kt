// CANDIDATE-ONLY: kotlin.native.concurrent is unavailable in JVM kotlinc; verify with the candidate runner.
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
