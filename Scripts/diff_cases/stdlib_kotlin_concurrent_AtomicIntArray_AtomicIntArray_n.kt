// DIFF_CANDIDATE_ONLY
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_AtomicIntArray_AtomicIntArray_n.kt.expected
@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.concurrent.AtomicIntArray

fun main() {
    val values = AtomicIntArray(2)
    println(values.compareAndExchange(0, 0, 10))
    println(values.compareAndSet(0, 10, 20))
    println(values.length)
    println(values.toString())
}
