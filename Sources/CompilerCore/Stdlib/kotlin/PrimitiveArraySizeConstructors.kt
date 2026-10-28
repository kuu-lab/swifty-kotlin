@file:OptIn(ExperimentalUnsignedTypes::class)

package kotlin

import kotlin.internal.KsSymbolName

// Expose compiler-provided size-only allocation as declarations so every
// primitive-array constructor can participate in callable-reference overload resolution.
@KsSymbolName("kk_array_new_checked")
public external fun BooleanArray(size: Int): BooleanArray

@KsSymbolName("kk_array_new_checked")
public external fun ByteArray(size: Int): ByteArray

@KsSymbolName("kk_array_new_checked")
public external fun CharArray(size: Int): CharArray

@KsSymbolName("kk_array_new_checked")
public external fun DoubleArray(size: Int): DoubleArray

@KsSymbolName("kk_array_new_checked")
public external fun FloatArray(size: Int): FloatArray

@KsSymbolName("kk_array_new_checked")
public external fun LongArray(size: Int): LongArray

@KsSymbolName("kk_array_new_checked")
public external fun ShortArray(size: Int): ShortArray

@KsSymbolName("kk_array_new_checked")
public external fun UByteArray(size: Int): UByteArray

@KsSymbolName("kk_array_new_checked")
public external fun UShortArray(size: Int): UShortArray

@KsSymbolName("kk_array_new_checked")
public external fun UIntArray(size: Int): UIntArray

@KsSymbolName("kk_array_new_checked")
public external fun ULongArray(size: Int): ULongArray
