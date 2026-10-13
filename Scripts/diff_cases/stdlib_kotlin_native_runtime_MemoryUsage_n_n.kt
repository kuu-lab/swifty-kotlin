// CANDIDATE-ONLY
import kotlin.native.runtime.MemoryUsage

@OptIn(kotlin.native.runtime.NativeRuntimeApi::class)
fun main() {
    val value: MemoryUsage = MemoryUsage(42L)
    println(value is MemoryUsage)
}
