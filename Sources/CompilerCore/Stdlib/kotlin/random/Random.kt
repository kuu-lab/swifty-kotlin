package kotlin.random

import kotlin.math.nextDown

// KSP-466: Random — Kotlin-source implementation of kotlin.random.Random, using
// the real kotlin.random.XorWowRandom algorithm (ported from kotlin-stdlib
// libraries/stdlib/src/kotlin/random/{Random,XorWowRandom}.kt) so behavior
// matches kotlinc exactly for the deterministic (seeded) path.
//
// NOTE: upstream Kotlin splits this into an `abstract class Random` (skeleton,
// no state) + `internal class XorWowRandom : Random()` (the concrete PRNG) +
// top-level `fun Random(seed: Int): Random` factory functions. KSwiftK's Sema
// does not currently support a class and a same-named top-level function
// coexisting in the same package (a general limitation, not specific to
// Random). This file therefore merges Random/XorWowRandom into a single open
// class and uses public secondary constructors (`Random(seed): this(...)`)
// instead of top-level factory functions, so `Random(seed)` remains ordinary
// constructor-call syntax with identical observable behavior and a bit-exact
// algorithm.
//
// Bridge residue: __kk_random_seed_entropy is the only native call, used once
// to seed Random.Default from system entropy.
private external fun __kk_random_seed_entropy(): Long

public open class Random internal constructor(
    private var x: Int,
    private var y: Int,
    private var z: Int,
    private var w: Int,
    private var v: Int,
    private var addend: Int
) {
    public constructor(seed: Int) : this(
        seed, seed.shr(31), 0, 0, seed.inv(), (seed shl 10) xor (seed.shr(31) ushr 4)
    )

    public constructor(seed: Long) : this(
        seed.toInt(), seed.shr(32).toInt(), 0, 0,
        seed.toInt().inv(), (seed.toInt() shl 10) xor (seed.shr(32).toInt() ushr 4)
    )

    init {
        require((x or y or z or w or v) != 0) { "Initial state must have at least one non-zero element." }
        repeat(64) { val _ = stepXorWow() }
    }

    // Raw XorWow step. Private (non-overridable) so the warm-up loop above
    // always advances *this* instance's own state: calling an `open` member
    // from here would dispatch to a subclass override before the subclass's
    // own properties (e.g. Default's `defaultRandom`) are initialized.
    private fun stepXorWow(): Int {
        var t = x
        t = t xor (t ushr 2)
        x = y
        y = z
        z = w
        val v0 = v
        w = v0
        t = (t xor (t shl 1)) xor v0 xor (v0 shl 4)
        v = t
        // NOTE: `addend += 362437` (compound assignment) does not persist on
        // instance fields in this compiler (confirmed reproducible outside
        // Random too — a general codegen gap, not specific to this class).
        // Explicit reassignment works correctly and is used everywhere in
        // this file for that reason.
        addend = addend + 362437
        return t + addend
    }

    public open fun nextBits(bitCount: Int): Int = stepXorWow().takeUpperBits(bitCount)

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

    // Keep both operands as Long.  The mixed Long + Int overload currently
    // resolves through an invalid dispatch path in KSwiftK and can recurse
    // indefinitely when Random.Default is used.
    public open fun nextLong(): Long = nextInt().toLong().shl(32) + (nextInt().toLong() and 0xFFFF_FFFFL)

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

    // nextUInt/nextULong (scalar overloads; ported from kotlin-stdlib
    // libraries/stdlib/src/kotlin/random/URandom.kt) are declared as real
    // members here rather than package-level extensions (as upstream does):
    // the kept native nextUInt(UIntRange)/nextULong(ULongRange) bridges
    // (KSP-457 scope) are registered as members named "nextUInt"/"nextULong",
    // and this compiler's overload resolution does not consider package-level
    // extensions once a member of the same name exists (same shadowing
    // confirmed for nextInt/nextLong above). Declaring these as sibling
    // members avoids that entirely.
    public open fun nextUInt(): UInt = nextInt().toUInt()

    public open fun nextUInt(until: UInt): UInt = nextUInt(0u, until)

    public open fun nextUInt(from: UInt, until: UInt): UInt {
        checkUIntRangeBounds(from, until)
        val signedFrom = from.toInt() xor Int.MIN_VALUE
        val signedUntil = until.toInt() xor Int.MIN_VALUE
        val signedResult = nextInt(signedFrom, signedUntil) xor Int.MIN_VALUE
        return signedResult.toUInt()
    }

    public open fun nextULong(): ULong = nextLong().toULong()

    public open fun nextULong(until: ULong): ULong = nextULong(0uL, until)

    public open fun nextULong(from: ULong, until: ULong): ULong {
        checkULongRangeBounds(from, until)
        val signedFrom = from.toLong() xor Long.MIN_VALUE
        val signedUntil = until.toLong() xor Long.MIN_VALUE
        val signedResult = nextLong(signedFrom, signedUntil) xor Long.MIN_VALUE
        return signedResult.toULong()
    }

    public companion object Default : Random(1, 0, 0, 0, 1, 0) {
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
        override fun nextUInt(): UInt = defaultRandom.nextUInt()
        override fun nextUInt(until: UInt): UInt = defaultRandom.nextUInt(until)
        override fun nextUInt(from: UInt, until: UInt): UInt = defaultRandom.nextUInt(from, until)
        override fun nextULong(): ULong = defaultRandom.nextULong()
        override fun nextULong(until: ULong): ULong = defaultRandom.nextULong(until)
        override fun nextULong(from: ULong, until: ULong): ULong = defaultRandom.nextULong(from, until)
    }
}

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
