// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

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
