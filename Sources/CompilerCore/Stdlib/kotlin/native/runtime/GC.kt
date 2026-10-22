/*
 * Copyright 2010-2023 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-native <kotlin-native/runtime/src/main/kotlin/kotlin/native/runtime/GC.kt>.
 */

package kotlin.native.runtime

import kotlin.internal.KsSymbolName
import kotlin.time.Duration
import kotlin.time.Duration.Companion.microseconds
import kotlin.time.Duration.Companion.nanoseconds

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
        set(value) { __setTargetHeapBytes(value) }

    public var targetHeapUtilization: Double
        get() = __getTargetHeapUtilization()
        set(value) {
            require(value > 0 && value <= 1) { "targetHeapUtilization must be in (0, 1] interval: $value" }
            __setTargetHeapUtilization(value)
        }

    public var minHeapBytes: Long
        get() = __minHeapBytes
        set(value) { __minHeapBytes = value }

    public var maxHeapBytes: Long
        get() = __getMaxHeapBytes()
        set(value) { __setMaxHeapBytes(value) }

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

    /**
     * Returns statistics of the last finished garbage collection run.
     * This information is supposed to be used for testing and debugging purposes only.
     *
     * Can return null, if there was no garbage collection runs yet.
     */
    @ExperimentalStdlibApi
    public val lastGCInfo: GCInfo?
        get() = __lastGCInfo()

    @Deprecated("No-op in modern GC implementation")
    @Suppress("UNUSED_PARAMETER")
    public fun findCycle(root: Any): Array<Any>? = null

    // The runtime records one RuntimeGCInfoSnapshot per completed pass and
    // serializes it as a flat List<Long>; absent optional timestamps decode
    // from Long.MIN_VALUE. Index order is part of the ABI — keep it in sync
    // with RuntimeGCInfoSnapshot.serializedFieldValues in RuntimeGC.swift.
    private fun __lastGCInfo(): GCInfo? {
        val snapshot = __gcLastGCInfoSnapshot() ?: return null
        fun optionalNs(index: Int): Long? =
            snapshot[index].let { if (it == Long.MIN_VALUE) null else it }
        return GCInfo(
            epoch = snapshot[0],
            startTimeNs = snapshot[1],
            endTimeNs = snapshot[2],
            firstPauseRequestTimeNs = snapshot[3],
            firstPauseStartTimeNs = snapshot[4],
            firstPauseEndTimeNs = snapshot[5],
            secondPauseRequestTimeNs = optionalNs(6),
            secondPauseStartTimeNs = optionalNs(7),
            secondPauseEndTimeNs = optionalNs(8),
            postGcCleanupTimeNs = optionalNs(9),
            rootSet = RootSetStatistics(
                threadLocalReferences = snapshot[10],
                stackReferences = snapshot[11],
                globalReferences = snapshot[12],
                stableReferences = snapshot[13],
            ),
            markedCount = snapshot[14],
            // This collector manages a single heap pool; it is reported under
            // the same "heap" name as Kotlin/Native's default allocator pool.
            sweepStatistics = mapOf(
                "heap" to SweepStatistics(sweptCount = snapshot[15], keptCount = snapshot[16])
            ),
            memoryUsageBefore = mapOf(
                "heap" to MemoryUsage(totalObjectsSizeBytes = snapshot[17])
            ),
            memoryUsageAfter = mapOf(
                "heap" to MemoryUsage(totalObjectsSizeBytes = snapshot[18])
            ),
        )
    }

    @KsSymbolName("kk_gc_last_gc_info")
    private external fun __gcLastGCInfoSnapshot(): List<Long>?


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
    public object MainThreadFinalizerProcessor {
        public val available: Boolean
            get() = __available() != 0

        public var batchSize: ULong
            get() = __getBatchSize()
            set(value) { __setBatchSize(value) }

        public var maxTimeInTask: Duration
            get() = __getMaxTimeInTask().nanoseconds
            set(value) { __setMaxTimeInTask(value.inWholeNanoseconds) }

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
