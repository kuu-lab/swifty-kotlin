// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
import kotlin.native.runtime.GCInfo
import kotlin.native.runtime.MemoryUsage
import kotlin.native.runtime.RootSetStatistics
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
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
    println(info.epoch)
    println(info.startTimeNs)
    println(info.endTimeNs)
    println(info.firstPauseRequestTimeNs)
    println(info.firstPauseStartTimeNs)
    println(info.firstPauseEndTimeNs)
    println(info.secondPauseRequestTimeNs)
    println(info.secondPauseStartTimeNs)
    println(info.secondPauseEndTimeNs)
    println(info.postGcCleanupTimeNs)
    println(info.rootSet.threadLocalReferences)
    println(info.markedCount)
    println(info.sweepStatistics["mutator"]?.sweptCount)
    println(info.memoryUsageBefore["heap"]?.totalObjectsSizeBytes)
    println(info.memoryUsageAfter["heap"]?.totalObjectsSizeBytes)
}
