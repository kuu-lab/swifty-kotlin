// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_runtime_Debugging_Debugging_n.expected.stdout
// Candidate-only: kotlin.native.runtime.Debugging has no JVM kotlinc reference; compare stdout with the adjacent sidecar.
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.Debugging

fun main() {
    val runnable: Boolean = Debugging.isThreadStateRunnable
    Debugging.forceCheckedShutdown = !Debugging.forceCheckedShutdown
    val dumped: Boolean = Debugging.dumpMemory(2L)
    println(runnable || dumped || Debugging.forceCheckedShutdown)
}
