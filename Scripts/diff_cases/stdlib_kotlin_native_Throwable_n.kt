// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Native-only and unavailable to the JVM kotlinc reference environment.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.getStackTraceAddresses

fun main() {
    val throwable = Throwable()
    val first = throwable.getStackTraceAddresses()
    val second = throwable.getStackTraceAddresses()
    println(first == second)
}
