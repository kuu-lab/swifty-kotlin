package kotlin.math

import kswiftk.internal.*

fun abs(x: Int): Int = if (x < 0) -x else x

fun abs(n: Long): Long = if (n < 0L) -n else n

fun abs(x: Double): Double = if (x < 0.0) -x else if (x == 0.0) 0.0 else x

fun abs(x: Float): Float = if (x < 0.0f) -x else if (x == 0.0f) 0.0f else x

fun sqrt(x: Double): Double = __mathSqrt(x)

fun sqrt(x: Float): Float = __mathSqrt(x)

fun ceil(x: Double): Double = __mathCeil(x)

fun ceil(x: Float): Float = __mathCeil(x)

fun floor(x: Double): Double = __mathFloor(x)

fun floor(x: Float): Float = __mathFloor(x)

fun round(x: Double): Double = __mathRound(x)

fun round(x: Float): Float = __mathRound(x)

fun truncate(x: Double): Double = __mathTruncate(x)

fun truncate(x: Float): Float = __mathTruncate(x)

fun sin(x: Double): Double = __mathSin(x)

fun sin(x: Float): Float = __mathSin(x)

fun cos(x: Double): Double = __mathCos(x)

fun cos(x: Float): Float = __mathCos(x)

fun tan(x: Double): Double = __mathTan(x)

fun tan(x: Float): Float = __mathTan(x)

fun asin(x: Double): Double = __mathAsin(x)

fun asin(x: Float): Float = __mathAsin(x)

fun acos(x: Double): Double = __mathAcos(x)

fun acos(x: Float): Float = __mathAcos(x)

fun atan(x: Double): Double = __mathAtan(x)

fun atan(x: Float): Float = __mathAtan(x)

fun atan2(y: Double, x: Double): Double = __mathAtan2(y, x)

fun atan2(y: Float, x: Float): Float = __mathAtan2(y, x)

fun exp(x: Double): Double = __mathExp(x)

fun exp(x: Float): Float = __mathExp(x)

fun expm1(x: Double): Double = __mathExpm1(x)

fun expm1(x: Float): Float = __mathExpm1(x)

fun ln(x: Double): Double = __mathLn(x)

fun ln(x: Float): Float = __mathLn(x)

fun ln1p(x: Double): Double = __mathLn1p(x)

fun ln1p(x: Float): Float = __mathLn1p(x)

fun log2(x: Double): Double = __mathLog2(x)

fun log2(x: Float): Float = __mathLog2(x)

fun log10(x: Double): Double = __mathLog10(x)

fun log10(x: Float): Float = __mathLog10(x)

fun log(x: Double, base: Double): Double = __mathLn(x) / __mathLn(base)

fun log(x: Float, base: Float): Float = __mathLn(x) / __mathLn(base)

fun sinh(x: Double): Double = __mathSinh(x)

fun sinh(x: Float): Float = __mathSinh(x)

fun cosh(x: Double): Double = __mathCosh(x)

fun cosh(x: Float): Float = __mathCosh(x)

fun tanh(x: Double): Double = __mathTanh(x)

fun tanh(x: Float): Float = __mathTanh(x)

fun cbrt(x: Double): Double = __mathCbrt(x)

fun cbrt(x: Float): Float = __mathCbrt(x)

fun acosh(x: Double): Double = __mathAcosh(x)

fun acosh(x: Float): Float = __mathAcosh(x)

fun asinh(x: Double): Double = __mathAsinh(x)

fun asinh(x: Float): Float = __mathAsinh(x)

fun atanh(x: Double): Double = __mathAtanh(x)

fun atanh(x: Float): Float = __mathAtanh(x)

fun sign(x: Double): Double =
    if (__doubleIsNaN(x) || x == 0.0) x else if (x < 0.0) -1.0 else 1.0

fun sign(x: Float): Float =
    if (__floatIsNaN(x) || x == 0.0f) x else if (x < 0.0f) -1.0f else 1.0f

fun hypot(x: Double, y: Double): Double = __mathHypot(x, y)

fun hypot(x: Float, y: Float): Float = __mathHypot(x, y)

fun ulp(x: Double): Double = __doubleUlp(x)

fun ulp(x: Float): Float = __floatUlp(x)

fun nextUp(x: Double): Double = __doubleNextUp(x)

fun nextUp(x: Float): Float = __floatNextUp(x)

fun nextDown(x: Double): Double = __doubleNextDown(x)

fun nextDown(x: Float): Float = __floatNextDown(x)

fun roundToInt(x: Float): Int = __floatRoundToInt(x)

fun roundToInt(x: Double): Int = __doubleRoundToInt(x)

fun roundToLong(x: Float): Long = __floatRoundToLong(x)

fun roundToLong(x: Double): Long = __doubleRoundToLong(x)

fun max(a: Double, b: Double): Double = __mathMax(a, b)

fun max(a: Float, b: Float): Float = __mathMax(a, b)

fun max(a: Int, b: Int): Int = if (a >= b) a else b

fun max(a: Long, b: Long): Long = if (a >= b) a else b

fun min(a: Double, b: Double): Double = __mathMin(a, b)

fun min(a: Float, b: Float): Float = __mathMin(a, b)

fun min(a: Int, b: Int): Int = if (a <= b) a else b

fun min(a: Long, b: Long): Long = if (a <= b) a else b
