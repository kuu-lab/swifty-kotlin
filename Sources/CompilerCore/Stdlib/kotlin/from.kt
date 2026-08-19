package kotlin

import kotlin.internal.KsSymbolName

// Floating-point values use their IEEE bit pattern as the runtime ABI payload.
// The existing raw-bit entry points are ABI identity functions, so they also
// provide the source-backed inverse without a fromBits-specific bridge.
@KsSymbolName("__kk_double_toRawBits")
private external fun __bitsToDouble(bits: Long): Double

@KsSymbolName("__kk_float_toRawBits")
private external fun __bitsToFloat(bits: Int): Float

public fun fromBits(bits: Long): Double = __bitsToDouble(bits)

public fun fromBits(bits: Int): Float = __bitsToFloat(bits)
