@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicIntArray

fun atomicIntArrayUpdateAt(
    atomic: AtomicIntArray,
    transform: (Int) -> Int
): Unit = atomic.updateAt(0, transform)

fun atomicIntArrayUpdateAndFetchAt(
    atomic: AtomicIntArray,
    transform: (Int) -> Int
): Int = atomic.updateAndFetchAt(0, transform)
