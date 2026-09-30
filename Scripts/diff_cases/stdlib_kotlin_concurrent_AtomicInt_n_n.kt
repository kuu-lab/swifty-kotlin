// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

import kotlin.concurrent.AtomicInt

fun main() {
    val atomic = AtomicInt(7)
    println(atomic.value)
    println(atomic.toString())
}
