/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/random/{Random,XorWowRandom}.kt.
 */

package kotlin.random

import kotlin.math.nextDown
import kotlin.internal.KsSymbolName

// The public API and state initialization follow kotlin-stdlib's
// libraries/stdlib/src/kotlin/random/{Random,XorWowRandom}.kt structure so
// seeded output remains bit-exact with kotlinc.
private external fun __kk_random_seed_entropy(): Long

@KsSymbolName("__kk_random_nextInt_rangeObject")
private external fun __kk_random_nextInt_rangeObject(random: Random, range: IntRange): Int

@KsSymbolName("__kk_random_nextLong_rangeObject")
private external fun __kk_random_nextLong_rangeObject(random: Random, range: LongRange): Long

// Single-method interfaces expose the Random methods that native runtime
// helpers call through itable dispatch. Keeping each interface to one method
// fixes its runtime slot at zero, independent of symbol ordering. They are
// public so downstream modules can resolve them from compiled .kklib metadata.
public interface RandomSource {
    public fun nextIntBelow(until: Int): Int
}

public interface RandomLongSource {
    public fun nextLongBits(): Long
}

public interface RandomIntBitsSource {
    public fun nextIntBits(): Int
}

public interface RandomIntRangeSource {
    public fun nextIntRange(from: Int, until: Int): Int
}

public interface RandomLongRangeSource {
    public fun nextLongRange(from: Long, until: Long): Long
}

public abstract class Random : RandomSource, RandomLongSource, RandomIntBitsSource, RandomIntRangeSource, RandomLongRangeSource {
    public abstract fun nextBits(bitCount: Int): Int

    public open fun nextInt(): Int = nextBits(32)

    public open fun nextInt(until: Int): Int = nextInt(0, until)

    public open fun nextInt(from: Int, until: Int): Int {
        checkRangeBounds(from, until)
        val n = until - from
        if (n > 0 || n == Int.MIN_VALUE) {
            val rnd = if (n and -n == n) {
                val bitCount = fastLog2(n)
                nextBits(bitCount)
            } else {
                var v: Int
                do {
                    val bits = nextInt().ushr(1)
                    v = bits % n
                } while (bits - v + (n - 1) < 0)
                v
            }
            return from + rnd
        }
        var result: Int
        do {
            result = nextInt()
        } while (result !in from until until)
        return result
    }

    // Keep both operands as Long to preserve Kotlin's sign extension of the
    // low Int when composing the 64-bit result.
    public open fun nextLong(): Long = nextInt().toLong().shl(32) + nextInt().toLong()

    public open fun nextLong(until: Long): Long = nextLong(0L, until)

    public open fun nextLong(from: Long, until: Long): Long {
        checkRangeBounds(from, until)
        val n = until - from
        if (n > 0) {
            val rnd: Long
            if (n and -n == n) {
                val nLow = n.toInt()
                val nHigh = (n ushr 32).toInt()
                rnd = if (nLow != 0) {
                    val bitCount = fastLog2(nLow)
                    nextBits(bitCount).toLong() and 0xFFFF_FFFFL
                } else if (nHigh == 1) {
                    nextInt().toLong() and 0xFFFF_FFFFL
                } else {
                    val bitCount = fastLog2(nHigh)
                    nextBits(bitCount).toLong().shl(32) + (nextInt().toLong() and 0xFFFF_FFFFL)
                }
            } else {
                var v: Long
                do {
                    val bits = nextLong().ushr(1)
                    v = bits % n
                } while (bits - v + (n - 1) < 0)
                rnd = v
            }
            return from + rnd
        }
        var result: Long
        do {
            result = nextLong()
        } while (result !in from until until)
        return result
    }

    public open override fun nextIntBelow(until: Int): Int = nextInt(until)

    public open override fun nextIntBits(): Int = nextInt()

    public open override fun nextIntRange(from: Int, until: Int): Int = nextInt(from, until)

    public open override fun nextLongBits(): Long = nextLong()

    public open override fun nextLongRange(from: Long, until: Long): Long = nextLong(from, until)

    public open fun nextBoolean(): Boolean = nextBits(1) != 0

