// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

@file:OptIn(kotlin.ExperimentalStdlibApi::class)
@file:Suppress("INVISIBLE_MEMBER", "INVISIBLE_REFERENCE")

import kotlin.concurrent.AtomicLongArray

fun main() {
    val zeros = AtomicLongArray(2)
    val source = longArrayOf(4, 5)
    val copied = AtomicLongArray(source)
    source[0] = 99
    println(zeros.size)
    println(copied[0])
}
