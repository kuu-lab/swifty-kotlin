/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/GC.kt>.
 */

package kotlin.native.runtime

import kotlin.internal.KsSymbolName
import kotlin.time.*

@NativeRuntimeApi
@SinceKotlin("1.9")
public object GC {
    @KsSymbolName("kk_gc_collect")
    public external fun collect()

    @KsSymbolName("kk_gc_schedule")
    public external fun schedule()

    // This runtime has no legacy memory manager / background GC thread, so the
    // control-flow API below is a permanent no-op, matching upstream Kotlin/Native
    // 2.x (which removed the legacy MM these functions used to operate).
    @Deprecated("No-op in modern GC implementation")
    public fun collectCyclic() {}

    @Deprecated("No-op in modern GC implementation")
    public fun suspend() {}

    @Deprecated("No-op in modern GC implementation")
    public fun resume() {}

    @Deprecated("No-op in modern GC implementation")
    public fun stop() {}

    @Deprecated("No-op in modern GC implementation")
    public fun start() {}

    @Deprecated("No-op in modern GC implementation")
    public var threshold: Int
        get() = 0
        set(value) {}

    @Deprecated("No-op in modern GC implementation")
    public var collectCyclesThreshold: Long
        get() = 0L
        set(value) {}

    @Deprecated("No-op in modern GC implementation")
    public var thresholdAllocations: Long
        get() = 0L
        set(value) {}

    public var autotune: Boolean
        get() = __autotune
        set(value) {
            __autotune = value
        }

    @Deprecated("No-op in modern GC implementation")
    public var cyclicCollectorEnabled: Boolean
        get() = false
        set(value) {}

    public var regularGCInterval: Duration
        get() = __regularGCInterval
        set(value) {
            require(!value.isNegative()) { "regularGCInterval must not be negative: $value" }
            __regularGCInterval = value
        }

    public var targetHeapBytes: Long
        get() = __getTargetHeapBytes()
        set(value) {
            require(value >= 0) { "targetHeapBytes must not be negative: $value" }
            __setTargetHeapBytes(value)
        }

    public var targetHeapUtilization: Double
        get() = __getTargetHeapUtilization()
        set(value) {
            require(value > 0 && value <= 1) { "targetHeapUtilization must be in (0, 1] interval: $value" }
            __setTargetHeapUtilization(value)
        }

    public var minHeapBytes: Long
        get() = __minHeapBytes
        set(value) {
            require(value >= 0) { "minHeapBytes must not be negative: $value" }
            __minHeapBytes = value
        }

    public var maxHeapBytes: Long
        get() = __getMaxHeapBytes()
        set(value) {
            require(value >= 0) { "maxHeapBytes must not be negative: $value" }
            __setMaxHeapBytes(value)
        }

    public var heapTriggerCoefficient: Double
        get() = __heapTriggerCoefficient
        set(value) {
            require(value > 0 && value <= 1) { "heapTriggerCoefficient must be in (0, 1] interval: $value" }
            __heapTriggerCoefficient = value
        }

    public var pauseOnTargetHeapOverflow: Boolean
        get() = __pauseOnTargetHeapOverflow
        set(value) {
            __pauseOnTargetHeapOverflow = value
        }

    @Deprecated("No-op in modern GC implementation")
    public fun detectCycles(): Array<Any>? = null

    // KSP-1262: lastGCInfo has no last-run data to report until a real GC-pass
    // recorder lands (tracked by GCInfo's own property-surface migration).
    // A plain stored `= null` (not `get() = null`) is intentional: a
    // getter-only object member with no backing field crashes at runtime
    // (BUG-257, root-caused but not yet fixed — see kswiftc's
    // tryLowerObjectMemberPropertyRead, which unconditionally lowers every
    // object member property read as a global-slot load even when the
    // property has no such slot).
    @ExperimentalStdlibApi
    public val lastGCInfo: GCInfo? = null

    @Deprecated("No-op in modern GC implementation")
    @Suppress("UNUSED_PARAMETER")
    public fun findCycle(root: Any): Array<Any>? = null

    public object MainThreadFinalizerProcessor {}

    private var __autotune: Boolean = true
    private var __regularGCInterval: Duration = 10_000_000L.microseconds
    private var __minHeapBytes: Long = 5L * 1024 * 1024
    private var __heapTriggerCoefficient: Double = 0.9
    private var __pauseOnTargetHeapOverflow: Boolean = true

    @KsSymbolName("kk_gc_target_heap_bytes")
    private external fun __getTargetHeapBytes(): Long

    @KsSymbolName("kk_gc_target_heap_bytes_set")
    private external fun __setTargetHeapBytes(value: Long)

    @KsSymbolName("kk_gc_target_heap_utilization")
    private external fun __getTargetHeapUtilization(): Double

    @KsSymbolName("kk_gc_target_heap_utilization_set")
    private external fun __setTargetHeapUtilization(value: Double)

    @KsSymbolName("kk_gc_max_heap_bytes")
    private external fun __getMaxHeapBytes(): Long

    @KsSymbolName("kk_gc_max_heap_bytes_set")
    private external fun __setMaxHeapBytes(value: Long)
}
