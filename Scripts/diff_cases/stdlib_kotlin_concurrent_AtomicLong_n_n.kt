// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_AtomicLong_n_n.expected.stdout
// Candidate-only: kotlin.concurrent.AtomicLong is Kotlin/Native-only in Kotlin 2.3.10.

import kotlin.concurrent.AtomicLong

fun main() {
    val atomic = AtomicLong(7L)
    println(atomic.value)
    println(atomic.toString())
}
