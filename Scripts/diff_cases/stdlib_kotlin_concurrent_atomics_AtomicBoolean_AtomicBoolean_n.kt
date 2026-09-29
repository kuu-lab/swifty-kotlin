@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicBoolean

// Kotlin 2.3.10's canonical reference lacks the legacy get/set/getAndSet
// aliases and value property; those compatibility declarations are covered by
// the Sema golden.
fun main() {
    val atomic = AtomicBoolean(true)
    println(atomic.load())
    atomic.store(false)
    println(atomic.exchange(true))
    println(atomic.compareAndExchange(true, false))
    println(atomic.toString())
}
