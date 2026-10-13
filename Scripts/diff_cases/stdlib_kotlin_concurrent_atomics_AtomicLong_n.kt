@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*

// KSP-1104: incrementAndFetch/decrementAndFetch, plusAssign/minusAssign
// operators, and the update/updateAndFetch CAS loops on atomics.AtomicLong.
fun main() {
    val atomic = AtomicLong(10L)
    println(atomic.incrementAndFetch())              // 11
    println(atomic.decrementAndFetch())              // 10
    atomic += 5L
    println(atomic.load())                           // 15
    atomic -= 3L
    println(atomic.load())                           // 12
    atomic.update(transform = { it * 2 })
    println(atomic.load())                           // 24
    println(atomic.updateAndFetch(transform = { it + 1 })) // 25
    println(atomic.load())                           // 25
}
