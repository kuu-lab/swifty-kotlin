package kotlin

import kotlin.internal.KsSymbolName

// KSP-777: source-backed declaration for the primitive float array factory.
// The shared array factory lowering packs the vararg elements before calling
// the runtime's common kk_array_of entry point.
@KsSymbolName("kk_array_of")
public external fun floatArrayOf(vararg elements: Float): FloatArray

// Kotlin's unsigned floating-point conversions saturate at the destination
// range, truncate toward zero, and map NaN to zero. Keep the high-bit branches
// in Kotlin so these APIs do not require dedicated runtime conversion bridges.
@PublishedApi
internal inline fun floatToUInt(value: Float): UInt {
    if (value.isNaN() || value <= 0.0f) return 0u
    if (value >= 4294967296.0f) return UInt.MAX_VALUE
    return if (value < 2147483648.0f) {
        value.toInt().toUInt()
    } else {
        (value - 2147483648.0f).toInt().toUInt() + 2147483648u
    }
}

@PublishedApi
internal inline fun floatToULong(value: Float): ULong {
    if (value.isNaN() || value <= 0.0f) return 0uL
    if (value >= 18446744073709551616.0f) return ULong.MAX_VALUE
    return if (value < 9223372036854775808.0f) {
        value.toLong().toULong()
    } else {
        (value - 9223372036854775808.0f).toLong().toULong() + 9223372036854775808uL
    }
}

public inline fun Float.toUInt(): UInt = floatToUInt(this)

public inline fun Float.toULong(): ULong = floatToULong(this)
