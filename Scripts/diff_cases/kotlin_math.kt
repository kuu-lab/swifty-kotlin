// DIFF_JVM
import kotlin.math.abs
import kotlin.math.absoluteValue
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sqrt

fun main() {
    // min / max across Int, Long, Float, Double
    println(min(1, 2)); println(max(1, 2))
    println(min(1L, 2L)); println(max(1L, 2L))
    println(min(1.5f, 2.5f)); println(max(1.5f, 2.5f))
    println(min(1.5, 2.5)); println(max(1.5, 2.5))
    println(min(-0.0, 0.0)); println(max(-0.0, 0.0))
    // abs across Int, Long, Float, Double
    println(abs(-5)); println(abs(-5L)); println(abs(-3.5)); println(abs(-3.5f))
    println(abs(Int.MIN_VALUE)); println(abs(Double.NaN))
    // sqrt across Double and Float
    println(sqrt(16.0)); println(sqrt(2.0)); println(sqrt(16f)); println(sqrt(0.25f))
    // pow across Double/Float with Double/Int exponents
    println(10f.pow(3)); println(2f.pow(3))
    println(2.0.pow(3)); println(2.0.pow(3.0)); println(2.0.pow(0.5))
    println(4f.pow(0.5f)); println((-2.0).pow(2))
    // absoluteValue property across Float and Double
    println((-3.5f).absoluteValue); println((-3.5).absoluteValue)
    println((-3).absoluteValue); println((-3L).absoluteValue)
    println(0.0.absoluteValue); println((-0.0).absoluteValue)
}
