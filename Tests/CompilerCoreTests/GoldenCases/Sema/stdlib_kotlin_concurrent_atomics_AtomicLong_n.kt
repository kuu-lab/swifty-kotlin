@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicLong

fun atomicLongIncrementAndFetch(atomic: AtomicLong): Long = atomic.incrementAndFetch()

fun atomicLongDecrementAndFetch(atomic: AtomicLong): Long = atomic.decrementAndFetch()

fun atomicLongPlusAssign(atomic: AtomicLong, delta: Long): Unit = atomic.plusAssign(delta)

fun atomicLongMinusAssign(atomic: AtomicLong, delta: Long): Unit = atomic.minusAssign(delta)

fun atomicLongCompoundAssign(atomic: AtomicLong, delta: Long) {
    atomic += delta
    atomic -= delta
}

fun atomicLongUpdate(atomic: AtomicLong, transform: (Long) -> Long): Unit = atomic.update(transform)

fun atomicLongUpdateAndFetch(atomic: AtomicLong, transform: (Long) -> Long): Long = atomic.updateAndFetch(transform)
