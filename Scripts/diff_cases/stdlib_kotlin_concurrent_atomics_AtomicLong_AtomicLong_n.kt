@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*

// Exercise the canonical Kotlin names, not Java getAnd* aliases.
fun main() {
    val atomic = AtomicLong(10L)
    println(atomic.load())
    atomic.store(11L)
    println(atomic.exchange(12L))
    println(atomic.addAndFetch(3L))
    println(atomic.fetchAndAdd(4L))
    println(atomic.fetchAndIncrement())
    println(atomic.fetchAndDecrement())
    println(atomic.incrementAndFetch())
    println(atomic.decrementAndFetch())
    println(atomic.compareAndExchange(15L, 16L))
    println(atomic.toString())
}
