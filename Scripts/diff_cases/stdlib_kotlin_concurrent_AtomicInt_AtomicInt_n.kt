// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

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
