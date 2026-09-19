@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicInt

fun atomicIntReceiverMembers(): String {
    val atomic = AtomicInt(10)
    val loaded = atomic.load()
    atomic.store(11)
    val exchanged = atomic.exchange(12)
    val added = atomic.addAndFetch(3)
    val oldAdded = atomic.getAndAdd(4)
    val oldIncrement = atomic.getAndIncrement()
    val oldDecrement = atomic.getAndDecrement()
    val compared = atomic.compareAndExchange(15, 16)
    val current = atomic.value
    return "$loaded:$exchanged:$added:$oldAdded:$oldIncrement:$oldDecrement:$compared:$current:${atomic.toString()}"
}
