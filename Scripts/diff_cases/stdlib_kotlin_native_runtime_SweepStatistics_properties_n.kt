// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_runtime_SweepStatistics_properties_n.expected
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val minimum = SweepStatistics(-9223372036854775807L - 1L, 9223372036854775807L)
    println(minimum.sweptCount)
    println(minimum.keptCount)
}
