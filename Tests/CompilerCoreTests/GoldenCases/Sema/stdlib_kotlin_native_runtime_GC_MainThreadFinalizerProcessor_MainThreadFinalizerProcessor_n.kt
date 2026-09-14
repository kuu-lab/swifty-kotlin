package golden.sema

import kotlin.native.runtime.GC

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun mainThreadFinalizerProcessorProperties(): Boolean {
    val available: Boolean = GC.MainThreadFinalizerProcessor.available
    val batchSize: ULong = GC.MainThreadFinalizerProcessor.batchSize
    GC.MainThreadFinalizerProcessor.batchSize = batchSize + 1uL
    val maxTimeInTask = GC.MainThreadFinalizerProcessor.maxTimeInTask
    GC.MainThreadFinalizerProcessor.maxTimeInTask = maxTimeInTask
    val minTimeBetweenTasks = GC.MainThreadFinalizerProcessor.minTimeBetweenTasks
    GC.MainThreadFinalizerProcessor.minTimeBetweenTasks = minTimeBetweenTasks
    return available
}
