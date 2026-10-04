// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.concurrent.AtomicIntArray

fun main() {
    val values = AtomicIntArray(2)
    println(values.compareAndExchange(0, 0, 10))
    println(values.compareAndSet(0, 10, 20))
    println(values.length)
    println(values.toString())
}
