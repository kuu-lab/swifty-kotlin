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

// KSP-1513: unsigned array member bridges. The public `size`, `toList`, and
// `asList` declarations below are source-backed; the runtime keeps the copy
// and backing-view semantics of the Kotlin API.
@KsSymbolName("__kk_uByteArray_toList")
private external fun __kkUByteArrayToList(array: UByteArray): List<UByte>

@KsSymbolName("__kk_uShortArray_toList")
private external fun __kkUShortArrayToList(array: UShortArray): List<UShort>

@KsSymbolName("__kk_uIntArray_toList")
private external fun __kkUIntArrayToList(array: UIntArray): List<UInt>

@KsSymbolName("__kk_uLongArray_toList")
private external fun __kkULongArrayToList(array: ULongArray): List<ULong>

@KsSymbolName("__kk_uByteArray_asList")
private external fun __kkUByteArrayAsList(array: UByteArray): List<UByte>

@KsSymbolName("__kk_uShortArray_asList")
private external fun __kkUShortArrayAsList(array: UShortArray): List<UShort>

@KsSymbolName("__kk_uIntArray_asList")
private external fun __kkUIntArrayAsList(array: UIntArray): List<UInt>

@KsSymbolName("__kk_uLongArray_asList")
private external fun __kkULongArrayAsList(array: ULongArray): List<ULong>

public fun ByteArray.asUByteArray(): UByteArray = this.__asUByteArrayView()

public fun ShortArray.asUShortArray(): UShortArray = this.__asUShortArrayView()

public fun IntArray.asUIntArray(): UIntArray = this.__asUIntArrayView()

public fun LongArray.asULongArray(): ULongArray = this.__asULongArrayView()

public fun UByteArray.asByteArray(): ByteArray = this.__asByteArrayView()

public fun UShortArray.asShortArray(): ShortArray = this.__asShortArrayView()

public fun UIntArray.asIntArray(): IntArray = this.__asIntArrayView()

public fun ULongArray.asLongArray(): LongArray = this.__asLongArrayView()

public val UByteArray.size: Int get() = __kkUByteArraySize(this)
public val UShortArray.size: Int get() = __kkUShortArraySize(this)
public val UIntArray.size: Int get() = __kkUIntArraySize(this)
public val ULongArray.size: Int get() = __kkULongArraySize(this)

public fun UByteArray.toList(): List<UByte> = __kkUByteArrayToList(this)
public fun UShortArray.toList(): List<UShort> = __kkUShortArrayToList(this)
public fun UIntArray.toList(): List<UInt> = __kkUIntArrayToList(this)
public fun ULongArray.toList(): List<ULong> = __kkULongArrayToList(this)

public fun UByteArray.asList(): List<UByte> = __kkUByteArrayAsList(this)
public fun UShortArray.asList(): List<UShort> = __kkUShortArrayAsList(this)
public fun UIntArray.asList(): List<UInt> = __kkUIntArrayAsList(this)
public fun ULongArray.asList(): List<ULong> = __kkULongArrayAsList(this)
