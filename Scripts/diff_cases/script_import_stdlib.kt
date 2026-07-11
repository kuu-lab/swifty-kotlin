import kotlin.math.*
import kotlin.collections.*
import kotlin.random.Random

val numbers = listOf(1, 2, 3, 4, 5)
val max = max(numbers[0], numbers[4])
val sqrtValue = sqrt(16.0)
val absValue = abs(-5)
// Random's PRNG differs from JVM kotlinc's, so sort to keep the diff
// deterministic (same idiom as sequence_shuffled.kt).
val shuffled = numbers.shuffled(Random(42)).sorted()

println("max: $max, sqrt: $sqrtValue, abs: $absValue")
println("shuffled: $shuffled")
