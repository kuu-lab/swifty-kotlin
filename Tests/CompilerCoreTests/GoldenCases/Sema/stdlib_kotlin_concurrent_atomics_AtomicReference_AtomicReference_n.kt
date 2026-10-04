@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicReference

fun atomicReferenceReceiverMembers(): String {
    val atomic = AtomicReference("initial")
    val loaded = atomic.load()
    atomic.store("stored")
    val exchanged = atomic.exchange("exchanged")
    val oldSet = atomic.getAndSet("getAndSet")
    val expected = atomic.load()
    val compared = atomic.compareAndExchange(expected, "compared")
    atomic.value = "assigned"
    val current = atomic.value
    return "$loaded:$exchanged:$oldSet:$compared:$current:${atomic.toString()}"
}
