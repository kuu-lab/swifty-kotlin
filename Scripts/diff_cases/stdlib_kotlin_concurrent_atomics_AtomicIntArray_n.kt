// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent.atomics is Native-only
// in Kotlin 2.3.10 and is unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicIntArray

fun updateAt(atomic: AtomicIntArray, transform: (Int) -> Int): Unit =
    atomic.updateAt(0, transform)

fun updateAndFetchAt(atomic: AtomicIntArray, transform: (Int) -> Int): Int =
    atomic.updateAndFetchAt(0, transform)

fun main() {}
