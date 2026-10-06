// KUU-1334: primitive operations and const references remain compile-time constants.
const val A = 1 + 2
const val B = "x" + "y"
const val C = A * 10
const val D = 1 shl 4
const val E = 'a' + 1
const val F = A == 3
const val PREVIOUS = E - 1
const val DISTANCE = 'z' - 'a'
const val WRAPPED = '\uFFFF' + 1
const val UNDERFLOW = '\u0000' - 1
const val EQ = E == 'b'
const val NE = A != 4
const val LT = 'a' < E
const val LE = A <= 3
const val GT = 9007199254740993L > 9007199254740992L
const val GE = D >= C
const val FLAGS = (F && LT) || GE
const val BOOL_EQ = FLAGS == true
const val TEXT_EQ = B == "xy"
const val FLOAT_LT = 1.5f < 2.0f
const val DOUBLE_GE = 2.0 >= 1.5
const val FLOAT_ROUNDED = 16777217f == 16777216f
const val MIXED_LT = A < 3.5
const val MIXED_ROUNDED = 16777217 > 16777216f
const val NAN_EQ = Double.NaN == Double.NaN
const val NAN_NE = Double.NaN != Double.NaN
const val NAN_LE = Double.NaN <= 0.0
const val SIGNED_ZERO = -0.0 == 0.0
const val INVERTED = D.inv()
const val LONG_INVERTED = 0L.inv()

fun main() {
    println(A)
    println(B)
    println(C)
    println(D)
    println(E)
    println(F)
    println(PREVIOUS)
    println(DISTANCE)
    println(WRAPPED.code)
    println(UNDERFLOW.code)
    println(EQ)
    println(NE)
    println(LT)
    println(LE)
    println(GT)
    println(GE)
    println(FLAGS)
    println(BOOL_EQ)
    println(TEXT_EQ)
    println(FLOAT_LT)
    println(DOUBLE_GE)
    println(FLOAT_ROUNDED)
    println(MIXED_LT)
    println(MIXED_ROUNDED)
    println(NAN_EQ)
    println(NAN_NE)
    println(NAN_LE)
    println(SIGNED_ZERO)
    println(INVERTED)
    println(LONG_INVERTED)
}
