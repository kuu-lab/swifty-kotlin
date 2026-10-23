@file:kotlin.jvm.JvmName("MathKt")
package kotlin.math

import kotlin.jvm.internal.__jvmMathAbsDouble
import kotlin.jvm.internal.__jvmMathAbsFloat
import kotlin.jvm.internal.__jvmMathAbsInt
import kotlin.jvm.internal.__jvmMathAbsLong
import kotlin.jvm.internal.__jvmMathAcos
import kotlin.jvm.internal.__jvmMathAsin
import kotlin.jvm.internal.__jvmMathAtan
import kotlin.jvm.internal.__jvmMathAtan2
import kotlin.jvm.internal.__jvmMathCbrt
import kotlin.jvm.internal.__jvmMathCeil
import kotlin.jvm.internal.__jvmMathCopySignDouble
import kotlin.jvm.internal.__jvmMathCopySignFloat
import kotlin.jvm.internal.__jvmMathCos
import kotlin.jvm.internal.__jvmMathCosh
import kotlin.jvm.internal.__jvmMathExp
import kotlin.jvm.internal.__jvmMathExpm1
import kotlin.jvm.internal.__jvmMathFloor
import kotlin.jvm.internal.__jvmMathHypot
import kotlin.jvm.internal.__jvmMathIeeeRemainder
import kotlin.jvm.internal.__jvmMathLog
import kotlin.jvm.internal.__jvmMathLog10
import kotlin.jvm.internal.__jvmMathLog1p
import kotlin.jvm.internal.__jvmMaxDouble
import kotlin.jvm.internal.__jvmMaxFloat
import kotlin.jvm.internal.__jvmMinDouble
import kotlin.jvm.internal.__jvmMinFloat
import kotlin.jvm.internal.__jvmMathNextAfter
import kotlin.jvm.internal.__jvmMathNextAfterFloat
import kotlin.jvm.internal.__jvmMathNextDownDouble
import kotlin.jvm.internal.__jvmMathNextDownFloat
import kotlin.jvm.internal.__jvmMathNextUpDouble
import kotlin.jvm.internal.__jvmMathNextUpFloat
import kotlin.jvm.internal.__jvmPowDouble
import kotlin.jvm.internal.__jvmMathRoundLong
import kotlin.jvm.internal.__jvmMathRint
import kotlin.jvm.internal.__jvmMathSin
import kotlin.jvm.internal.__jvmMathSinh
import kotlin.jvm.internal.__jvmMathSqrt
import kotlin.jvm.internal.__jvmMathTanh
import kotlin.jvm.internal.__jvmMathUlpDouble
import kotlin.jvm.internal.__jvmMathUlpFloat
import kotlin.jvm.internal.__jvmMathTan

public const val PI: Double = 3.141592653589793
public const val E: Double = 2.718281828459045

public fun abs(n: Int): Int = __jvmMathAbsInt(n)
public fun abs(n: Long): Long = __jvmMathAbsLong(n)
public fun abs(x: Double): Double = __jvmMathAbsDouble(x)
public fun abs(x: Float): Float = __jvmMathAbsFloat(x)

public val Int.absoluteValue: Int get() = abs(this)
public val Long.absoluteValue: Long get() = abs(this)
public val Double.absoluteValue: Double get() = abs(this)
public val Float.absoluteValue: Float get() = abs(this)

public fun sign(x: Double): Double = if (x > 0.0) 1.0 else if (x < 0.0) -1.0 else x
public fun sign(x: Float): Float = if (x > 0.0f) 1.0f else if (x < 0.0f) -1.0f else x

public val Double.sign: Double get() = sign(this)
public val Float.sign: Float get() = sign(this)
public val Int.sign: Int get() = if (this > 0) 1 else if (this < 0) -1 else 0
public val Long.sign: Int get() = if (this > 0L) 1 else if (this < 0L) -1 else 0

