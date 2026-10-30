// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_runtime_SweepStatistics_n_n.expected.stdout
// Candidate-only: kotlin.native.runtime APIs are unavailable in JVM kotlinc; run against the bundled stdlib.
import kotlin.native.runtime.NativeRuntimeApi
import kotlin.native.runtime.SweepStatistics

@OptIn(NativeRuntimeApi::class)
fun main() {
    SweepStatistics(1L, 2L)
    println("sweep_statistics_ok=true")
}
