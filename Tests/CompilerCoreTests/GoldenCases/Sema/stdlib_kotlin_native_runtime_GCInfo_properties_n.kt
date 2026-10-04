package golden.sema

import kotlin.native.runtime.GCInfo
import kotlin.native.runtime.MemoryUsage
import kotlin.native.runtime.RootSetStatistics
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun gcInfoProperties(): Long {
    val info = GCInfo(
        epoch = 1L,
        startTimeNs = 2L,
        endTimeNs = 3L,
        firstPauseRequestTimeNs = 4L,
        firstPauseStartTimeNs = 5L,
        firstPauseEndTimeNs = 6L,
        secondPauseRequestTimeNs = null,
        secondPauseStartTimeNs = null,
        secondPauseEndTimeNs = null,
        postGcCleanupTimeNs = null,
        rootSet = RootSetStatistics(7L, 8L, 9L, 10L),
        markedCount = 11L,
        sweepStatistics = mapOf("mutator" to SweepStatistics(12L, 13L)),
        memoryUsageBefore = mapOf("heap" to MemoryUsage(14L)),
        memoryUsageAfter = mapOf("heap" to MemoryUsage(15L))
    )
    return info.epoch + info.startTimeNs + info.endTimeNs +
        info.firstPauseRequestTimeNs + info.firstPauseStartTimeNs + info.firstPauseEndTimeNs +
        (info.secondPauseRequestTimeNs ?: 0L) + (info.secondPauseStartTimeNs ?: 0L) +
        (info.secondPauseEndTimeNs ?: 0L) + (info.postGcCleanupTimeNs ?: 0L) +
        info.rootSet.threadLocalReferences +
        info.markedCount +
        (info.sweepStatistics["mutator"]?.sweptCount ?: 0L) +
        (info.memoryUsageBefore["heap"]?.totalObjectsSizeBytes ?: 0L) +
        (info.memoryUsageAfter["heap"]?.totalObjectsSizeBytes ?: 0L)
}
