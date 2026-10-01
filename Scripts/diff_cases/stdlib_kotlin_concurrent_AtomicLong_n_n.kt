// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

import kotlin.concurrent.AtomicLong

fun main() {
    val atomic = AtomicLong(7L)
    println(atomic.value)
    println(atomic.toString())
}
