@file:OptIn(kotlin.native.runtime.NativeRuntimeApi::class, ExperimentalStdlibApi::class)
@file:Suppress("DEPRECATION")

import kotlin.native.runtime.GC
import kotlin.native.runtime.GCInfo
import kotlin.time.seconds

fun gcContract(): Boolean {
    GC.collect()
    GC.schedule()
    GC.collectCyclic()
    GC.suspend()
    GC.resume()
    GC.stop()
    GC.start()

    GC.threshold = 100
    val threshold: Int = GC.threshold

    GC.collectCyclesThreshold = 200L
    val collectCyclesThreshold: Long = GC.collectCyclesThreshold

    GC.thresholdAllocations = 300L
    val thresholdAllocations: Long = GC.thresholdAllocations

    GC.autotune = true
    val autotune: Boolean = GC.autotune

    GC.cyclicCollectorEnabled = false
    val cyclicCollectorEnabled: Boolean = GC.cyclicCollectorEnabled

    GC.regularGCInterval = 5.seconds
    val regularGCInterval = GC.regularGCInterval

    GC.targetHeapBytes = 1024L
    val targetHeapBytes: Long = GC.targetHeapBytes

    GC.targetHeapUtilization = 0.5
    val targetHeapUtilization: Double = GC.targetHeapUtilization

    GC.minHeapBytes = 512L
    val minHeapBytes: Long = GC.minHeapBytes

    GC.maxHeapBytes = 2048L
    val maxHeapBytes: Long = GC.maxHeapBytes

    GC.heapTriggerCoefficient = 0.9
    val heapTriggerCoefficient: Double = GC.heapTriggerCoefficient

    GC.pauseOnTargetHeapOverflow = true
    val pauseOnTargetHeapOverflow: Boolean = GC.pauseOnTargetHeapOverflow

    val detected: Array<Any>? = GC.detectCycles()
    val lastInfo: GCInfo? = GC.lastGCInfo
    val cycle: Array<Any>? = GC.findCycle(Any())

    return threshold > 0 &&
        collectCyclesThreshold > 0 &&
        thresholdAllocations > 0 &&
        autotune &&
        cyclicCollectorEnabled == cyclicCollectorEnabled &&
        regularGCInterval == regularGCInterval &&
        targetHeapBytes > 0 &&
        targetHeapUtilization > 0 &&
        minHeapBytes >= 0 &&
        maxHeapBytes > 0 &&
        heapTriggerCoefficient > 0 &&
        pauseOnTargetHeapOverflow &&
        detected == null &&
        lastInfo == null &&
        cycle == null
}
