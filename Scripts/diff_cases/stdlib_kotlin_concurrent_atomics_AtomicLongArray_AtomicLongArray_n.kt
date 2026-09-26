// SKIP-DIFF (DEBT-DIFF-001): the AtomicLongArray receiver members
// compareAndExchange / compareAndSet / length are Kotlin/Native-only in
// Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicLongArray

fun main() {
    val values = AtomicLongArray(2)
    println(values.compareAndExchange(0, 0L, 10L))
    println(values.compareAndSet(0, 10L, 20L))
    println(values.length)
    println(values.size)
    println(values.toString())
}
