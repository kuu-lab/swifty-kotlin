package kotlin

// KSP-775: Double-specific stdlib APIs are implemented in bundled Kotlin.
// The unsigned conversions preserve Kotlin's saturating behavior for NaN,
// negative values, and values outside the destination type's range.

public inline fun doubleArrayOf(vararg elements: Double): DoubleArray {
    val result = DoubleArray(elements.size)
    var i = 0
    while (i < elements.size) {
        result[i] = elements[i]
        i++
    }
    return result
}

public fun Double.toUInt(): UInt {
    if (isNaN()) return 0u
    if (this >= 4294967295.0) return UInt.MAX_VALUE
    if (this <= 0.0) return 0u
    return this.toLong().toUInt()
}

public fun Double.toULong(): ULong {
    if (isNaN()) return 0uL
    if (this >= 18446744073709551616.0) return ULong.MAX_VALUE
    if (this <= 0.0) return 0uL

    // Double cannot represent every ULong value. Split at 2^63 so the
    // intermediate signed conversion remains in range before reinterpreting
    // the low bits as ULong.
    val signedLimit = 9223372036854775808.0
    if (this >= signedLimit) {
        return 9223372036854775807uL + 1uL + (this - signedLimit).toLong().toULong()
    }
    return this.toLong().toULong()
}