public fun min(a: Int, b: Int): Int = if (a <= b) a else b
public fun max(a: Int, b: Int): Int = if (a >= b) a else b
public fun min(a: Long, b: Long): Long = if (a <= b) a else b
public fun max(a: Long, b: Long): Long = if (a >= b) a else b
public fun min(a: Double, b: Double): Double = __jvmMinDouble(a, b)
public fun max(a: Double, b: Double): Double = __jvmMaxDouble(a, b)
public fun min(a: Float, b: Float): Float = __jvmMinFloat(a, b)
public fun max(a: Float, b: Float): Float = __jvmMaxFloat(a, b)
public fun min(a: UInt, b: UInt): UInt = if (a <= b) a else b
public fun max(a: UInt, b: UInt): UInt = if (a >= b) a else b
public fun min(a: ULong, b: ULong): ULong = if (a <= b) a else b
public fun max(a: ULong, b: ULong): ULong = if (a >= b) a else b

public fun ceil(x: Double): Double = __jvmMathCeil(x)
public fun floor(x: Double): Double = __jvmMathFloor(x)
public fun round(x: Double): Double = __jvmMathRint(x)
public fun truncate(x: Double): Double = if (x < 0.0) __jvmMathCeil(x) else __jvmMathFloor(x)

public fun ceil(x: Float): Float = __jvmMathCeil(x.toDouble()).toFloat()
public fun floor(x: Float): Float = __jvmMathFloor(x.toDouble()).toFloat()
public fun round(x: Float): Float = __jvmMathRint(x.toDouble()).toFloat()
public fun truncate(x: Float): Float = if (x < 0.0f) __jvmMathCeil(x.toDouble()).toFloat() else __jvmMathFloor(x.toDouble()).toFloat()

public fun Double.withSign(sign: Double): Double = __jvmMathCopySignDouble(this, sign)
public fun Double.withSign(sign: Int): Double = __jvmMathCopySignDouble(this, if (sign < 0) -1.0 else 1.0)
public fun Float.withSign(sign: Float): Float = __jvmMathCopySignFloat(this, sign)
public fun Float.withSign(sign: Int): Float = __jvmMathCopySignFloat(this, if (sign < 0) -1.0f else 1.0f)

public fun sqrt(x: Double): Double = __jvmMathSqrt(x)
public fun sqrt(x: Float): Float = __jvmMathSqrt(x.toDouble()).toFloat()

public fun Double.pow(x: Double): Double = __jvmPowDouble(this, x)
public fun Double.pow(n: Int): Double = __jvmPowDouble(this, n.toDouble())
public fun Float.pow(x: Float): Float = __jvmPowDouble(this.toDouble(), x.toDouble()).toFloat()
public fun Float.pow(n: Int): Float = __jvmPowDouble(this.toDouble(), n.toDouble()).toFloat()

public fun Double.IEEErem(divisor: Double): Double = __jvmMathIeeeRemainder(this, divisor)
public fun Float.IEEErem(divisor: Float): Float = __jvmMathIeeeRemainder(this.toDouble(), divisor.toDouble()).toFloat()
public fun Double.nextTowards(to: Double): Double = __jvmMathNextAfter(this, to)
public fun Float.nextTowards(to: Float): Float = __jvmMathNextAfterFloat(this, to.toDouble())

public fun sin(x: Double): Double = __jvmMathSin(x)
public fun cos(x: Double): Double = __jvmMathCos(x)
public fun tan(x: Double): Double = __jvmMathTan(x)
public fun asin(x: Double): Double = __jvmMathAsin(x)
public fun acos(x: Double): Double = __jvmMathAcos(x)
public fun atan(x: Double): Double = __jvmMathAtan(x)
public fun atan2(y: Double, x: Double): Double = __jvmMathAtan2(y, x)
public fun sinh(x: Double): Double = __jvmMathSinh(x)
public fun cosh(x: Double): Double = __jvmMathCosh(x)
public fun tanh(x: Double): Double = __jvmMathTanh(x)
public fun hypot(x: Double, y: Double): Double = __jvmMathHypot(x, y)
public fun exp(x: Double): Double = __jvmMathExp(x)
public fun expm1(x: Double): Double = __jvmMathExpm1(x)
public fun ln(x: Double): Double = __jvmMathLog(x)
public fun ln1p(x: Double): Double = __jvmMathLog1p(x)
public fun log2(x: Double): Double = ln(x) / ln(2.0)
public fun log10(x: Double): Double = __jvmMathLog10(x)
public fun log(x: Double, base: Double): Double = ln(x) / ln(base)
public fun cbrt(x: Double): Double = __jvmMathCbrt(x)

