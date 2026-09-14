/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/GC.kt>.
 */

package kotlin.native.runtime

import kotlin.internal.KsSymbolName
import kotlin.time.Duration
import kotlin.time.nanoseconds

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

    // BUG-263: writing an object-member `var` whose owner was imported from a
    // precompiled .kklib (the normal, non-`--stdlib-from-source` path every
    // real user build takes) silently does nothing when the property's type
    // is `Long` -- the assignment lowers to the same `call set symbol=_`
    // shape as the (working) Boolean/Double properties below, but the actual
    // setter body never runs: neither the `require` guard nor the backing
    // write take effect, and there's no crash to signal it. Root cause is
    // still open (a symbol-resolution gap somewhere between Sema's member
    // assignment lowering and NativeEmitter's nil-symbol call resolution,
    // not the BUG-258 float/int widening this file's comparisons might
    // suggest). Until it's fixed, the setter is a documented no-op instead of
    // a validating write that silently fails to persist -- the getter still
    // reports the real (never-changing) default.
    public var targetHeapBytes: Long
        get() = __getTargetHeapBytes()
        set(value) {}

    public var targetHeapUtilization: Double
        get() = __getTargetHeapUtilization()
        set(value) {
            require(value > 0 && value <= 1) { "targetHeapUtilization must be in (0, 1] interval: $value" }
            __setTargetHeapUtilization(value)
        }

    // BUG-263 (see targetHeapBytes above): same silent-no-op write for a
    // plain Kotlin-stored Long backing field, not just the external-fun
    // bridged ones -- the defect is in `Long`-typed object-member writes in
    // general, not specific to the Swift bridge.
    public var minHeapBytes: Long
        get() = __minHeapBytes
        set(value) {}

    // BUG-263 (see targetHeapBytes above).
    public var maxHeapBytes: Long
        get() = __getMaxHeapBytes()
        set(value) {}

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
    @ExperimentalStdlibApi
    public val lastGCInfo: GCInfo? = null

    @Deprecated("No-op in modern GC implementation")
    @Suppress("UNUSED_PARAMETER")
    public fun findCycle(root: Any): Array<Any>? = null


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
    // KSP-1263: Keep MainThreadFinalizerProcessor's property surface
    // source-backed, following the same external-bridge pattern as
    // kotlin.native.Platform (public get()/set() wrapping a raw external fun).
    public object MainThreadFinalizerProcessor {
        /** Whether main-thread finalizer processing is supported on this target. */
        public val available: Boolean
            get() = __available() != 0

        /** Number of finalizers processed per main-thread batch. */
        public var batchSize: ULong
            get() = __getBatchSize()
            set(value) { __setBatchSize(value) }

        /** Upper bound on time spent finalizing per main-thread task. */
        public var maxTimeInTask: Duration
            get() = __getMaxTimeInTask().nanoseconds
            set(value) { __setMaxTimeInTask(value.inWholeNanoseconds) }

        /** Minimum delay between consecutive main-thread finalizer tasks. */
        public var minTimeBetweenTasks: Duration
            get() = __getMinTimeBetweenTasks().nanoseconds
            set(value) { __setMinTimeBetweenTasks(value.inWholeNanoseconds) }

        @KsSymbolName("kk_gc_main_thread_finalizer_processor_available")
        private external fun __available(): Int

        @KsSymbolName("kk_gc_main_thread_finalizer_processor_batch_size_load")
        private external fun __getBatchSize(): ULong

        @KsSymbolName("kk_gc_main_thread_finalizer_processor_batch_size_store")
        private external fun __setBatchSize(value: ULong): Unit

        @KsSymbolName("kk_gc_main_thread_finalizer_processor_max_time_in_task_load")
        private external fun __getMaxTimeInTask(): Long

        @KsSymbolName("kk_gc_main_thread_finalizer_processor_max_time_in_task_store")
        private external fun __setMaxTimeInTask(value: Long): Unit

        @KsSymbolName("kk_gc_main_thread_finalizer_processor_min_time_between_tasks_load")
        private external fun __getMinTimeBetweenTasks(): Long

        @KsSymbolName("kk_gc_main_thread_finalizer_processor_min_time_between_tasks_store")
        private external fun __setMinTimeBetweenTasks(value: Long): Unit
    }
}
