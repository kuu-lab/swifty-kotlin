@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.*

fun main() {
    val atomic = AtomicInt(10)
    println(atomic.incrementAndFetch())
    println(atomic.decrementAndFetch())
    atomic += 5
    println(atomic.load())
    atomic -= 3
    println(atomic.load())
    atomic.update { it * 2 }
    println(atomic.load())
    println(atomic.updateAndFetch { it + 1 })
}
