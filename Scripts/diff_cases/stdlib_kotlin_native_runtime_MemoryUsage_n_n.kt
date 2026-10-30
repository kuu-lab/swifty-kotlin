// DIFF_CANDIDATE_ONLY_EXPECTED_OUTPUT: stdlib_kotlin_native_runtime_MemoryUsage_n_n.expected.stdout
import kotlin.native.runtime.MemoryUsage

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val value: MemoryUsage = MemoryUsage(42L)
    println(value is MemoryUsage)
}
