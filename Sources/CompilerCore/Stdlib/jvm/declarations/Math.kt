package kotlin.math

public const val PI: Double = 3.141592653589793
public const val E: Double = 2.718281828459045

public fun abs(n: Int): Int = 0
public fun abs(n: Long): Long = 0L
public fun abs(x: Double): Double = 0.0
public fun abs(x: Float): Float = 0.0f

public val Int.absoluteValue: Int get() = 0
public val Long.absoluteValue: Long get() = 0L
public val Double.absoluteValue: Double get() = 0.0
public val Float.absoluteValue: Float get() = 0.0f

public fun sign(x: Double): Double = 0.0
public fun sign(x: Float): Float = 0.0f
public val Double.sign: Double get() = 0.0
public val Float.sign: Float get() = 0.0f
public val Int.sign: Int get() = 0
public val Long.sign: Int get() = 0

public fun min(a: Int, b: Int): Int = 0
public fun max(a: Int, b: Int): Int = 0
public fun min(a: Long, b: Long): Long = 0L
public fun max(a: Long, b: Long): Long = 0L
public fun min(a: Double, b: Double): Double = 0.0
public fun max(a: Double, b: Double): Double = 0.0
public fun min(a: Float, b: Float): Float = 0.0f
public fun max(a: Float, b: Float): Float = 0.0f
public fun min(a: UInt, b: UInt): UInt = 0u
public fun max(a: UInt, b: UInt): UInt = 0u
public fun min(a: ULong, b: ULong): ULong = 0uL
public fun max(a: ULong, b: ULong): ULong = 0uL

public fun ceil(x: Double): Double = 0.0
public fun floor(x: Double): Double = 0.0
public fun round(x: Double): Double = 0.0
public fun truncate(x: Double): Double = 0.0
public fun ceil(x: Float): Float = 0.0f
public fun floor(x: Float): Float = 0.0f
public fun round(x: Float): Float = 0.0f
public fun truncate(x: Float): Float = 0.0f

public fun Double.withSign(sign: Double): Double = 0.0
public fun Double.withSign(sign: Int): Double = 0.0
public fun Float.withSign(sign: Float): Float = 0.0f
public fun Float.withSign(sign: Int): Float = 0.0f

public fun sqrt(x: Double): Double = 0.0
public fun sqrt(x: Float): Float = 0.0f
public fun Double.pow(x: Double): Double = 0.0
public fun Double.pow(n: Int): Double = 0.0
public fun Float.pow(x: Float): Float = 0.0f
public fun Float.pow(n: Int): Float = 0.0f
public fun Double.IEEErem(divisor: Double): Double = 0.0
public fun Float.IEEErem(divisor: Float): Float = 0.0f
public fun Double.nextTowards(to: Double): Double = 0.0
public fun Float.nextTowards(to: Float): Float = 0.0f

public fun sin(x: Double): Double = 0.0
public fun cos(x: Double): Double = 0.0
public fun tan(x: Double): Double = 0.0
public fun asin(x: Double): Double = 0.0
public fun acos(x: Double): Double = 0.0
public fun atan(x: Double): Double = 0.0
public fun atan2(y: Double, x: Double): Double = 0.0
public fun sinh(x: Double): Double = 0.0
public fun cosh(x: Double): Double = 0.0
public fun tanh(x: Double): Double = 0.0
public fun hypot(x: Double, y: Double): Double = 0.0
public fun exp(x: Double): Double = 0.0
public fun expm1(x: Double): Double = 0.0
public fun ln(x: Double): Double = 0.0
public fun ln1p(x: Double): Double = 0.0
public fun log2(x: Double): Double = 0.0
public fun log10(x: Double): Double = 0.0
public fun log(x: Double, base: Double): Double = 0.0
public fun acosh(x: Double): Double = 0.0
public fun asinh(x: Double): Double = 0.0
public fun atanh(x: Double): Double = 0.0
public fun cbrt(x: Double): Double = 0.0

public fun sin(x: Float): Float = 0.0f
public fun cos(x: Float): Float = 0.0f
public fun tan(x: Float): Float = 0.0f
public fun asin(x: Float): Float = 0.0f
public fun acos(x: Float): Float = 0.0f
public fun atan(x: Float): Float = 0.0f
public fun atan2(y: Float, x: Float): Float = 0.0f
public fun sinh(x: Float): Float = 0.0f
public fun cosh(x: Float): Float = 0.0f
public fun tanh(x: Float): Float = 0.0f
public fun hypot(x: Float, y: Float): Float = 0.0f
public fun exp(x: Float): Float = 0.0f
public fun expm1(x: Float): Float = 0.0f
public fun ln(x: Float): Float = 0.0f
public fun ln1p(x: Float): Float = 0.0f
public fun log2(x: Float): Float = 0.0f
public fun log10(x: Float): Float = 0.0f
public fun log(x: Float, base: Float): Float = 0.0f
public fun acosh(x: Float): Float = 0.0f
public fun asinh(x: Float): Float = 0.0f
public fun atanh(x: Float): Float = 0.0f
public fun cbrt(x: Float): Float = 0.0f

public fun Float.roundToInt(): Int = 0
public fun Double.roundToInt(): Int = 0
public fun Float.roundToLong(): Long = 0L
public fun Double.roundToLong(): Long = 0L
public val Double.ulp: Double get() = 0.0
public val Float.ulp: Float get() = 0.0f
public fun Double.nextUp(): Double = 0.0
public fun Float.nextUp(): Float = 0.0f
public fun Double.nextDown(): Double = 0.0
public fun Float.nextDown(): Float = 0.0f
