package kotlin.collections

// KUU-1105: primitive-array overloads keep their exact element types.

public fun IntArray.average(): Double = asList().average()

public fun IntArray.min(): Int = asList().min()

public fun IntArray.max(): Int = asList().max()

public fun IntArray.minOrNull(): Int? = asList().minOrNull()

public fun IntArray.maxOrNull(): Int? = asList().maxOrNull()

public inline fun <R> IntArray.foldRight(initial: R, operation: (Int, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun IntArray.reduceRight(operation: (Int, Int) -> Int): Int {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public fun LongArray.average(): Double = asList().average()

public fun LongArray.min(): Long = asList().min()

public fun LongArray.max(): Long = asList().max()

public fun LongArray.minOrNull(): Long? = asList().minOrNull()

public fun LongArray.maxOrNull(): Long? = asList().maxOrNull()

public inline fun <R> LongArray.foldRight(initial: R, operation: (Long, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun LongArray.reduceRight(operation: (Long, Long) -> Long): Long {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public fun ByteArray.average(): Double = asList().average()

public fun ByteArray.min(): Byte = asList().min()

public fun ByteArray.max(): Byte = asList().max()

public fun ByteArray.minOrNull(): Byte? = asList().minOrNull()

public fun ByteArray.maxOrNull(): Byte? = asList().maxOrNull()

public inline fun <R> ByteArray.foldRight(initial: R, operation: (Byte, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun ByteArray.reduceRight(operation: (Byte, Byte) -> Byte): Byte {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public fun ShortArray.average(): Double = asList().average()

public fun ShortArray.min(): Short = asList().min()

public fun ShortArray.max(): Short = asList().max()

public fun ShortArray.minOrNull(): Short? = asList().minOrNull()

public fun ShortArray.maxOrNull(): Short? = asList().maxOrNull()

public inline fun <R> ShortArray.foldRight(initial: R, operation: (Short, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun ShortArray.reduceRight(operation: (Short, Short) -> Short): Short {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public fun CharArray.min(): Char = asList().min()

public fun CharArray.max(): Char = asList().max()

public fun CharArray.minOrNull(): Char? = asList().minOrNull()

public fun CharArray.maxOrNull(): Char? = asList().maxOrNull()

public inline fun <R> CharArray.foldRight(initial: R, operation: (Char, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun CharArray.reduceRight(operation: (Char, Char) -> Char): Char {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun <R> BooleanArray.foldRight(initial: R, operation: (Boolean, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun BooleanArray.reduceRight(operation: (Boolean, Boolean) -> Boolean): Boolean {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public fun FloatArray.average(): Double = asList().average()

public fun FloatArray.min(): Float = minOrNull() ?: throw NoSuchElementException()

public fun FloatArray.max(): Float = maxOrNull() ?: throw NoSuchElementException()

public fun FloatArray.minOrNull(): Float? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.min(result, this[index])
        index++
    }
    return result
}

public fun FloatArray.maxOrNull(): Float? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.max(result, this[index])
        index++
    }
    return result
}

public inline fun <R> FloatArray.foldRight(initial: R, operation: (Float, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun FloatArray.reduceRight(operation: (Float, Float) -> Float): Float {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public fun DoubleArray.average(): Double = asList().average()

public fun DoubleArray.min(): Double = minOrNull() ?: throw NoSuchElementException()

public fun DoubleArray.max(): Double = maxOrNull() ?: throw NoSuchElementException()

public fun DoubleArray.minOrNull(): Double? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.min(result, this[index])
        index++
    }
    return result
}

public fun DoubleArray.maxOrNull(): Double? {
    if (size == 0) return null
    var result = this[0]
    var index = 1
    while (index < size) {
        result = kotlin.math.max(result, this[index])
        index++
    }
    return result
}

public inline fun <R> DoubleArray.foldRight(initial: R, operation: (Double, R) -> R): R {
    var accumulator = initial
    var index = size - 1
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}

public inline fun DoubleArray.reduceRight(operation: (Double, Double) -> Double): Double {
    if (size == 0) throw UnsupportedOperationException("Empty array can't be reduced.")
    var accumulator = this[size - 1]
    var index = size - 2
    while (index >= 0) {
        accumulator = operation(this[index], accumulator)
        index--
    }
    return accumulator
}
