package kotlin.collections

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