public fun acosh(x: Double): Double =
    if (x < 1.0) Double.NaN
    else if (x > 1.0e154) ln(x) + ln(2.0)
    else ln(x + sqrt(x - 1.0) * sqrt(x + 1.0))

public fun asinh(x: Double): Double {
    if (x.isNaN() || x.isInfinite() || x == 0.0) return x
    val magnitude = abs(x)
    val result = if (magnitude > 1.0e154) {
        ln(magnitude) + ln(2.0)
    } else {
        ln1p(magnitude + magnitude * magnitude / (1.0 + sqrt(magnitude * magnitude + 1.0)))
    }
    return if (x < 0.0) -result else result
}

public fun atanh(x: Double): Double =
    if (x == 1.0) Double.POSITIVE_INFINITY
    else if (x == -1.0) Double.NEGATIVE_INFINITY
    else if (x > 1.0 || x < -1.0) Double.NaN
    else 0.5 * ln1p(2.0 * x / (1.0 - x))

public fun sin(x: Float): Float = __jvmMathSin(x.toDouble()).toFloat()
public fun cos(x: Float): Float = __jvmMathCos(x.toDouble()).toFloat()
public fun tan(x: Float): Float = __jvmMathTan(x.toDouble()).toFloat()
public fun asin(x: Float): Float = __jvmMathAsin(x.toDouble()).toFloat()
public fun acos(x: Float): Float = __jvmMathAcos(x.toDouble()).toFloat()
public fun atan(x: Float): Float = __jvmMathAtan(x.toDouble()).toFloat()
public fun atan2(y: Float, x: Float): Float = __jvmMathAtan2(y.toDouble(), x.toDouble()).toFloat()
public fun sinh(x: Float): Float = __jvmMathSinh(x.toDouble()).toFloat()
public fun cosh(x: Float): Float = __jvmMathCosh(x.toDouble()).toFloat()
public fun tanh(x: Float): Float = __jvmMathTanh(x.toDouble()).toFloat()
public fun hypot(x: Float, y: Float): Float = __jvmMathHypot(x.toDouble(), y.toDouble()).toFloat()
public fun exp(x: Float): Float = __jvmMathExp(x.toDouble()).toFloat()
public fun expm1(x: Float): Float = __jvmMathExpm1(x.toDouble()).toFloat()
public fun ln(x: Float): Float = __jvmMathLog(x.toDouble()).toFloat()
public fun ln1p(x: Float): Float = __jvmMathLog1p(x.toDouble()).toFloat()
public fun log2(x: Float): Float = ln(x) / ln(2.0f)
public fun log10(x: Float): Float = __jvmMathLog10(x.toDouble()).toFloat()
public fun log(x: Float, base: Float): Float = ln(x) / ln(base)
public fun cbrt(x: Float): Float = __jvmMathCbrt(x.toDouble()).toFloat()
public fun acosh(x: Float): Float = acosh(x.toDouble()).toFloat()
public fun asinh(x: Float): Float = asinh(x.toDouble()).toFloat()
public fun atanh(x: Float): Float = atanh(x.toDouble()).toFloat()

public fun Float.roundToInt(): Int = this.toDouble().roundToInt()
public fun Double.roundToInt(): Int {
    if (isNaN()) throw IllegalArgumentException("Cannot round NaN value.")
    val rounded = __jvmMathRoundLong(this)
    return if (rounded > 2147483647L) 2147483647
    else if (rounded < -2147483648L) -2147483648
    else rounded.toInt()
}

public fun Float.roundToLong(): Long = this.toDouble().roundToLong()
public fun Double.roundToLong(): Long {
    if (isNaN()) throw IllegalArgumentException("Cannot round NaN value.")
    return __jvmMathRoundLong(this)
}

public val Double.ulp: Double get() = __jvmMathUlpDouble(this)
public val Float.ulp: Float get() = __jvmMathUlpFloat(this)
public fun Double.nextUp(): Double = __jvmMathNextUpDouble(this)
public fun Float.nextUp(): Float = __jvmMathNextUpFloat(this)
public fun Double.nextDown(): Double = __jvmMathNextDownDouble(this)
public fun Float.nextDown(): Float = __jvmMathNextDownFloat(this)
