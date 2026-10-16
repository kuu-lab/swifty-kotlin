// DIFF_CANDIDATE_ONLY: kotlin.concurrent.AtomicIntArray is Kotlin/Native-only and has no JVM kotlinc oracle.
// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_concurrent_AtomicIntArray_n_n.expected
// Exercise public allocation and indexed storage here; the internal array-copy constructor has a source-backed backend regression test.

@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.concurrent.AtomicIntArray

fun main() {
    val values = AtomicIntArray(2)
    values[0] = 4
    values[1] = 5
    println(values.size)
    println(values[0])
}
