// The adjacent .expected file selects diff_kotlinc.sh's candidate-only runner.
import kotlin.native.runtime.SweepStatistics

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val minimum = SweepStatistics(-9223372036854775807L - 1L, 9223372036854775807L)
    println(minimum.sweptCount)
    println(minimum.keptCount)
}
