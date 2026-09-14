// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.Debugging

fun main() {
    val runnable: Boolean = Debugging.isThreadStateRunnable
    Debugging.forceCheckedShutdown = !Debugging.forceCheckedShutdown
    val dumped: Boolean = Debugging.dumpMemory(2L)
    println(runnable || dumped || Debugging.forceCheckedShutdown)
}
