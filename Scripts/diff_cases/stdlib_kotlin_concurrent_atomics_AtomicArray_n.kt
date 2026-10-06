@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*

fun fetchAndUpdateAt(atomic: AtomicArray<String>, transform: (String) -> String): String =
    atomic.fetchAndUpdateAt(0, transform)

fun updateAt(atomic: AtomicArray<String>, transform: (String) -> String): Unit =
    atomic.updateAt(0, transform)

fun updateAndFetchAt(atomic: AtomicArray<String>, transform: (String) -> String): String =
    atomic.updateAndFetchAt(0, transform)

fun main() {}
