// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_Throwable_n.expected.stdout
// Candidate-only: Kotlin/Native APIs have no JVM oracle; assert only stable equality behavior, not stack details.
@file:OptIn(kotlin.experimental.ExperimentalNativeApi::class)

import kotlin.native.getStackTraceAddresses

fun main() {
    val throwable = Throwable()
    val first = throwable.getStackTraceAddresses()
    val second = throwable.getStackTraceAddresses()
    println(first == second)
}
