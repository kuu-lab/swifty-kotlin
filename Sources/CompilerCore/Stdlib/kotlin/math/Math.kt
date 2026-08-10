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

public fun withSign(x: Double, sign: Double): Double {
    val xBits = x.toRawBits()
    val signBit = sign.toRawBits() and Long.MIN_VALUE
    val mag = xBits and Long.MAX_VALUE
    return Double.fromBits(mag or signBit)
}

public fun withSign(x: Double, sign: Int): Double =
    if (sign < 0) -abs(x) else abs(x)

public fun withSign(x: Float, sign: Float): Float {
    val xBits = x.toRawBits()
    val signBit = sign.toRawBits() and Int.MIN_VALUE
    val mag = xBits and Int.MAX_VALUE
    return Float.fromBits(mag or signBit)
}

public fun withSign(x: Float, sign: Int): Float =
    if (sign < 0) -abs(x) else abs(x)

public fun Double.withSign(sign: Double): Double = withSign(this, sign)

public fun Double.withSign(sign: Int): Double = withSign(this, sign)

public fun Float.withSign(sign: Float): Float = withSign(this, sign)

public fun Float.withSign(sign: Int): Float = withSign(this, sign)
