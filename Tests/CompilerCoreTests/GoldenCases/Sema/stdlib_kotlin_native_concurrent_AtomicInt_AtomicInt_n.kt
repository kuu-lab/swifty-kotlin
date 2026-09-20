@file:Suppress("DEPRECATION_ERROR")

package golden.sema

import kotlin.native.concurrent.AtomicInt

fun atomicIntReceiverSurface(
    atomic: AtomicInt,
    expected: Int,
    newValue: Int,
    delta: Int
): String {
    val oldValue: Int = atomic.value
    val swapped: Int = atomic.compareAndSwap(expected, newValue)
    val added: Int = atomic.getAndAdd(delta)
    val incremented: Int = atomic.getAndIncrement()
    val decremented: Int = atomic.getAndDecrement()
    atomic.increment()
    atomic.decrement()
    atomic.value = newValue
    return atomic.toString()
}
