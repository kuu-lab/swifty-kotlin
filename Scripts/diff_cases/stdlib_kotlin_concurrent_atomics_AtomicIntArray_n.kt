@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*

fun updateAt(atomic: AtomicIntArray, transform: (Int) -> Int): Unit =
    atomic.updateAt(0, transform)

fun updateAndFetchAt(atomic: AtomicIntArray, transform: (Int) -> Int): Int =
    atomic.updateAndFetchAt(0, transform)

fun main() {}