    public open fun nextDouble(): Double = doubleFromParts(nextBits(26), nextBits(27))

    public open fun nextDouble(until: Double): Double = nextDouble(0.0, until)

    public open fun nextDouble(from: Double, until: Double): Double {
        checkRangeBounds(from, until)
        val size = until - from
        val r = if (size.isInfinite() && from.isFinite() && until.isFinite()) {
            val r1 = nextDouble() * (until / 2 - from / 2)
            from + r1 + r1
        } else {
            from + nextDouble() * size
        }
        return if (r >= until) until.nextDown() else r
    }

    public open fun nextFloat(): Float = nextBits(24) / (1 shl 24).toFloat()

    // Non-standard overloads: real kotlin.random.Random has no nextFloat(Float)
    // overloads. Kept for backward compatibility with KSwiftK's pre-existing
    // public surface (formerly kk_random_nextFloat_until/_range).
    public open fun nextFloat(until: Float): Float {
        require(until > 0 && until.isFinite()) {
            "Random range is empty: until must be positive, but was $until."
        }
        return nextFloat() * until
    }

    public open fun nextFloat(from: Float, until: Float): Float {
        // See checkRangeBounds below for why the message is precomputed.
        val message = "Random range is empty: $from..$until."
        require(until > from && from.isFinite() && until.isFinite()) { message }
        return from + (nextFloat() * (until - from))
    }

    public open fun nextBytes(array: ByteArray, fromIndex: Int, toIndex: Int): ByteArray {
        // See checkRangeBounds below for why these messages are precomputed.
        val rangeMessage = "fromIndex ($fromIndex) or toIndex ($toIndex) are out of range: 0..${array.size}."
        require(fromIndex in 0..array.size && toIndex in 0..array.size) { rangeMessage }
        val orderMessage = "fromIndex ($fromIndex) must be not greater than toIndex ($toIndex)."
        require(fromIndex <= toIndex) { orderMessage }
        val steps = (toIndex - fromIndex) / 4
        var position = fromIndex
        repeat(steps) {
            val v = nextInt()
            array[position] = v.toByte()
            array[position + 1] = v.ushr(8).toByte()
            array[position + 2] = v.ushr(16).toByte()
            array[position + 3] = v.ushr(24).toByte()
            position = position + 4
        }
        val remainder = toIndex - position
        val vr = nextBits(remainder * 8)
        for (i in 0 until remainder) {
            array[position + i] = vr.ushr(i * 8).toByte()
        }
        return array
    }

    public open fun nextBytes(array: ByteArray): ByteArray = nextBytes(array, 0, array.size)

    public open fun nextBytes(size: Int): ByteArray = nextBytes(ByteArray(size) { 0 })

    public companion object Default : Random() {
        private val defaultRandom: Random

        init {
            val entropy = __kk_random_seed_entropy()
            defaultRandom = Random(entropy)
        }

        // NOTE: every open member is re-declared here, even though most bodies
        // are identical to what Random's own skeleton implementation would
        // already compute by calling nextBits() virtually. This compiler's "bare ClassName.member()"
        // shorthand for named-companion access (used throughout existing
        // diff_cases/golden tests, e.g. `Random.nextInt(1, 10)`) only resolves
        // members the companion *directly declares*, not ones it merely
        // inherits — confirmed with a minimal repro independent of Random.
        // Relying on inheritance here would make Random.nextInt()/nextLong()/
        // etc. (without an explicit `.Default`) fail to resolve.
        override fun nextBits(bitCount: Int): Int = defaultRandom.nextBits(bitCount)
        override fun nextInt(): Int = defaultRandom.nextInt()
        override fun nextInt(until: Int): Int = defaultRandom.nextInt(until)
        override fun nextInt(from: Int, until: Int): Int = defaultRandom.nextInt(from, until)
        override fun nextLong(): Long = defaultRandom.nextLong()
        override fun nextLong(until: Long): Long = defaultRandom.nextLong(until)
        override fun nextLong(from: Long, until: Long): Long = defaultRandom.nextLong(from, until)
        override fun nextBoolean(): Boolean = defaultRandom.nextBoolean()
        override fun nextDouble(): Double = defaultRandom.nextDouble()
        override fun nextDouble(until: Double): Double = defaultRandom.nextDouble(until)
        override fun nextDouble(from: Double, until: Double): Double = defaultRandom.nextDouble(from, until)
        override fun nextFloat(): Float = defaultRandom.nextFloat()
        override fun nextFloat(until: Float): Float = defaultRandom.nextFloat(until)
        override fun nextFloat(from: Float, until: Float): Float = defaultRandom.nextFloat(from, until)
        override fun nextBytes(array: ByteArray, fromIndex: Int, toIndex: Int): ByteArray =
            defaultRandom.nextBytes(array, fromIndex, toIndex)
        override fun nextBytes(array: ByteArray): ByteArray = defaultRandom.nextBytes(array)
        override fun nextBytes(size: Int): ByteArray = defaultRandom.nextBytes(size)
    }
}

