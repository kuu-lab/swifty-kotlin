// SKIP-DIFF (DEBT-DIFF-001): the AtomicLongArray updateAt / updateAndFetchAt
// receiver extensions are Kotlin/Native-only in Kotlin 2.3.10 and are
// unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicLongArray

fun updateAt(values: AtomicLongArray, index: Int, transform: (Long) -> Long): Unit =
    values.updateAt(index, transform)

fun updateAndFetchAt(values: AtomicLongArray, index: Int, transform: (Long) -> Long): Long =
    values.updateAndFetchAt(index, transform)

fun main() {}
