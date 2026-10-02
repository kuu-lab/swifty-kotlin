// SKIP-DIFF (DEBT-DIFF-001): kotlin.concurrent atomic APIs are Kotlin/Native-only
// in Kotlin 2.3.10 and are unavailable in the JVM kotlinc reference environment.

import kotlin.concurrent.AtomicReference

fun main() {
    val atomic = AtomicReference("initial")
    println(atomic.value)
    println(atomic.toString())
}
