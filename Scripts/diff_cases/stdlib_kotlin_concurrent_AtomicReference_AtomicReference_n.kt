// DIFF_CANDIDATE_ONLY: kotlin.concurrent.AtomicReference is Kotlin/Native-only and has no JVM kotlinc reference.

import kotlin.concurrent.AtomicReference

fun main() {
    val atomic = AtomicReference("initial")
    println(atomic.compareAndExchange("initial", "next"))
    println(atomic.getAndSet("replaced"))
    println(atomic.value)
    atomic.value = "assigned"
    println(atomic.value)
    println(atomic.toString())
}
