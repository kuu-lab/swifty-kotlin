package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-660
// Array signed/unsigned view conversions.
// Migration source: Sources/Runtime/RuntimeArrayBasics.swift (kk_*Array_as*Array)
//
// A signed primitive array and its unsigned counterpart share the same backing
// storage; the conversion reinterprets the same array handle rather than copying,
// so it is delegated to the __kk_* runtime bridges.

@KsSymbolName("__kk_byteArray_asUByteArray")
private external fun ByteArray.__asUByteArrayView(): UByteArray

@KsSymbolName("__kk_shortArray_asUShortArray")
private external fun ShortArray.__asUShortArrayView(): UShortArray

@KsSymbolName("__kk_intArray_asUIntArray")
private external fun IntArray.__asUIntArrayView(): UIntArray

@KsSymbolName("__kk_longArray_asULongArray")
private external fun LongArray.__asULongArrayView(): ULongArray

@KsSymbolName("__kk_uByteArray_asByteArray")
private external fun UByteArray.__asByteArrayView(): ByteArray

@KsSymbolName("__kk_uShortArray_asShortArray")
private external fun UShortArray.__asShortArrayView(): ShortArray

@KsSymbolName("__kk_uIntArray_asIntArray")
private external fun UIntArray.__asIntArrayView(): IntArray

@KsSymbolName("__kk_uLongArray_asLongArray")
private external fun ULongArray.__asLongArrayView(): LongArray

public fun ByteArray.asUByteArray(): UByteArray = this.__asUByteArrayView()

public fun ShortArray.asUShortArray(): UShortArray = this.__asUShortArrayView()

public fun IntArray.asUIntArray(): UIntArray = this.__asUIntArrayView()

public fun LongArray.asULongArray(): ULongArray = this.__asULongArrayView()

public fun UByteArray.asByteArray(): ByteArray = this.__asByteArrayView()

public fun UShortArray.asShortArray(): ShortArray = this.__asShortArrayView()

public fun UIntArray.asIntArray(): IntArray = this.__asIntArrayView()

public fun ULongArray.asLongArray(): LongArray = this.__asLongArrayView()
