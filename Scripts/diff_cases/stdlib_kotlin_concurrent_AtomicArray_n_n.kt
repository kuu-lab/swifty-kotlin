// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlin.concurrent.AtomicArray

fun main() {
    val initialized = AtomicArray(2) { index -> index.toString() }
    val source = arrayOf("alpha", "beta")
    val copied = AtomicArray(source)
    source[0] = "x"
    println(initialized)
    println(copied)
}
