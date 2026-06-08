package kotlin.math

import kswiftk.internal.*

fun Double.pow(x: Double): Double = __mathPow(this, x)

fun Float.pow(x: Float): Float = __mathPow(this, x)

fun Double.pow(n: Int): Double {
    var exponent = if (n < 0) -(n.toLong()) else n.toLong()
    var base = if (n < 0) 1.0 / this else this
    var result = 1.0
    while (exponent > 0L) {
        if (exponent % 2L != 0L) {
            result = result * base
        }
        base = base * base
        exponent = exponent / 2L
    }
    return result
}

fun Float.pow(n: Int): Float {
    var exponent = if (n < 0) -(n.toLong()) else n.toLong()
    var base = if (n < 0) 1.0f / this else this
    var result = 1.0f
    while (exponent > 0L) {
        if (exponent % 2L != 0L) {
            result = result * base
        }
        base = base * base
        exponent = exponent / 2L
    }
    return result
}

fun Double.roundToInt(): Int = __doubleRoundToInt(this)

fun Float.roundToInt(): Int = __floatRoundToInt(this)

fun Double.roundToLong(): Long = __doubleRoundToLong(this)

fun Float.roundToLong(): Long = __floatRoundToLong(this)
