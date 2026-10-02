// SKIP-DIFF (DEBT-DIFF-001): the AtomicIntArray receiver members
// compareAndExchange / compareAndSet / length are Kotlin/Native-only in
// Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray

fun main() {
    val values = AtomicIntArray(2)
    println(values.compareAndExchange(0, 0, 10))
    println(values.compareAndSet(0, 10, 20))
    println(values.length)
    println(values.size)
    println(values.toString())
}
