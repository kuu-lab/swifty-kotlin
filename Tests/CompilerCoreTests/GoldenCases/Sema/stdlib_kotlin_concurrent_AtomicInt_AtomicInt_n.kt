@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

package golden.sema

import kotlin.concurrent.AtomicInt

fun atomicIntReceiverSurface(
    atomic: AtomicInt,
    expectedValue: Int,
    newValue: Int,
    delta: Int
): String {
    val exchanged: Int = atomic.compareAndExchange(expectedValue, newValue)
    val added: Int = atomic.getAndAdd(delta)
    val incremented: Int = atomic.getAndIncrement()
    val decremented: Int = atomic.getAndDecrement()
    val current: Int = atomic.value
    atomic.value = newValue
    return atomic.toString()
}
