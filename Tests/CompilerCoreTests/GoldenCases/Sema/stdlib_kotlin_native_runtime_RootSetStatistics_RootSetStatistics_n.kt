package golden.sema

import kotlin.native.runtime.RootSetStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun rootSetStatisticsProperties(): Long {
    val statistics = RootSetStatistics(
        threadLocalReferences = 1L,
        stackReferences = 2L,
        globalReferences = 3L,
        stableReferences = 4L,
    )
    return statistics.threadLocalReferences +
        statistics.stackReferences +
        statistics.globalReferences +
        statistics.stableReferences
}
