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

    // Printed individually (not folded into one `&&` chain) so every getter
    // above actually runs -- a short-circuiting `&&` would stop at the first
    // false operand and silently skip the rest, hiding a regression in any
    // later property. threshold/collectCyclesThreshold/thresholdAllocations
    // and (pending BUG-263) targetHeapBytes/minHeapBytes/maxHeapBytes are
    // documented no-ops, so their lines are expected to print the type's
    // zero value, not the value assigned above.
    println(GC.threshold)
    println(GC.collectCyclesThreshold)
    println(GC.thresholdAllocations)
    println(GC.autotune)
    println(GC.targetHeapBytes)
    println(GC.targetHeapUtilization)
    println(GC.minHeapBytes)
    println(GC.maxHeapBytes)
    println(GC.heapTriggerCoefficient)
    println(GC.pauseOnTargetHeapOverflow)
    println(detected == null)
    println(lastInfo == null)
    println(cycle == null)
}
