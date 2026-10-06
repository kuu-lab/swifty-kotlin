@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicLong

fun atomicLongReceiverMembers(): String {
    val atomic = AtomicLong(10L)
    val loaded = atomic.load()
    atomic.store(11L)
    val exchanged = atomic.exchange(12L)
    val added = atomic.addAndFetch(3L)
    val oldAdded = atomic.fetchAndAdd(4L)
    val oldIncrement = atomic.fetchAndIncrement()
    val oldDecrement = atomic.fetchAndDecrement()
    val compared = atomic.compareAndExchange(15L, 16L)
    val current = atomic.load()
    return "$loaded:$exchanged:$added:$oldAdded:$oldIncrement:$oldDecrement:$compared:$current:${atomic.toString()}"
}
