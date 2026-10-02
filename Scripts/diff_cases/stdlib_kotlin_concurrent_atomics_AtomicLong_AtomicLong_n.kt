@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicLong

// Kotlin 2.3.10's canonical reference lacks the legacy getAnd* aliases and
// value property; those compatibility declarations are covered by the Sema golden.
fun main() {
    val atomic = AtomicLong(10L)
    println(atomic.load())
    atomic.store(11L)
    println(atomic.exchange(12L))
    println(atomic.addAndFetch(3L))
    println(atomic.compareAndExchange(15L, 16L))
    println(atomic.toString())
}
