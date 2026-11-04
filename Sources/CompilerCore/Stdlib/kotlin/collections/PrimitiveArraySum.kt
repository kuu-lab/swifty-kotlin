package kotlin.collections

import kotlin.experimental.ExperimentalTypeInference

// KUU-941: a primitive `vararg` parameter is a primitive array in the callee, so
// the aggregate that used to work only because it was typed as List<T> lives here.

public fun IntArray.sum(): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun LongArray.sum(): Long {
    var sum = 0L
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun ByteArray.sum(): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += this[i].toInt()
        i++
    }
    return sum
}

public fun ShortArray.sum(): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += this[i].toInt()
        i++
    }
    return sum
}

public fun DoubleArray.sum(): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun FloatArray.sum(): Float {
    var sum = 0.0f
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun UIntArray.sum(): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun ULongArray.sum(): ULong {
    var sum = 0uL
    var i = 0
    while (i < this.size) {
        sum += this[i]
        i++
    }
    return sum
}

public fun UByteArray.sum(): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += this[i].toUInt()
        i++
    }
    return sum
}

public fun UShortArray.sum(): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += this[i].toUInt()
        i++
    }
    return sum
}

@SinceKotlin("1.4")
public inline fun CharArray.sumOf(selector: (Char) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun UIntArray.sumOf(selector: (UInt) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.4")
public inline fun UIntArray.sumOf(selector: (UInt) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.4")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun UIntArray.sumOf(selector: (UInt) -> Long): Long {
    var sum = 0L
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.5")
public inline fun UIntArray.sumOf(selector: (UInt) -> UInt): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@SinceKotlin("1.5")
@OptIn(ExperimentalTypeInference::class)
@OverloadResolutionByLambdaReturnType
public inline fun UIntArray.sumOf(selector: (UInt) -> ULong): ULong {
    var sum = 0uL
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun ByteArray.sumBy(selector: (Byte) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun ShortArray.sumBy(selector: (Short) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun IntArray.sumBy(selector: (Int) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun LongArray.sumBy(selector: (Long) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun FloatArray.sumBy(selector: (Float) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun DoubleArray.sumBy(selector: (Double) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun BooleanArray.sumBy(selector: (Boolean) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun CharArray.sumBy(selector: (Char) -> Int): Int {
    var sum = 0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun UByteArray.sumBy(selector: (UByte) -> UInt): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun UShortArray.sumBy(selector: (UShort) -> UInt): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun UIntArray.sumBy(selector: (UInt) -> UInt): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

// Upstream quirk (kept for parity): ULongArray.sumBy accumulates into UInt,
// unlike every other unsigned sum which widens to ULong.
@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun ULongArray.sumBy(selector: (ULong) -> UInt): UInt {
    var sum = 0u
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun ByteArray.sumByDouble(selector: (Byte) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun ShortArray.sumByDouble(selector: (Short) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun IntArray.sumByDouble(selector: (Int) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun LongArray.sumByDouble(selector: (Long) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun FloatArray.sumByDouble(selector: (Float) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun DoubleArray.sumByDouble(selector: (Double) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun BooleanArray.sumByDouble(selector: (Boolean) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun CharArray.sumByDouble(selector: (Char) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun UByteArray.sumByDouble(selector: (UByte) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun UShortArray.sumByDouble(selector: (UShort) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun UIntArray.sumByDouble(selector: (UInt) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}

@ExperimentalUnsignedTypes
@Deprecated("Use sumOf instead.", ReplaceWith("sumOf(selector)"))
public inline fun ULongArray.sumByDouble(selector: (ULong) -> Double): Double {
    var sum = 0.0
    var i = 0
    while (i < this.size) {
        sum += selector(this[i])
        i++
    }
    return sum
}
