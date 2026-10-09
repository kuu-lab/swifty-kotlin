// CANDIDATE-ONLY: kotlin.native.runtime is unavailable in JVM kotlinc; compare against the adjacent expected stdout.
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun sweepStatisticsSurface(): Long {
    val statistics = SweepStatistics(-9223372036854775807L - 1L, 9223372036854775807L)
    return statistics.sweptCount + statistics.keptCount
}

fun main() {
    println(sweepStatisticsSurface())
}
