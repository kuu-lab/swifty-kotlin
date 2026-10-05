@file:OptIn(kotlin.concurrent.atomics.ExperimentalAtomicApi::class)

import kotlin.concurrent.atomics.AtomicBoolean

fun main() {
    val atomic = AtomicBoolean(true)
    println(atomic.load())
    atomic.store(false)
    println(atomic.exchange(true))
    println(atomic.compareAndExchange(true, false))
    println(atomic.toString())
}
