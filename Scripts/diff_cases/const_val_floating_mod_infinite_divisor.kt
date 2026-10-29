// DIFF_JVM
// Floating-point `mod` folds with an infinite divisor take the sign-correction branch like the runtime.
const val DOUBLE_NEGATIVE = (-1.0).mod(Double.POSITIVE_INFINITY)
const val DOUBLE_POSITIVE = 1.0.mod(Double.NEGATIVE_INFINITY)
const val DOUBLE_SAME_SIGN = 1.0.mod(Double.POSITIVE_INFINITY)
const val FLOAT_NEGATIVE = (-1.0f).mod(Float.POSITIVE_INFINITY)

fun main() {
    println(DOUBLE_NEGATIVE)
    println(DOUBLE_POSITIVE)
    println(DOUBLE_SAME_SIGN)
    println(FLOAT_NEGATIVE)
    val inf = Double.POSITIVE_INFINITY
    println((-1.0).mod(inf))
}
