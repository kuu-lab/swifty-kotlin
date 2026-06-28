package kotlin.random

// MIGRATION-RANDOM-001
// Random class API — nextInt, nextLong, nextDouble, nextFloat, nextBoolean, nextBytes.
// PRNG state management (SeededRandomBox / SystemRNG) lives in the Swift bridge;
// this file provides the Kotlin-source API that delegates to nextBits for raw entropy.
//
// Migration source:
//   Sources/Runtime/RuntimeRandom.swift          (kk_random_* implementations)
//   Sources/RuntimeABI/RuntimeABISpec+Random.swift (ABI registration)
//   Sources/CompilerCore/Sema/DataFlow/HeaderHelpers+SyntheticRandomStubs.swift
//
// Implementation strategy:
//   nextBits(bitCount)   — synthetic stub remains; calls kk_random_nextBits (PRNG bridge)
//   nextBoolean()        — pure Kotlin: nextBits(1) != 0
//   nextInt()            — pure Kotlin: nextBits(32)
//   nextInt(until)       — pure Kotlin: validated, nextBits(31) % until
//   nextInt(from, until) — pure Kotlin: from + nextInt(until - from)
//   nextLong()           — pure Kotlin: two nextBits(32) combined
//   nextLong(until/range)— pure Kotlin: validated, nextLong() % until
//   nextFloat()          — pure Kotlin: 24-bit significand from nextBits
//   nextFloat(until/range)— pure Kotlin: validated, scaled
//   nextDouble()         — pure Kotlin: 53-bit significand from two nextBits
//   nextDouble(until/range)— pure Kotlin: validated, scaled
//   nextBytes(array)     — bridge delegate: kk_random_nextBytes (non-throwing)
//   nextBytes(size)      — pure Kotlin: validate size, call nextBytes(ByteArray(size))

fun Random.nextBoolean(): Boolean = nextBits(1) != 0

// ─── nextInt ─────────────────────────────────────────────────────────────────

fun Random.nextInt(): Int = nextBits(32)

fun Random.nextInt(until: Int): Int {
    if (until <= 0) throw IllegalArgumentException(
        "Random range is empty: until must be positive, but was $until.")
    val bits = nextBits(31)
    val value = bits % until
    return if (bits - value + (until - 1) < 0) nextInt(until) else value
}

fun Random.nextInt(from: Int, until: Int): Int {
    if (until <= from) throw IllegalArgumentException(
        "Random range is empty: $from..$until.")
    return from + nextInt(until - from)
}

// ─── nextLong ────────────────────────────────────────────────────────────────

fun Random.nextLong(): Long {
    val hi = nextBits(32).toLong() shl 32
    val lo = nextBits(32).toLong() and 0xFFFFFFFFL
    return hi or lo
}

fun Random.nextLong(until: Long): Long {
    if (until <= 0L) throw IllegalArgumentException(
        "Random range is empty: until must be positive, but was $until.")
    return nextLong() % until
}

fun Random.nextLong(from: Long, until: Long): Long {
    if (until <= from) throw IllegalArgumentException(
        "Random range is empty: $from..$until.")
    return from + nextLong(until - from)
}

// ─── nextFloat ───────────────────────────────────────────────────────────────

fun Random.nextFloat(): Float = nextBits(24).toFloat() / 16777216.0f  // 2^24

fun Random.nextFloat(until: Float): Float {
    if (until <= 0.0f || !until.isFinite()) throw IllegalArgumentException(
        "Random range is empty: until must be positive and finite, but was $until.")
    return nextFloat() * until
}

fun Random.nextFloat(from: Float, until: Float): Float {
    if (until <= from || !from.isFinite() || !until.isFinite()) throw IllegalArgumentException(
        "Random range is empty: $from..$until.")
    return from + nextFloat() * (until - from)
}

// ─── nextDouble ──────────────────────────────────────────────────────────────

fun Random.nextDouble(): Double {
    val hi = nextBits(26).toLong() shl 27
    val lo = nextBits(27).toLong()
    return (hi or lo).toDouble() / 9007199254740992.0  // 2^53
}

fun Random.nextDouble(until: Double): Double {
    if (until <= 0.0 || !until.isFinite()) throw IllegalArgumentException(
        "Random range is empty: until must be positive and finite, but was $until.")
    return nextDouble() * until
}

fun Random.nextDouble(from: Double, until: Double): Double {
    if (until <= from || !from.isFinite() || !until.isFinite()) throw IllegalArgumentException(
        "Random range is empty: $from..$until.")
    return from + nextDouble() * (until - from)
}

// ─── nextBytes ───────────────────────────────────────────────────────────────
// ABI bridge: kk_random_nextBytes is non-throwing (fills a pre-allocated ByteArray).

@Suppress("UNCHECKED_CAST")
private external fun kk_random_nextBytes(self: Any?, array: Any?): Any?

@Suppress("UNCHECKED_CAST")
fun Random.nextBytes(array: ByteArray): ByteArray = kk_random_nextBytes(this, array) as ByteArray

fun Random.nextBytes(size: Int): ByteArray {
    if (size < 0) throw IllegalArgumentException(
        "Random byte array size must be non-negative, but was $size.")
    return nextBytes(ByteArray(size))
}
