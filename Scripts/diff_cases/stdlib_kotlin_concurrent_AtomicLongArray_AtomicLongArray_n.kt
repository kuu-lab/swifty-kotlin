// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_AtomicLongArray_AtomicLongArray_n.expected.stdout
// Candidate-only: kotlin.concurrent atomic APIs have no JVM kotlinc reference.

@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.concurrent.AtomicLongArray

fun main() {
    val values = AtomicLongArray(2)
    println(values.compareAndExchange(0, 0L, 10L))
    println(values.compareAndSet(0, 10L, 20L))
    println(values.length)
    println(values.toString())
}
