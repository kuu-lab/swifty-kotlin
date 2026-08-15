package kotlin.math

import kotlin.comparisons.maxOf
import kotlin.comparisons.minOf
import kotlin.internal.KsSymbolName

// KSP-635
// abs / sign / min / max and the PI / E constants migrated from the synthetic
// stubs in Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMathStubs.swift
// and the kk_math_abs*/kk_math_sign*/kk_math_min*/kk_math_max*/kk_math_PI/kk_math_E
// entry points in Sources/Runtime/RuntimeNumericCompat.swift.
//
// The floating-point min/max delegate to kotlin.comparisons.maxOf/minOf, which
// already own the NaN propagation and signed-zero ordering contract; everything
// else is expressible without touching the runtime.

public val PI: Double get() = 3.141592653589793
public val E: Double get() = 2.718281828459045

// `0.0 - x` (rather than `-x`) normalizes -0.0 to +0.0 while leaving NaN and
// the infinities untouched. abs(Int.MIN_VALUE) / abs(Long.MIN_VALUE) overflow
// back to the same value, matching Kotlin.

public fun abs(n: Int): Int = if (n < 0) -n else n

public fun abs(n: Long): Long = if (n < 0L) -n else n

public fun abs(x: Double): Double = if (x <= 0.0) 0.0 - x else x

public fun abs(x: Float): Float = if (x <= 0.0f) 0.0f - x else x

public val Int.absoluteValue: Int get() = abs(this)

public val Long.absoluteValue: Long get() = abs(this)

public val Double.absoluteValue: Double get() = abs(this)

public val Float.absoluteValue: Float get() = abs(this)

// NaN falls through to the final branch and is returned as-is, and ±0.0 keeps
// its own sign, as specified for Math.signum.

public fun sign(x: Double): Double = if (x > 0.0) 1.0 else if (x < 0.0) -1.0 else x

public fun sign(x: Float): Float = if (x > 0.0f) 1.0f else if (x < 0.0f) -1.0f else x

public val Double.sign: Double get() = if (this > 0.0) 1.0 else if (this < 0.0) -1.0 else this

public val Float.sign: Float get() = if (this > 0.0f) 1.0f else if (this < 0.0f) -1.0f else this

public val Int.sign: Int get() = if (this > 0) 1 else if (this < 0) -1 else 0

public val Long.sign: Int get() = if (this > 0L) 1 else if (this < 0L) -1 else 0

public fun max(a: Int, b: Int): Int = maxOf(a, b)

public fun max(a: Long, b: Long): Long = maxOf(a, b)

public fun max(a: Float, b: Float): Float = maxOf(a, b)

public fun max(a: Double, b: Double): Double = maxOf(a, b)

public fun max(a: UInt, b: UInt): UInt = maxOf(a, b)

public fun max(a: ULong, b: ULong): ULong = maxOf(a, b)

public fun min(a: Int, b: Int): Int = minOf(a, b)

public fun min(a: Long, b: Long): Long = minOf(a, b)

public fun min(a: Float, b: Float): Float = minOf(a, b)

public fun min(a: Double, b: Double): Double = minOf(a, b)

public fun min(a: UInt, b: UInt): UInt = minOf(a, b)

public fun min(a: ULong, b: ULong): ULong = minOf(a, b)

// KSP-636
// ceil / floor / round / truncate and withSign migrated from the synthetic
// stubs in Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMathStubs.swift
// and the kk_math_* entry points in Sources/Runtime/RuntimeNumericCompat.swift.
//
// Rounding functions still need libm/Foundation, so they are exposed as
// internal __kk_math_* runtime bridges. withSign is pure bit manipulation on
// top of Double/Float.toRawBits and Double/Float.fromBits, so it lives fully
// in Kotlin.

@KsSymbolName("__kk_math_ceil")
internal external fun __kkMathCeil(x: Double): Double

@KsSymbolName("__kk_math_floor")
internal external fun __kkMathFloor(x: Double): Double

@KsSymbolName("__kk_math_round")
internal external fun __kkMathRound(x: Double): Double

