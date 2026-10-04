@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicInt

// Kotlin 2.3.10's canonical reference lacks the legacy getAnd* aliases and
// value property; those compatibility declarations are covered by the Sema golden.
fun main() {
    val atomic = AtomicInt(10)
    println(atomic.load())
    atomic.store(11)
    println(atomic.exchange(12))
    println(atomic.addAndFetch(3))
    println(atomic.compareAndExchange(15, 16))
    println(atomic.toString())
}
