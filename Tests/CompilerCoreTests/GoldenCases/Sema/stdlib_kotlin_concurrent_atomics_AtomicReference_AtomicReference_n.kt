@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.atomics.AtomicReference

fun atomicReferenceReceiverMembers(): String {
    val atomic = AtomicReference("initial")
    val loaded = atomic.load()
    atomic.store("stored")
    val exchanged = atomic.exchange("exchanged")
    val oldSet = atomic.exchange("next")
    val expected = atomic.load()
    val compared = atomic.compareAndExchange(expected, "compared")
    atomic.store("assigned")
    val current = atomic.load()
    return "$loaded:$exchanged:$oldSet:$compared:$current:${atomic.toString()}"
}
