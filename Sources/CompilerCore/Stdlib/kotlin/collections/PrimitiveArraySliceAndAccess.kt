package kotlin.collections

// KUU-1105: primitive-array overloads keep their exact element types.

public fun IntArray.take(n: Int): List<Int> = asList().take(n)

public fun IntArray.takeLast(n: Int): List<Int> = asList().takeLast(n)

public fun IntArray.drop(n: Int): List<Int> = asList().drop(n)

public fun IntArray.dropLast(n: Int): List<Int> = asList().dropLast(n)

public fun IntArray.slice(indices: IntRange): List<Int> = asList().slice(indices)

public fun IntArray.slice(indices: Iterable<Int>): List<Int> = asList().slice(indices)

public fun IntArray.elementAtOrNull(index: Int): Int? =
    if (index >= 0 && index < size) this[index] else null

public inline fun IntArray.getOrElse(index: Int, defaultValue: (Int) -> Int): Int =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun IntArray.elementAt(index: Int): Int = this[index]

public fun IntArray.getOrNull(index: Int): Int? =
    if (index >= 0 && index < size) this[index] else null

public inline fun IntArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Int): Int =
    getOrElse(index, defaultValue)

public fun IntArray.indexOf(element: Int): Int = asList().indexOf(element)

public fun IntArray.lastIndexOf(element: Int): Int = asList().lastIndexOf(element)