@KsSymbolName("__kk_math_truncate")
internal external fun __kkMathTruncate(x: Double): Double

@KsSymbolName("__kk_math_ceil_float")
internal external fun __kkMathCeilFloat(x: Float): Float

@KsSymbolName("__kk_math_floor_float")
internal external fun __kkMathFloorFloat(x: Float): Float

@KsSymbolName("__kk_math_round_float")
internal external fun __kkMathRoundFloat(x: Float): Float

@KsSymbolName("__kk_math_truncate_float")
internal external fun __kkMathTruncateFloat(x: Float): Float

public fun ceil(x: Double): Double = __kkMathCeil(x)

public fun floor(x: Double): Double = __kkMathFloor(x)

public fun round(x: Double): Double = __kkMathRound(x)

public fun truncate(x: Double): Double = __kkMathTruncate(x)

public fun ceil(x: Float): Float = __kkMathCeilFloat(x)

public fun floor(x: Float): Float = __kkMathFloorFloat(x)

public fun round(x: Float): Float = __kkMathRoundFloat(x)

public fun truncate(x: Float): Float = __kkMathTruncateFloat(x)

public fun Double.withSign(sign: Double): Double {
    val xBits = this.toRawBits()
    val signBit = sign.toRawBits() and Long.MIN_VALUE
    val mag = xBits and Long.MAX_VALUE
    return Double.fromBits(mag or signBit)
}

public fun Double.withSign(sign: Int): Double =
    if (sign < 0) -abs(this) else abs(this)

public fun Float.withSign(sign: Float): Float {
    val xBits = this.toRawBits()
    val signBit = sign.toRawBits() and Int.MIN_VALUE
    val mag = xBits and Int.MAX_VALUE
    return Float.fromBits(mag or signBit)
}

public fun Float.withSign(sign: Int): Float =
    if (sign < 0) -abs(this) else abs(this)

// KSP-638
// roundToInt / roundToLong / ulp / nextUp / nextDown are Kotlin-source
// surface declarations. Their native implementations remain bridges because
// rounding must preserve Kotlin's NaN exception and saturation contract, while
// the precision helpers operate on IEEE 754 bit patterns.

@KsSymbolName("__kk_float_roundToInt")
internal external fun __kkFloatRoundToInt(x: Float): Int

@KsSymbolName("__kk_double_roundToInt")
internal external fun __kkDoubleRoundToInt(x: Double): Int

@KsSymbolName("__kk_float_roundToLong")
internal external fun __kkFloatRoundToLong(x: Float): Long

@KsSymbolName("__kk_double_roundToLong")
internal external fun __kkDoubleRoundToLong(x: Double): Long

@KsSymbolName("__kk_double_ulp")
internal external fun __kkDoubleUlp(x: Double): Double

@KsSymbolName("__kk_float_ulp")
internal external fun __kkFloatUlp(x: Float): Float

@KsSymbolName("__kk_double_nextUp")
internal external fun __kkDoubleNextUp(x: Double): Double

@KsSymbolName("__kk_float_nextUp")
internal external fun __kkFloatNextUp(x: Float): Float

@KsSymbolName("__kk_double_nextDown")
internal external fun __kkDoubleNextDown(x: Double): Double

@KsSymbolName("__kk_float_nextDown")
internal external fun __kkFloatNextDown(x: Float): Float

public fun Float.roundToInt(): Int = __kkFloatRoundToInt(this)

public fun Double.roundToInt(): Int = __kkDoubleRoundToInt(this)

public fun Float.roundToLong(): Long = __kkFloatRoundToLong(this)

public fun Double.roundToLong(): Long = __kkDoubleRoundToLong(this)

public val Double.ulp: Double get() = __kkDoubleUlp(this)

public val Float.ulp: Float get() = __kkFloatUlp(this)

public fun Double.nextUp(): Double = __kkDoubleNextUp(this)

public fun Float.nextUp(): Float = __kkFloatNextUp(this)

public fun Double.nextDown(): Double = __kkDoubleNextDown(this)

public fun Float.nextDown(): Float = __kkFloatNextDown(this)
