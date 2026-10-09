// DIFF_CANDIDATE_ONLY
@file:Suppress("DEPRECATION")

import kotlin.native.runtime.GC
import kotlin.native.runtime.GCInfo
import kotlin.time.Duration.Companion.seconds

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

    // Print each result separately so a short-circuiting expression cannot
    // hide a regression in a later getter. The three threshold properties
    // return zero. The target and minimum heap properties retain their fixed
    // defaults after their no-op setters. The maximum heap default also
    // depends on host physical memory, so check its guaranteed lower bound.
    println(GC.threshold)
    println(GC.collectCyclesThreshold)
    println(GC.thresholdAllocations)
    println(GC.autotune)
    println(GC.targetHeapBytes)
    println(GC.targetHeapUtilization)
    println(GC.minHeapBytes)
    println(GC.maxHeapBytes >= 100L * 1024 * 1024)
    println(GC.heapTriggerCoefficient)
    println(GC.pauseOnTargetHeapOverflow)
    println(detected == null)
    println(lastInfo == null)
    println(cycle == null)
}