public inline fun IntArray.indexOfFirst(predicate: (Int) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun IntArray.indexOfLast(predicate: (Int) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun IntArray.fill(value: Int, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}

public fun LongArray.take(n: Int): List<Long> = asList().take(n)

public fun LongArray.takeLast(n: Int): List<Long> = asList().takeLast(n)

public fun LongArray.drop(n: Int): List<Long> = asList().drop(n)

public fun LongArray.dropLast(n: Int): List<Long> = asList().dropLast(n)

public fun LongArray.slice(indices: IntRange): List<Long> = asList().slice(indices)

public fun LongArray.slice(indices: Iterable<Int>): List<Long> = asList().slice(indices)

public fun LongArray.elementAtOrNull(index: Int): Long? =
    if (index >= 0 && index < size) this[index] else null

public inline fun LongArray.getOrElse(index: Int, defaultValue: (Int) -> Long): Long =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun LongArray.elementAt(index: Int): Long = this[index]

public fun LongArray.getOrNull(index: Int): Long? =
    if (index >= 0 && index < size) this[index] else null

public inline fun LongArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Long): Long =
    getOrElse(index, defaultValue)

public fun LongArray.indexOf(element: Long): Int = asList().indexOf(element)

public fun LongArray.lastIndexOf(element: Long): Int = asList().lastIndexOf(element)

public inline fun LongArray.indexOfFirst(predicate: (Long) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun LongArray.indexOfLast(predicate: (Long) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun LongArray.fill(value: Long, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}

public fun ByteArray.take(n: Int): List<Byte> = asList().take(n)

public fun ByteArray.takeLast(n: Int): List<Byte> = asList().takeLast(n)

public fun ByteArray.drop(n: Int): List<Byte> = asList().drop(n)

public fun ByteArray.dropLast(n: Int): List<Byte> = asList().dropLast(n)

public fun ByteArray.slice(indices: IntRange): List<Byte> = asList().slice(indices)

public fun ByteArray.slice(indices: Iterable<Int>): List<Byte> = asList().slice(indices)

public fun ByteArray.elementAtOrNull(index: Int): Byte? =
    if (index >= 0 && index < size) this[index] else null

public inline fun ByteArray.getOrElse(index: Int, defaultValue: (Int) -> Byte): Byte =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun ByteArray.elementAt(index: Int): Byte = this[index]

public fun ByteArray.getOrNull(index: Int): Byte? =
    if (index >= 0 && index < size) this[index] else null

public inline fun ByteArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Byte): Byte =
    getOrElse(index, defaultValue)

public fun ByteArray.indexOf(element: Byte): Int = asList().indexOf(element)

public fun ByteArray.lastIndexOf(element: Byte): Int = asList().lastIndexOf(element)

public inline fun ByteArray.indexOfFirst(predicate: (Byte) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun ByteArray.indexOfLast(predicate: (Byte) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun ByteArray.fill(value: Byte, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}

public fun ShortArray.take(n: Int): List<Short> = asList().take(n)

public fun ShortArray.takeLast(n: Int): List<Short> = asList().takeLast(n)

public fun ShortArray.drop(n: Int): List<Short> = asList().drop(n)

public fun ShortArray.dropLast(n: Int): List<Short> = asList().dropLast(n)

public fun ShortArray.slice(indices: IntRange): List<Short> = asList().slice(indices)

public fun ShortArray.slice(indices: Iterable<Int>): List<Short> = asList().slice(indices)

public fun ShortArray.elementAtOrNull(index: Int): Short? =
    if (index >= 0 && index < size) this[index] else null

public inline fun ShortArray.getOrElse(index: Int, defaultValue: (Int) -> Short): Short =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun ShortArray.elementAt(index: Int): Short = this[index]

public fun ShortArray.getOrNull(index: Int): Short? =
    if (index >= 0 && index < size) this[index] else null

public inline fun ShortArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Short): Short =
    getOrElse(index, defaultValue)

public fun ShortArray.indexOf(element: Short): Int = asList().indexOf(element)

public fun ShortArray.lastIndexOf(element: Short): Int = asList().lastIndexOf(element)

public inline fun ShortArray.indexOfFirst(predicate: (Short) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun ShortArray.indexOfLast(predicate: (Short) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun ShortArray.fill(value: Short, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}

public fun CharArray.take(n: Int): List<Char> = asList().take(n)

public fun CharArray.takeLast(n: Int): List<Char> = asList().takeLast(n)

public fun CharArray.drop(n: Int): List<Char> = asList().drop(n)

public fun CharArray.dropLast(n: Int): List<Char> = asList().dropLast(n)

public fun CharArray.slice(indices: IntRange): List<Char> = asList().slice(indices)

public fun CharArray.slice(indices: Iterable<Int>): List<Char> = asList().slice(indices)

public fun CharArray.elementAtOrNull(index: Int): Char? =
    if (index >= 0 && index < size) this[index] else null

public inline fun CharArray.getOrElse(index: Int, defaultValue: (Int) -> Char): Char =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun CharArray.elementAt(index: Int): Char = this[index]

public fun CharArray.getOrNull(index: Int): Char? =
    if (index >= 0 && index < size) this[index] else null

public inline fun CharArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Char): Char =
    getOrElse(index, defaultValue)

public fun CharArray.indexOf(element: Char): Int = asList().indexOf(element)

public fun CharArray.lastIndexOf(element: Char): Int = asList().lastIndexOf(element)

public inline fun CharArray.indexOfFirst(predicate: (Char) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun CharArray.indexOfLast(predicate: (Char) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun CharArray.fill(value: Char, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}

public fun BooleanArray.take(n: Int): List<Boolean> = asList().take(n)

public fun BooleanArray.takeLast(n: Int): List<Boolean> = asList().takeLast(n)

public fun BooleanArray.drop(n: Int): List<Boolean> = asList().drop(n)

public fun BooleanArray.dropLast(n: Int): List<Boolean> = asList().dropLast(n)

public fun BooleanArray.slice(indices: IntRange): List<Boolean> = asList().slice(indices)

public fun BooleanArray.slice(indices: Iterable<Int>): List<Boolean> = asList().slice(indices)

public fun BooleanArray.elementAtOrNull(index: Int): Boolean? =
    if (index >= 0 && index < size) this[index] else null

public inline fun BooleanArray.getOrElse(index: Int, defaultValue: (Int) -> Boolean): Boolean =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun BooleanArray.elementAt(index: Int): Boolean = this[index]

public fun BooleanArray.getOrNull(index: Int): Boolean? =
    if (index >= 0 && index < size) this[index] else null

public inline fun BooleanArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Boolean): Boolean =
    getOrElse(index, defaultValue)

public fun BooleanArray.indexOf(element: Boolean): Int = asList().indexOf(element)

public fun BooleanArray.lastIndexOf(element: Boolean): Int = asList().lastIndexOf(element)

public inline fun BooleanArray.indexOfFirst(predicate: (Boolean) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun BooleanArray.indexOfLast(predicate: (Boolean) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun BooleanArray.fill(value: Boolean, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}

public fun FloatArray.take(n: Int): List<Float> = asList().take(n)

public fun FloatArray.takeLast(n: Int): List<Float> = asList().takeLast(n)

public fun FloatArray.drop(n: Int): List<Float> = asList().drop(n)

public fun FloatArray.dropLast(n: Int): List<Float> = asList().dropLast(n)

public fun FloatArray.slice(indices: IntRange): List<Float> = asList().slice(indices)

public fun FloatArray.slice(indices: Iterable<Int>): List<Float> = asList().slice(indices)

public fun FloatArray.elementAtOrNull(index: Int): Float? =
    if (index >= 0 && index < size) this[index] else null

public inline fun FloatArray.getOrElse(index: Int, defaultValue: (Int) -> Float): Float =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun FloatArray.elementAt(index: Int): Float = this[index]

public fun FloatArray.getOrNull(index: Int): Float? =
    if (index >= 0 && index < size) this[index] else null

public inline fun FloatArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Float): Float =
    getOrElse(index, defaultValue)

public inline fun FloatArray.indexOfFirst(predicate: (Float) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun FloatArray.indexOfLast(predicate: (Float) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun FloatArray.fill(value: Float, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}

public fun DoubleArray.take(n: Int): List<Double> = asList().take(n)

public fun DoubleArray.takeLast(n: Int): List<Double> = asList().takeLast(n)

public fun DoubleArray.drop(n: Int): List<Double> = asList().drop(n)

public fun DoubleArray.dropLast(n: Int): List<Double> = asList().dropLast(n)

public fun DoubleArray.slice(indices: IntRange): List<Double> = asList().slice(indices)

public fun DoubleArray.slice(indices: Iterable<Int>): List<Double> = asList().slice(indices)

public fun DoubleArray.elementAtOrNull(index: Int): Double? =
    if (index >= 0 && index < size) this[index] else null

public inline fun DoubleArray.getOrElse(index: Int, defaultValue: (Int) -> Double): Double =
    if (index >= 0 && index < size) this[index] else defaultValue(index)

public fun DoubleArray.elementAt(index: Int): Double = this[index]

public fun DoubleArray.getOrNull(index: Int): Double? =
    if (index >= 0 && index < size) this[index] else null

public inline fun DoubleArray.elementAtOrElse(index: Int, defaultValue: (Int) -> Double): Double =
    getOrElse(index, defaultValue)

public inline fun DoubleArray.indexOfFirst(predicate: (Double) -> Boolean): Int =
    asList().indexOfFirst(predicate)

public inline fun DoubleArray.indexOfLast(predicate: (Double) -> Boolean): Int =
    asList().indexOfLast(predicate)

public fun DoubleArray.fill(value: Double, fromIndex: Int = 0, toIndex: Int = size) {
    if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex($fromIndex) > toIndex($toIndex)")
    if (fromIndex < 0) throw ArrayIndexOutOfBoundsException("Array index out of range: $fromIndex")
    if (toIndex > size) throw ArrayIndexOutOfBoundsException("Array index out of range: $toIndex")
    var index = fromIndex
    while (index < toIndex) {
        this[index] = value
        index++
    }
}
