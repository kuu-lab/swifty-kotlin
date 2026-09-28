@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicArray

fun atomicArrayFetchAndUpdateAt(
    atomic: AtomicArray<String>,
    transform: (String) -> String
): String = atomic.fetchAndUpdateAt(0, transform)

fun atomicArrayUpdateAt(
    atomic: AtomicArray<String>,
    transform: (String) -> String
): Unit = atomic.updateAt(0, transform)

fun atomicArrayUpdateAndFetchAt(
    atomic: AtomicArray<String>,
    transform: (String) -> String
): String = atomic.updateAndFetchAt(0, transform)
