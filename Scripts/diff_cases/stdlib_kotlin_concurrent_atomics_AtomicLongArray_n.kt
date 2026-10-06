@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*

fun updateAt(values: AtomicLongArray, index: Int, transform: (Long) -> Long): Unit =
    values.updateAt(index, transform)

fun updateAndFetchAt(values: AtomicLongArray, index: Int, transform: (Long) -> Long): Long =
    values.updateAndFetchAt(index, transform)

fun main() {}
