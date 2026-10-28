// DIFF_JVM
// Folded non-const initializers keep IEEE 754 equality; only const val uses kotlinc's boxed comparison.
val SIGNED_ZERO_EQ = 0.0 == -0.0
val SIGNED_ZERO_NE = 0.0 != -0.0
val FLOAT_SIGNED_ZERO_EQ = 0.0f == -0.0f
val NAN_EQ = (0.0 / 0.0) == (0.0 / 0.0)
val NAN_NE = (0.0 / 0.0) != (0.0 / 0.0)
const val CONST_SIGNED_ZERO_EQ = 0.0 == -0.0
const val CONST_NAN_EQ = Double.NaN == Double.NaN

fun main() {
    println(SIGNED_ZERO_EQ)
    println(SIGNED_ZERO_NE)
    println(FLOAT_SIGNED_ZERO_EQ)
    println(NAN_EQ)
    println(NAN_NE)
    println(CONST_SIGNED_ZERO_EQ)
    println(CONST_NAN_EQ)
}
