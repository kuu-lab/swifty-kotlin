// DIFF-CANDIDATE-ONLY: Kotlin/Native AtomicIntArray has no JVM kotlinc reference.
@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.concurrent.AtomicIntArray

fun main() {
    val values = AtomicIntArray(2)
    println(values.compareAndExchange(0, 0, 10))
    println(values.compareAndSet(0, 10, 20))
    println(values.length)
    println(values.toString())
}
