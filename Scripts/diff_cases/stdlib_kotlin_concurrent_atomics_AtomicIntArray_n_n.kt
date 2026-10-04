@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray

fun main() {
    val zeros = AtomicIntArray(2)
    val source = intArrayOf(4, 5)
    val copied = AtomicIntArray(source)
    source[0] = 99
    println(zeros.size)
    println(copied.loadAt(0))
}
