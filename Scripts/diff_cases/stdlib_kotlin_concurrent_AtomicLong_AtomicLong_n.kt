// DIFF_CANDIDATE_ONLY: kotlin.concurrent.AtomicLong is Kotlin/Native-only in Kotlin 2.3.10 and has no JVM kotlinc reference.

import kotlin.concurrent.AtomicLong

fun main() {
    val atomic = AtomicLong(10L)
    println(atomic.compareAndExchange(10L, 20L))
    println(atomic.getAndAdd(5L))
    println(atomic.getAndIncrement())
    println(atomic.getAndDecrement())
    println(atomic.value)
    atomic.value = 42L
    println(atomic.value)
    println(atomic.toString())
}
