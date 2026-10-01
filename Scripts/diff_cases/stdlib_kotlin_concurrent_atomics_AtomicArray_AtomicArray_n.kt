// SKIP-DIFF (DEBT-DIFF-001): the AtomicArray receiver members
// compareAndExchange / compareAndSet / get / set / getAndSet / length
// are Kotlin/Native-only in Kotlin 2.3.10 and are unavailable in the JVM
// kotlinc reference environment.

@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicArray

fun main() {
    val values = AtomicArray<String>(2)
    values.storeAt(0, "a")
    values[1] = "b"
    println(values.loadAt(0))
    println(values[1])
    println(values.getAndSet(0, "x"))
    println(values.exchangeAt(1, "y"))
    println(values.compareAndExchange(0, "x", "z"))
    println(values.compareAndSet(0, "z", "w"))
    println(values.compareAndExchangeAt(0, "w", "v"))
    println(values.compareAndSetAt(0, "v", "u"))
    println(values.length)
    println(values.size)
    println(values.toString())
}
