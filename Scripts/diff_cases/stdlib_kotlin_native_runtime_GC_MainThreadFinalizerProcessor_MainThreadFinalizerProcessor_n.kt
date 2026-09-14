// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class)

import kotlin.native.runtime.GC

fun main() {
    println(GC.MainThreadFinalizerProcessor.available)
    val originalBatchSize = GC.MainThreadFinalizerProcessor.batchSize
    GC.MainThreadFinalizerProcessor.batchSize = originalBatchSize + 1uL
    println(GC.MainThreadFinalizerProcessor.batchSize == originalBatchSize + 1uL)
    val maxTimeInTask = GC.MainThreadFinalizerProcessor.maxTimeInTask
    GC.MainThreadFinalizerProcessor.maxTimeInTask = maxTimeInTask
    println(GC.MainThreadFinalizerProcessor.maxTimeInTask == maxTimeInTask)
    val minTimeBetweenTasks = GC.MainThreadFinalizerProcessor.minTimeBetweenTasks
    GC.MainThreadFinalizerProcessor.minTimeBetweenTasks = minTimeBetweenTasks
    println(GC.MainThreadFinalizerProcessor.minTimeBetweenTasks == minTimeBetweenTasks)
}
