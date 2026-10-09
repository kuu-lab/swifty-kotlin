// CANDIDATE-ONLY: Kotlin/Native APIs have no JVM oracle; assert only stable equality behavior, not stack details.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.getStackTraceAddresses

fun main() {
    val throwable = Throwable()
    val first = throwable.getStackTraceAddresses()
    val second = throwable.getStackTraceAddresses()
    println(first == second)
}
