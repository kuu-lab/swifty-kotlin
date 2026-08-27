package kotlin.collections

import kotlin.internal.KsSymbolName

// KSP-1512: signed primitive-array member bridges. The public `size` and
// `toList` declarations below are bundled Kotlin source; these private
// declarations retain only the runtime allocation/boxing work.
@KsSymbolName("__kk_intArray_toList")
private external fun __kkIntArrayToList(array: IntArray): List<Int>

@KsSymbolName("__kk_longArray_toList")
private external fun __kkLongArrayToList(array: LongArray): List<Long>

@KsSymbolName("__kk_shortArray_toList")
private external fun __kkShortArrayToList(array: ShortArray): List<Short>

@KsSymbolName("__kk_byteArray_toList")
private external fun __kkByteArrayToList(array: ByteArray): List<Byte>

@KsSymbolName("__kk_charArray_toList")
private external fun __kkCharArrayToList(array: CharArray): List<Char>

@KsSymbolName("__kk_booleanArray_toList")
private external fun __kkBooleanArrayToList(array: BooleanArray): List<Boolean>

@KsSymbolName("__kk_doubleArray_toList")
private external fun __kkDoubleArrayToList(array: DoubleArray): List<Double>

@KsSymbolName("__kk_floatArray_toList")
private external fun __kkFloatArrayToList(array: FloatArray): List<Float>

// KSP-1512: public signed primitive-array members are source-backed. `size`
// uses the intrinsic declarations in kotlin.ArrayIntrinsics.kt, while
// `toList` delegates to the typed runtime bridge for correct primitive boxing.
public val IntArray.size: Int get() = __kkIntArraySize(this)
public val LongArray.size: Int get() = __kkLongArraySize(this)
public val ShortArray.size: Int get() = __kkShortArraySize(this)
public val ByteArray.size: Int get() = __kkByteArraySize(this)
public val CharArray.size: Int get() = __kkCharArraySize(this)
public val BooleanArray.size: Int get() = __kkBooleanArraySize(this)
public val DoubleArray.size: Int get() = __kkDoubleArraySize(this)
public val FloatArray.size: Int get() = __kkFloatArraySize(this)

public fun IntArray.toList(): List<Int> = __kkIntArrayToList(this)
public fun LongArray.toList(): List<Long> = __kkLongArrayToList(this)
public fun ShortArray.toList(): List<Short> = __kkShortArrayToList(this)
public fun ByteArray.toList(): List<Byte> = __kkByteArrayToList(this)
public fun CharArray.toList(): List<Char> = __kkCharArrayToList(this)
public fun BooleanArray.toList(): List<Boolean> = __kkBooleanArrayToList(this)
public fun DoubleArray.toList(): List<Double> = __kkDoubleArrayToList(this)
public fun FloatArray.toList(): List<Float> = __kkFloatArrayToList(this)

// KSP-628 + KSP-629
// List → array conversions (object + signed/unsigned primitive element types).
// Migration source: Sources/Runtime/RuntimeArrayBasics.swift
//   (kk_list_toTypedArray / kk_list_to{Char,Boolean,Short,Double,Float,Int,Long,Byte,UByte,UShort,UInt,ULong}Array)
//
// Fresh storage comes from the array constructors / arrayOfNulls, so only the
// per-array-type allocation core stays in the Swift runtime.

@Suppress("UNCHECKED_CAST")
public fun <T> List<T>.toTypedArray(): Array<T> {
    val size = this.size
    val result = arrayOfNulls<T>(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result as Array<T>
}

public fun List<Char>.toCharArray(): CharArray {
    val size = this.size
    val result = CharArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Boolean>.toBooleanArray(): BooleanArray {
    val size = this.size
    val result = BooleanArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Short>.toShortArray(): ShortArray {
    val size = this.size
    val result = ShortArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Double>.toDoubleArray(): DoubleArray {
    val size = this.size
    val result = DoubleArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Float>.toFloatArray(): FloatArray {
    val size = this.size
    val result = FloatArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Int>.toIntArray(): IntArray {
    val size = this.size
    val result = IntArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Long>.toLongArray(): LongArray {
    val size = this.size
    val result = LongArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<Byte>.toByteArray(): ByteArray {
    val size = this.size
    val result = ByteArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<UByte>.toUByteArray(): UByteArray {
    val size = this.size
    val result = UByteArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<UShort>.toUShortArray(): UShortArray {
    val size = this.size
    val result = UShortArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<UInt>.toUIntArray(): UIntArray {
    val size = this.size
    val result = UIntArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}

public fun List<ULong>.toULongArray(): ULongArray {
    val size = this.size
    val result = ULongArray(size)
    var i = 0
    while (i < size) {
        result[i] = this[i]
        i++
    }
    return result
}
