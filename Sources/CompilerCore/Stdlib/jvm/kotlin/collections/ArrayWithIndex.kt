@file:kotlin.jvm.JvmName("ArraysKt")

package kotlin.collections

internal class ArrayIndexingIterable<out T>(
    private val size: Int,
    private val elementAt: (Int) -> T
) : Iterable<IndexedValue<T>> {
    override fun iterator(): Iterator<IndexedValue<T>> = object : Iterator<IndexedValue<T>> {
        private var index = 0

        override fun hasNext(): Boolean = index < size

        override fun next(): IndexedValue<T> {
            if (!hasNext()) throw NoSuchElementException()
            val current = index++
            return IndexedValue(current, elementAt(current))
        }
    }
}

public fun <T> Array<out T>.withIndex(): Iterable<IndexedValue<T>> = ArrayIndexingIterable(size) { this[it] }
public fun ByteArray.withIndex(): Iterable<IndexedValue<Byte>> = ArrayIndexingIterable(size) { this[it] }
public fun ShortArray.withIndex(): Iterable<IndexedValue<Short>> = ArrayIndexingIterable(size) { this[it] }
public fun IntArray.withIndex(): Iterable<IndexedValue<Int>> = ArrayIndexingIterable(size) { this[it] }
public fun LongArray.withIndex(): Iterable<IndexedValue<Long>> = ArrayIndexingIterable(size) { this[it] }
public fun FloatArray.withIndex(): Iterable<IndexedValue<Float>> = ArrayIndexingIterable(size) { this[it] }
public fun DoubleArray.withIndex(): Iterable<IndexedValue<Double>> = ArrayIndexingIterable(size) { this[it] }
public fun BooleanArray.withIndex(): Iterable<IndexedValue<Boolean>> = ArrayIndexingIterable(size) { this[it] }
public fun CharArray.withIndex(): Iterable<IndexedValue<Char>> = ArrayIndexingIterable(size) { this[it] }
