// DIFF_JVM
// const val floating comparisons follow kotlinc's compareTo order; non-const vals keep IEEE 754.
const val NEGATIVE_ZERO_LT = -0.0 < 0.0
const val ZERO_LE_NEGATIVE_ZERO = 0.0 <= -0.0
const val NAN_GT = Double.NaN > 1.0
const val NAN_LT = Double.NaN < 1.0
const val NAN_GE_NAN = Double.NaN >= Double.NaN
const val FLOAT_NEGATIVE_ZERO_LT = -0.0f < 0.0f
val RUNTIME_NEGATIVE_ZERO_LT = -0.0 < 0.0
val RUNTIME_NAN_GT = (0.0 / 0.0) > 1.0

fun main() {
    println(NEGATIVE_ZERO_LT)
    println(ZERO_LE_NEGATIVE_ZERO)
    println(NAN_GT)
    println(NAN_LT)
    println(NAN_GE_NAN)
    println(FLOAT_NEGATIVE_ZERO_LT)
    println(RUNTIME_NEGATIVE_ZERO_LT)
    println(RUNTIME_NAN_GT)
    println(-0.0 < 0.0)
}
