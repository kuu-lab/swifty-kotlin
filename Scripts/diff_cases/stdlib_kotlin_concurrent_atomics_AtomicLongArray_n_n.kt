@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val zeros = AtomicLongArray(2)
    val source = longArrayOf(4, 5)
    val copied = AtomicLongArray(source)
    source[0] = 99
    println(zeros.size)
    println(copied.loadAt(0))
}
