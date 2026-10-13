// DIFF_CANDIDATE_ONLY: kotlin.native.runtime APIs have no JVM reference; compare the constructed value's runtime type.
import kotlin.native.runtime.GCInfo
import kotlin.native.runtime.MemoryUsage
import kotlin.native.runtime.RootSetStatistics
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val value: GCInfo = GCInfo(
        1L,
        2L,
        3L,
        4L,
        5L,
        6L,
        null,
        null,
        null,
        null,
        RootSetStatistics(7L, 8L, 9L, 10L),
        7L,
        mapOf("mutator" to SweepStatistics(12L, 13L)),
        mapOf("heap" to MemoryUsage(14L)),
        mapOf("heap" to MemoryUsage(15L)),
    )
    println(value is GCInfo)
}
