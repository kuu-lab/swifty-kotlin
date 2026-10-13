// CANDIDATE-ONLY: kotlin.native.runtime.Debugging has no JVM kotlinc reference; compare stdout with the adjacent sidecar.
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.Debugging

fun main() {
    val runnable: Boolean = Debugging.isThreadStateRunnable
    Debugging.forceCheckedShutdown = !Debugging.forceCheckedShutdown
    val dumped: Boolean = Debugging.dumpMemory(2L)
    println(runnable || dumped || Debugging.forceCheckedShutdown)
}
