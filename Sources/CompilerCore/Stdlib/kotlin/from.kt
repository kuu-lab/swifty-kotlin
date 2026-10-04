package kotlin

import kotlin.internal.KsSymbolName

// Floating-point values use their IEEE bit pattern as the runtime ABI payload.
// Double's bit pattern already occupies the full ABI word, so its fromBits
// bridge is an identity operation. Float exposes its
// 32-bit pattern as a sign-extended Kotlin Int, while the runtime ABI carries
// it zero-extended, so Float needs a dedicated re-widening bridge.
@KsSymbolName("__kk_double_fromBits")
private external fun __bitsToDouble(bits: Long): Double

@KsSymbolName("__kk_float_fromBits")
private external fun __bitsToFloat(bits: Int): Float

public fun fromBits(bits: Long): Double = __bitsToDouble(bits)

public fun fromBits(bits: Int): Float = __bitsToFloat(bits)
