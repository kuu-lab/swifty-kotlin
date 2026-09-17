// SKIP-DIFF (DEBT-DIFF-001): kotlin.native.* APIs are Kotlin/Native-only and are not available in JVM kotlinc.
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

fun main() {
    println(rootSetStatisticsProperties())
}
