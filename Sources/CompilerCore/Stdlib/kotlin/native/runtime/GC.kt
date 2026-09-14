/*
 * KSP-1261: Source-backed nominal declaration for Kotlin/Native GC.
 *
 * The remaining GC members are intentionally retained by the synthetic
 * runtime surface until their owning migration tasks are completed.
 */

package kotlin.native.runtime

import kotlin.internal.KsSymbolName
import kotlin.time.Duration
import kotlin.time.nanoseconds

@NativeRuntimeApi
@SinceKotlin("1.9")
public object GC {
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
