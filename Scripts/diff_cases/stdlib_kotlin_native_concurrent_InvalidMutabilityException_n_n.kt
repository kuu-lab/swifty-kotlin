// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_concurrent_InvalidMutabilityException_n_n.expected.stdout
// Candidate-only: kotlin.native.concurrent is unavailable in JVM kotlinc; verify with the candidate runner.
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
