@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val values = AtomicLongArray(2)
    println(values.compareAndExchangeAt(0, 0L, 10L))
    println(values.compareAndSetAt(0, 10L, 20L))
    println(values.size)
    println(values.toString())
}
