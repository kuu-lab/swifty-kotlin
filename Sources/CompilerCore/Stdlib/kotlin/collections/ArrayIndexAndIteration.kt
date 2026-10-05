package kotlin.collections

// KUU-572: Array index and iteration APIs are ordinary Kotlin source. Array
// storage, element access, and primitive boxing remain compiler/runtime
// responsibilities; these declarations only compose those existing APIs.

public fun <T> Array<out T>.lastIndex(): Int = this.size - 1

public fun <T> Array<out T>.indices(): IntRange = 0..this.lastIndex()

public fun IntArray.lastIndex(): Int = this.size - 1

public fun IntArray.indices(): IntRange = 0..this.lastIndex()

public fun LongArray.lastIndex(): Int = this.size - 1

public fun LongArray.indices(): IntRange = 0..this.lastIndex()

public fun ByteArray.lastIndex(): Int = this.size - 1

public fun ByteArray.indices(): IntRange = 0..this.lastIndex()

public fun CharArray.lastIndex(): Int = this.size - 1

public fun CharArray.indices(): IntRange = 0..this.lastIndex()

public operator fun <T> Array<out T>.iterator(): Iterator<T> {
    val array = this
    return object : Iterator<T> {
        private var index = 0

        override fun hasNext(): Boolean = index < array.size

        override fun next(): T {
            if (!hasNext()) throw NoSuchElementException()
            return array[index++]
        }
    }
}

public operator fun IntArray.iterator(): IntIterator {
    val array = this
    return object : IntIterator() {
        private var index = 0

        override fun hasNext(): Boolean = index < array.size

        override fun nextInt(): Int {
            if (!hasNext()) throw NoSuchElementException()
            return array[index++]
        }
    }
}

public operator fun LongArray.iterator(): LongIterator {
    val array = this
    return object : LongIterator() {
        private var index = 0

        override fun hasNext(): Boolean = index < array.size

        override fun nextLong(): Long {
            if (!hasNext()) throw NoSuchElementException()
            return array[index++]
        }
    }
}

public fun <T> Array<out T>.withIndex(): Iterable<IndexedValue<T>> {
    val array = this
    return object : Iterable<IndexedValue<T>> {
        override fun iterator(): Iterator<IndexedValue<T>> = IndexingIterator(array.iterator())
    }
}

public fun IntArray.withIndex(): Iterable<IndexedValue<Int>> {
    val array = this
    return object : Iterable<IndexedValue<Int>> {
        override fun iterator(): Iterator<IndexedValue<Int>> = IndexingIterator(array.iterator())
    }
}

public fun LongArray.withIndex(): Iterable<IndexedValue<Long>> {
    val array = this
    return object : Iterable<IndexedValue<Long>> {
        override fun iterator(): Iterator<IndexedValue<Long>> = IndexingIterator(array.iterator())
    }
}

public operator fun IntArray.component1(): Int = this[0]

public operator fun IntArray.component2(): Int = this[1]

public operator fun IntArray.component3(): Int = this[2]

public operator fun IntArray.component4(): Int = this[3]

public operator fun IntArray.component5(): Int = this[4]

public operator fun LongArray.component1(): Long = this[0]

public operator fun LongArray.component2(): Long = this[1]

public operator fun LongArray.component3(): Long = this[2]

public operator fun LongArray.component4(): Long = this[3]

public operator fun LongArray.component5(): Long = this[4]

public operator fun ShortArray.component1(): Short = this[0]

public operator fun ShortArray.component2(): Short = this[1]

public operator fun ShortArray.component3(): Short = this[2]

public operator fun ShortArray.component4(): Short = this[3]

public operator fun ShortArray.component5(): Short = this[4]

public operator fun ByteArray.component1(): Byte = this[0]

public operator fun ByteArray.component2(): Byte = this[1]

public operator fun ByteArray.component3(): Byte = this[2]

public operator fun ByteArray.component4(): Byte = this[3]

public operator fun ByteArray.component5(): Byte = this[4]

public operator fun CharArray.component1(): Char = this[0]

public operator fun CharArray.component2(): Char = this[1]

public operator fun CharArray.component3(): Char = this[2]

public operator fun CharArray.component4(): Char = this[3]

public operator fun CharArray.component5(): Char = this[4]

public operator fun BooleanArray.component1(): Boolean = this[0]

public operator fun BooleanArray.component2(): Boolean = this[1]

public operator fun BooleanArray.component3(): Boolean = this[2]

public operator fun BooleanArray.component4(): Boolean = this[3]

public operator fun BooleanArray.component5(): Boolean = this[4]

public operator fun FloatArray.component1(): Float = this[0]

public operator fun FloatArray.component2(): Float = this[1]

public operator fun FloatArray.component3(): Float = this[2]

public operator fun FloatArray.component4(): Float = this[3]

public operator fun FloatArray.component5(): Float = this[4]

public operator fun DoubleArray.component1(): Double = this[0]

public operator fun DoubleArray.component2(): Double = this[1]

public operator fun DoubleArray.component3(): Double = this[2]

public operator fun DoubleArray.component4(): Double = this[3]

public operator fun DoubleArray.component5(): Double = this[4]
