// CANDIDATE-ONLY: kotlin.concurrent.AtomicLong is Kotlin/Native-only in Kotlin 2.3.10.

import kotlin.concurrent.AtomicLong

fun main() {
    val atomic = AtomicLong(7L)
    println(atomic.value)
    println(atomic.toString())
}
