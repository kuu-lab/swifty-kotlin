@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.AtomicReference

fun atomicReferenceReceiverSurface(
    atomic: AtomicReference<String>,
    expectedValue: String,
    newValue: String
): String {
    val exchanged: String = atomic.compareAndExchange(expectedValue, newValue)
    val oldValue: String = atomic.getAndSet(newValue)
    val current: String = atomic.value
    atomic.value = newValue
    return atomic.toString()
}
