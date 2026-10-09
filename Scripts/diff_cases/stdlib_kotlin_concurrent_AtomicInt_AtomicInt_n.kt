// DIFF_CANDIDATE_ONLY: kotlin.concurrent atomics are Kotlin/Native-only and have no JVM kotlinc reference.

import kotlin.concurrent.AtomicInt

fun main() {
    val atomic = AtomicInt(10)
    println(atomic.compareAndExchange(10, 20))
    println(atomic.getAndAdd(5))
    println(atomic.getAndIncrement())
    println(atomic.getAndDecrement())
    println(atomic.value)
    atomic.value = 42
    println(atomic.value)
    println(atomic.toString())
}
