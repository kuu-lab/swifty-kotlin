@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.AtomicLong

fun atomicLongReceiverSurface(
    atomic: AtomicLong,
    expectedValue: Long,
    newValue: Long,
    delta: Long
): String {
    val exchanged: Long = atomic.compareAndExchange(expectedValue, newValue)
    val added: Long = atomic.getAndAdd(delta)
    val incremented: Long = atomic.getAndIncrement()
    val decremented: Long = atomic.getAndDecrement()
    val current: Long = atomic.value
    atomic.value = newValue
    return atomic.toString()
}
