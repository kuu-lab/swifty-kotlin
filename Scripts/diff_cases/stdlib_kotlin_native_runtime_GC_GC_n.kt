// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
@file:Suppress("DEPRECATION")

import kotlin.native.runtime.GC
import kotlin.native.runtime.GCInfo
import kotlin.time.seconds

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class, ExperimentalStdlibApi::class)
fun main() {
    GC.collect()
    GC.schedule()
    GC.collectCyclic()
    GC.suspend()
    GC.resume()
    GC.stop()
    GC.start()

    GC.threshold = 100
    GC.collectCyclesThreshold = 200L
    GC.thresholdAllocations = 300L
    GC.autotune = true
    GC.cyclicCollectorEnabled = false
    GC.regularGCInterval = 5.seconds
    GC.targetHeapBytes = 1024L
    GC.targetHeapUtilization = 0.5
    GC.minHeapBytes = 512L
    GC.maxHeapBytes = 2048L
    GC.heapTriggerCoefficient = 0.9
    GC.pauseOnTargetHeapOverflow = true

    val detected: Array<Any>? = GC.detectCycles()
    val lastInfo: GCInfo? = GC.lastGCInfo
    val cycle: Array<Any>? = GC.findCycle(Any())

    println(
        GC.threshold > 0 &&
            GC.collectCyclesThreshold > 0 &&
            GC.thresholdAllocations > 0 &&
            GC.autotune &&
            GC.targetHeapBytes > 0 &&
            GC.targetHeapUtilization > 0 &&
            GC.maxHeapBytes > 0 &&
            GC.heapTriggerCoefficient > 0 &&
            GC.pauseOnTargetHeapOverflow &&
            detected == null &&
            lastInfo == null &&
            cycle == null
    )
}
