// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.ExperimentalStdlibApi::class)

import kotlin.concurrent.AtomicArray

fun main() {
    val values = AtomicArray(2) { "v$it" }
    println(values.length)
    println(values[0])
    values[0] = "updated"
    println(values.getAndSet(0, "exchanged"))
    println(values.compareAndSet(0, "exchanged", "cas"))
    println(values.compareAndExchange(0, "cas", "changed"))
    println(values.toString())
}
