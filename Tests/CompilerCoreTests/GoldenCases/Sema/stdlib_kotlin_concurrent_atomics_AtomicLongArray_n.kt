@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicLongArray

fun atomicLongArrayUpdateAt(
    values: AtomicLongArray,
    index: Int,
    transform: (Long) -> Long
): Unit = values.updateAt(index, transform)

fun atomicLongArrayUpdateAndFetchAt(
    values: AtomicLongArray,
    index: Int,
    transform: (Long) -> Long
): Long = values.updateAndFetchAt(index, transform)
