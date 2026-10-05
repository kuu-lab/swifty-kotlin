@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*

// Exercise the canonical Kotlin names, not Java getAnd* aliases.
fun main() {
    val atomic = AtomicInt(10)
    println(atomic.load())
    atomic.store(11)
    println(atomic.exchange(12))
    println(atomic.addAndFetch(3))
    println(atomic.fetchAndAdd(4))
    println(atomic.fetchAndIncrement())
    println(atomic.fetchAndDecrement())
    println(atomic.incrementAndFetch())
    println(atomic.decrementAndFetch())
    println(atomic.compareAndExchange(15, 16))
    println(atomic.toString())
}
