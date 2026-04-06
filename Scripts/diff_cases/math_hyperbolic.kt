import kotlin.math.*

fun main() {
    println(acosh(1.0))   // 0.0
    println(asinh(0.0))   // 0.0
    println(atanh(0.0))   // 0.0
    println(acosh(2.0).let { it > 1.3 && it < 1.4 })  // true (≈1.317)
    println(asinh(1.0).let { it > 0.88 && it < 0.89 }) // true (≈0.881)
    println(atanh(0.5).let { it > 0.54 && it < 0.55 }) // true (≈0.549)
}
