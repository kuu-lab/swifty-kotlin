package java.util

import kotlin.math.ln
import kotlin.math.nextDown
import kotlin.math.sqrt
import kotlin.random.Random as KotlinRandom

// KSP-466: java.util.Random used to share its native SeededRandomBox
// representation with kotlin.random.Random, so asKotlinRandom()/asJavaRandom()
// could just pass the same opaque handle straight through. Now that
// kotlin.random.Random is a genuine compiled Kotlin object (see
// kotlin.random.Random in Random.kt), a raw pointer passthrough between the two
// is no longer safe: calling a Random method on a handle that is actually a
// SeededRandomBox reads through the wrong object layout. This class instead
// wraps a real kotlin.random.Random so the conversion is a genuine field access.
// (Aliased as KotlinRandom here since this class is itself named Random.)
//
// KUU-2780: java.util.Random's own API (nextInt/nextDouble/... as members of
// this class) is implemented with the JDK's 48-bit LCG so that a seeded
// Random(seed) produces the same sequence as on the JVM. An instance created by
// Random.asJavaRandom() instead pulls its bits from the wrapped Kotlin Random.
public class Random {
    private var seed: Long = 0L
    private val source: KotlinRandom?
    private var nextNextGaussian: Double = 0.0
    private var haveNextNextGaussian: Boolean = false

    // NOTE: these deliberately assign fields in the constructor body rather
    // than delegating via `: this(KotlinRandom(seed))`. Constructor delegation
    // syntax resolves `KotlinRandom(seed)` back to *this* class's own
    // constructor instead of the aliased kotlin.random.Random — since both
    // classes are named "Random", this causes infinite recursion (confirmed via
    // `sample` on the hung process: identical compiled frame calling itself).
    // Plain expression position (as used below) resolves the alias correctly.
    // This looks like a general compiler bug in constructor-delegation-argument
    // resolution, not specific to Random; flagged separately for a proper fix.
    public constructor() {
        source = null
        seed = scrambleSeed(KotlinRandom.Default.nextLong())
    }

    public constructor(seed: Int) {
        source = null
        this.seed = scrambleSeed(seed.toLong())
    }

    public constructor(seed: Long) {
        source = null
        this.seed = scrambleSeed(seed)
    }

    public constructor(delegate: KotlinRandom) {
        source = delegate
    }

    // Kotlin view of this Random. Wrapping instances hand back the Kotlin
    // Random they were built from; LCG-backed ones adapt their own bit stream.
    public val delegate: KotlinRandom
        get() = source ?: JavaRandomAsKotlinRandom(this)

    public fun setSeed(seed: Long) {
        this.seed = scrambleSeed(seed)
        haveNextNextGaussian = false
    }

    internal fun nextBits(bits: Int): Int {
        val wrapped = source
        if (wrapped != null) {
            return wrapped.nextBits(bits)
        }
        seed = (seed * 0x5DEECE66DL + 0xBL) and 0xFFFFFFFFFFFFL
        return (seed ushr (48 - bits)).toInt()
    }

    public fun nextInt(): Int = nextBits(32)

    public fun nextInt(bound: Int): Int {
        if (bound <= 0) throw IllegalArgumentException("bound must be positive")
        var r = nextBits(31)
        val m = bound - 1
        if ((bound and m) == 0) {
            r = ((bound.toLong() * r.toLong()) shr 31).toInt()
        } else {
            var u = r
            r = u % bound
            while (u - r + m < 0) {
                u = nextBits(31)
                r = u % bound
            }
        }
        return r
    }

    public fun nextInt(origin: Int, bound: Int): Int {
        if (origin >= bound) throw IllegalArgumentException("bound must be greater than origin")
        var r = nextInt()
        val n = bound - origin
        val m = n - 1
        if ((n and m) == 0) {
            r = (r and m) + origin
        } else if (n > 0) {
            var u = r ushr 1
            r = u % n
            while (u + m - r < 0) {
                u = nextInt() ushr 1
                r = u % n
            }
            r += origin
        } else {
            while (r < origin || r >= bound) {
                r = nextInt()
            }
        }
        return r
    }

    public fun nextLong(): Long = (nextBits(32).toLong() shl 32) + nextBits(32).toLong()

    public fun nextLong(bound: Long): Long {
        if (bound <= 0L) throw IllegalArgumentException("bound must be positive")
        val m = bound - 1L
        var r = nextLong()
        if ((bound and m) == 0L) {
            r = r and m
        } else {
            var u = r ushr 1
            r = u % bound
            while (u + m - r < 0L) {
                u = nextLong() ushr 1
                r = u % bound
            }
        }
        return r
    }

    public fun nextLong(origin: Long, bound: Long): Long {
        if (origin >= bound) throw IllegalArgumentException("bound must be greater than origin")
        var r = nextLong()
        val n = bound - origin
        val m = n - 1L
        if ((n and m) == 0L) {
            r = (r and m) + origin
        } else if (n > 0L) {
            var u = r ushr 1
            r = u % n
            while (u + m - r < 0L) {
                u = nextLong() ushr 1
                r = u % n
            }
            r += origin
        } else {
            while (r < origin || r >= bound) {
                r = nextLong()
            }
        }
        return r
    }

    public fun nextBoolean(): Boolean = nextBits(1) != 0

    public fun nextFloat(): Float = nextBits(24) / (1 shl 24).toFloat()

    public fun nextDouble(): Double =
        ((nextBits(26).toLong() shl 27) + nextBits(27).toLong()) * 1.1102230246251565E-16

    public fun nextDouble(bound: Double): Double {
        if (!(bound > 0.0 && bound < Double.POSITIVE_INFINITY)) {
            throw IllegalArgumentException("bound must be finite and positive")
        }
        var r = nextDouble() * bound
        if (r >= bound) r = bound.nextDown()
        return r
    }

    public fun nextDouble(origin: Double, bound: Double): Double {
        if (!(origin < bound && (bound - origin) < Double.POSITIVE_INFINITY)) {
            throw IllegalArgumentException("bound must be greater than origin")
        }
        var r = nextDouble() * (bound - origin) + origin
        if (r >= bound) r = bound.nextDown()
        return r
    }

    public fun nextBytes(bytes: ByteArray) {
        var i = 0
        val len = bytes.size
        while (i < len) {
            var rnd = nextInt()
            var n = if (len - i < 4) len - i else 4
            while (n > 0) {
                bytes[i] = rnd.toByte()
                i++
                rnd = rnd shr 8
                n--
            }
        }
    }

    public fun nextGaussian(): Double {
        if (haveNextNextGaussian) {
            haveNextNextGaussian = false
            return nextNextGaussian
        }
        var v1: Double
        var v2: Double
        var s: Double
        do {
            v1 = 2.0 * nextDouble() - 1.0
            v2 = 2.0 * nextDouble() - 1.0
            s = v1 * v1 + v2 * v2
        } while (s >= 1.0 || s == 0.0)
        val multiplier = sqrt(-2.0 * ln(s) / s)
        nextNextGaussian = v2 * multiplier
        haveNextNextGaussian = true
        return v1 * multiplier
    }
}

private fun scrambleSeed(seed: Long): Long = (seed xor 0x5DEECE66DL) and 0xFFFFFFFFFFFFL

// Exposes a LCG-backed java.util.Random as a kotlin.random.Random
// (Random.asKotlinRandom()), drawing every value from the Java bit stream.
private class JavaRandomAsKotlinRandom(private val java: Random) : KotlinRandom() {
    override fun nextBits(bitCount: Int): Int = java.nextBits(bitCount)
}
