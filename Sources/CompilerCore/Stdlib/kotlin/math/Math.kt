/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/util/MathH.kt
 * (kotlin.math declaration surface and the PI/E constant values).
 */

package kotlin.math

// KSP-635: pure-logic kotlin.math surface (abs/sign/min/max + PI/E) migrated
// from the synthetic stubs in
// Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticMathStubs.swift and
// the kk_math_{abs,sign,min,max,PI,E}* runtime exports in
// Sources/Runtime/RuntimeNumericCompat.swift.
//
// Floating-point overloads follow the JVM Math.min/Math.max contract that
// Kotlin specifies: NaN propagates through min/max, and signed zeros are
// ordered (-0.0 < 0.0) even though they compare equal. Zero signs are probed
// with toRawBits() rather than a comparison, which cannot distinguish them.

public const val PI: Double = 3.141592653589793

public const val E: Double = 2.718281828459045

// abs

public fun abs(x: Double): Double = if (x < 0.0) -x else if (x == 0.0) 0.0 else x

public fun abs(x: Float): Float = if (x < 0.0f) -x else if (x == 0.0f) 0.0f else x

public fun abs(n: Int): Int = if (n < 0) -n else n

public fun abs(n: Long): Long = if (n < 0L) -n else n

public val Double.absoluteValue: Double get() = abs(this)

public val Float.absoluteValue: Float get() = abs(this)

public val Int.absoluteValue: Int get() = abs(this)

public val Long.absoluteValue: Long get() = abs(this)

// sign

public fun sign(x: Double): Double {
    if (x.isNaN()) return Double.NaN
    if (x > 0.0) return 1.0
    if (x < 0.0) return -1.0
    return x
}

public fun sign(x: Float): Float {
    if (x.isNaN()) return Float.NaN
    if (x > 0.0f) return 1.0f
    if (x < 0.0f) return -1.0f
    return x
}

public val Double.sign: Double get() = sign(this)

public val Float.sign: Float get() = sign(this)

public val Int.sign: Int get() = if (this > 0) 1 else if (this < 0) -1 else 0

public val Long.sign: Int get() = if (this > 0L) 1 else if (this < 0L) -1 else 0

// max / min

public fun max(a: Double, b: Double): Double {
    if (a.isNaN() || b.isNaN()) return Double.NaN
    if (a == 0.0 && b == 0.0) {
        return if (a.toRawBits() < 0L && b.toRawBits() < 0L) -0.0 else 0.0
    }
    return if (a >= b) a else b
}

public fun max(a: Float, b: Float): Float {
    if (a.isNaN() || b.isNaN()) return Float.NaN
    if (a == 0.0f && b == 0.0f) {
        return if (a.toRawBits() < 0 && b.toRawBits() < 0) -0.0f else 0.0f
    }
    return if (a >= b) a else b
}

public fun max(a: Int, b: Int): Int = if (a >= b) a else b

public fun max(a: Long, b: Long): Long = if (a >= b) a else b

public fun max(a: UInt, b: UInt): UInt = if (a >= b) a else b

public fun max(a: ULong, b: ULong): ULong = if (a >= b) a else b

public fun min(a: Double, b: Double): Double {
    if (a.isNaN() || b.isNaN()) return Double.NaN
    if (a == 0.0 && b == 0.0) {
        return if (a.toRawBits() < 0L || b.toRawBits() < 0L) -0.0 else 0.0
    }
    return if (a <= b) a else b
}

public fun min(a: Float, b: Float): Float {
    if (a.isNaN() || b.isNaN()) return Float.NaN
    if (a == 0.0f && b == 0.0f) {
        return if (a.toRawBits() < 0 || b.toRawBits() < 0) -0.0f else 0.0f
    }
    return if (a <= b) a else b
}

public fun min(a: Int, b: Int): Int = if (a <= b) a else b

public fun min(a: Long, b: Long): Long = if (a <= b) a else b

public fun min(a: UInt, b: UInt): UInt = if (a <= b) a else b

public fun min(a: ULong, b: ULong): ULong = if (a <= b) a else b
