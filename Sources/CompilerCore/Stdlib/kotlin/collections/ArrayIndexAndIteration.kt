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
