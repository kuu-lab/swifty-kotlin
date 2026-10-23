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
    // return zero: their setters are deliberate no-ops. The heap-size
    // properties keep the values assigned above — a persisted write is what
    // separates a live setter from the silent drop that motivated this case.
    println(GC.threshold)
    println(GC.collectCyclesThreshold)
    println(GC.thresholdAllocations)
    println(GC.autotune)
    println(GC.regularGCInterval)
    println(GC.targetHeapBytes)
    println(GC.targetHeapUtilization)
    println(GC.minHeapBytes)
    println(GC.maxHeapBytes)
    println(GC.heapTriggerCoefficient)
    println(GC.pauseOnTargetHeapOverflow)
    println(detected == null)
    // GC.collect() above records a completed pass, so lastGCInfo is non-null.
    println(lastInfo == null)
    println(cycle == null)

    // Compound assignment must route through the same accessors: `+=` on an
    // object property with custom get/set used to read and write a dead
    // flat-global slot, silently dropping the update.
    GC.minHeapBytes += 8L
    GC.maxHeapBytes += 16L
    GC.targetHeapBytes += 4L
    GC.regularGCInterval += 1.seconds
    GC.heapTriggerCoefficient += 0.05
    GC.threshold += 5
    GC.collectCyclesThreshold += 100L
    println(GC.minHeapBytes)
    println(GC.maxHeapBytes)
    println(GC.targetHeapBytes)
    println(GC.regularGCInterval)
    println(GC.heapTriggerCoefficient)
    println(GC.threshold)
    println(GC.collectCyclesThreshold)
}
