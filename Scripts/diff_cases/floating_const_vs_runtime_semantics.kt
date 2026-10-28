// kotlinc compares floating-point values with two different rules:
// `const val` initializers use equals/compareTo (NaN == NaN, -0.0 < 0.0,
// NaN orders above everything), every other expression uses IEEE 754.
// Also covers `mod` with an infinite divisor, const Double/Float conversions,
// and unsigned arithmetic inside a folded String concatenation.
const val INF = 1.0 / 0.0
const val NAN_LT = 0.0 < Double.NaN
const val NAN_GE = Double.NaN >= 1.0
const val NEG_ZERO_LT = -0.0 < 0.0
const val NEG_ZERO_GE = -0.0 >= 0.0
const val NEG_ZERO_EQ = -0.0 == 0.0
const val NAN_EQ = Double.NaN == Double.NaN
const val FLOAT_NAN_GT = Float.NaN > Float.POSITIVE_INFINITY
const val MIXED_NAN_LT = 1 < Double.NaN
const val CONCAT_EQ = "c " + (-0.0 == 0.0)
const val CONCAT_LT = "d " + (0.0 < Double.NaN)
const val MOD_POS_INF = (-1.0).mod(INF)
const val MOD_NEG_INF = 1.0.mod(-INF)
const val FLOAT_MOD_INF = (-1.0f).mod(1.0f / 0.0f)
const val TO_INT = 3.9.toInt()
const val NEG_TO_INT = (-3.9).toInt()
const val NAN_TO_INT = Double.NaN.toInt()
const val BIG_TO_INT = 1.0E300.toInt()
const val SMALL_TO_LONG = (-1.0E300).toLong()
const val FLOAT_TO_LONG = (-2.5f).toLong()
const val TO_FLOAT = 1.1.toFloat()
const val TO_DOUBLE = 0.1f.toDouble()

val TOP = -0.0 == 0.0
val TOP_NAN = 0.0 / 0.0 == 0.0 / 0.0
val TOP_LT = 0.0 < 0.0 / 0.0

class Holder {
    val negZero = -0.0 == 0.0
    val nanNe = 0.0 / 0.0 != 0.0 / 0.0
}

object Singleton {
    val floatNegZero = -0.0f == 0.0f
}

val GETTER: Boolean get() = -0.0 == 0.0

fun runtimeMod(a: Double, b: Double) = a.mod(b)

fun main() {
    println(NAN_LT)
    println(NAN_GE)
    println(NEG_ZERO_LT)
    println(NEG_ZERO_GE)
    println(NEG_ZERO_EQ)
    println(NAN_EQ)
    println(FLOAT_NAN_GT)
    println(MIXED_NAN_LT)
    println(CONCAT_EQ)
    println(CONCAT_LT)
    println(MOD_POS_INF)
    println(MOD_NEG_INF)
    println(FLOAT_MOD_INF)
    println(TO_INT)
    println(NEG_TO_INT)
    println(NAN_TO_INT)
    println(BIG_TO_INT)
    println(SMALL_TO_LONG)
    println(FLOAT_TO_LONG)
    println(TO_FLOAT)
    println(TO_DOUBLE)

    println(TOP)
    println(TOP_NAN)
    println(TOP_LT)
    println(Holder().negZero)
    println(Holder().nanNe)
    println(Singleton.floatNegZero)
    println(GETTER)
    println("a " + (0.0 / 0.0 == 0.0 / 0.0))
    println("b " + (0.0 / 0.0 != 0.0 / 0.0))
    println("p " + (-0.0 == 0.0))
    println("q " + (0.0 < 0.0 / 0.0))
    println("t ${-0.0 == 0.0}")
    println("u ${0.0f / 0.0f == 0.0f / 0.0f}")
    println(runtimeMod(-1.0, Double.POSITIVE_INFINITY))
    println((-1.0).mod(Double.POSITIVE_INFINITY))

    println("v " + (1u + 2u))
    println("w " + (1uL + 2uL) + " " + (7u - 2u) + " " + (3u * 4u))
    println("x " + (UInt.MAX_VALUE + 1u))
    println("y ${1u + 2u}")
}
