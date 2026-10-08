// CANDIDATE-ONLY: kotlin.concurrent.AtomicIntArray is Kotlin/Native-only and has no JVM kotlinc oracle.

@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlin.concurrent.AtomicIntArray

fun main() {
    val zeros = AtomicIntArray(2)
    val source = intArrayOf(4, 5)
    val copied = AtomicIntArray(source)
    source[0] = 99
    println(zeros.size)
    println(copied[0])
}