public fun Random.nextInt(range: IntRange): Int = __kk_random_nextInt_rangeObject(this, range)

public fun Random.nextLong(range: LongRange): Long = __kk_random_nextLong_rangeObject(this, range)

internal class XorWowRandom internal constructor(
    private var x: Int,
    private var y: Int,
    private var z: Int,
    private var w: Int,
    private var v: Int,
    private var addend: Int
) : Random() {
    internal constructor(seed1: Int, seed2: Int) :
        this(seed1, seed2, 0, 0, seed1.inv(), (seed1 shl 10) xor (seed2 ushr 4))

    init {
        require((x or y or z or w or v) != 0) { "Initial state must have at least one non-zero element." }
        // Some trivial seeds produce several values with zeroes in upper bits,
        // so discard the first 64 values just like kotlin-stdlib.
        repeat(64) { val _ = nextInt() }
    }

    // Marsaglia's xorwow step. The explicit field reassignment is intentional:
    // compound assignment on instance fields is not persistent in this compiler.
    override fun nextInt(): Int {
        var t = x
        t = t xor (t ushr 2)
        x = y
        y = z
        z = w
        val v0 = v
        w = v0
        t = (t xor (t shl 1)) xor v0 xor (v0 shl 4)
        v = t
        addend = addend + 362437
        return t + addend
    }

    override fun nextBits(bitCount: Int): Int = nextInt().takeUpperBits(bitCount)
}

public fun Random(seed: Int): Random = XorWowRandom(seed, seed.shr(31))

public fun Random(seed: Long): Random = XorWowRandom(seed.toInt(), seed.shr(32).toInt())

internal fun fastLog2(value: Int): Int = 31 - value.countLeadingZeroBits()

internal fun Int.takeUpperBits(bitCount: Int): Int = this.ushr(32 - bitCount) and (-bitCount).shr(31)

internal fun boundsErrorMessage(from: Any, until: Any): String = "Random range is empty: [$from, $until)."

// NOTE: the message is precomputed as a local val rather than passed as an
// inline `{ boundsErrorMessage(from, until) }` lambda. A require()/check()
// message lambda that (transitively) captures 3+ distinct values from an
// enclosing member-function call chain (this happens even though
// boundsErrorMessage itself is a top-level, 2-parameter function; the crash
// is tied to the calling context, not this function's own capture count) hits
// a confirmed compiler bug: either silently wrong interpolated values, or an
// outright crash (KSWIFTK-RUNTIME-0001 kk_array_get_inbounds). Precomputing
// avoids it entirely, at the cost of require()'s normal message-laziness.
internal fun checkRangeBounds(from: Int, until: Int) {
    val message = boundsErrorMessage(from, until)
    require(until > from) { message }
}

internal fun checkRangeBounds(from: Long, until: Long) {
    val message = boundsErrorMessage(from, until)
    require(until > from) { message }
}

internal fun checkRangeBounds(from: Double, until: Double) {
    val message = boundsErrorMessage(from, until)
    require(until > from) { message }
}

internal fun doubleFromParts(hi26: Int, low27: Int): Double =
    (hi26.toLong().shl(27) + low27) / (1L shl 53).toDouble()
