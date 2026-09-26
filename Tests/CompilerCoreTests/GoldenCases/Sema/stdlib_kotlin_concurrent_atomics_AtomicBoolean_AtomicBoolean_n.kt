@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicBoolean

fun atomicBooleanReceiverMembers(): String {
    val atomic = AtomicBoolean(true)
    val loaded = atomic.load()
    atomic.store(false)
    val exchanged = atomic.exchange(true)
    val compared = atomic.compareAndExchange(true, false)
    val set = atomic.compareAndSet(false, true)
    val current = atomic.value
    return "$loaded:$exchanged:$compared:$set:$current:${atomic.toString()}"
}
