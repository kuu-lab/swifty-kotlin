@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray

fun main() {
    val values = AtomicIntArray(2)
    println(values.compareAndExchangeAt(0, 0, 10))
    println(values.compareAndSetAt(0, 10, 20))
    println(values.size)
    println(values.toString())
}
