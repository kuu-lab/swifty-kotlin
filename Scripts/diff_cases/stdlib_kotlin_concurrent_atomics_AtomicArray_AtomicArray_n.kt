@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.atomicArrayOfNulls

fun main() {
    val values = atomicArrayOfNulls<String>(2)
    values.storeAt(0, "a")
    values.storeAt(1, "b")
    println(values.loadAt(0))
    println(values.loadAt(1))
    println(values.exchangeAt(0, "x"))
    println(values.exchangeAt(1, "y"))
    println(values.compareAndExchangeAt(0, "x", "z"))
    println(values.compareAndSetAt(0, "z", "w"))
    println(values.compareAndExchangeAt(0, "w", "v"))
    println(values.compareAndSetAt(0, "v", "u"))
    println(values.size)
    println(values.toString())
}
