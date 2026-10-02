@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicInt

fun atomicIntIncrementAndFetch(atomic: AtomicInt): Int = atomic.incrementAndFetch()

fun atomicIntDecrementAndFetch(atomic: AtomicInt): Int = atomic.decrementAndFetch()

fun atomicIntPlusAssign(atomic: AtomicInt, delta: Int): Unit {
    atomic += delta
}

fun atomicIntMinusAssign(atomic: AtomicInt, delta: Int): Unit {
    atomic -= delta
}

fun atomicIntUpdate(
    atomic: AtomicInt,
    transform: (Int) -> Int
): Unit = atomic.update(transform)

fun atomicIntUpdateAndFetch(
    atomic: AtomicInt,
    transform: (Int) -> Int
): Int = atomic.updateAndFetch(transform)
