// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.concurrent is a Kotlin/Native-only API.
@file:Suppress("DEPRECATION_ERROR")

import kotlin.native.concurrent.AtomicInt

fun useAtomicIntReceiver(atomic: AtomicInt) {
    atomic.value = 1
    atomic.compareAndSwap(1, 2)
    atomic.getAndAdd(3)
    atomic.getAndIncrement()
    atomic.getAndDecrement()
    atomic.increment()
    atomic.decrement()
    atomic.toString()
}
