package kotlin.collections

import kotlin.jvm.internal.markers.KMappedMarker

public abstract class AbstractList<out E> protected constructor() : AbstractCollection<E>(), List<E> {
    abstract override val size: Int
    abstract override fun get(index: Int): E

    override fun iterator(): Iterator<E> = listIterator()

    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean {
        for (element in elements) if (!contains(element)) return false
        return true
    }

    override fun indexOf(element: @UnsafeVariance E): Int {
        val iterator = listIterator()
        while (iterator.hasNext()) {
            val index = iterator.nextIndex()
            if (iterator.next() == element) return index
        }
        return -1
    }

    override fun lastIndexOf(element: @UnsafeVariance E): Int {
        val iterator = listIterator(size)
        while (iterator.hasPrevious()) {
            val index = iterator.previousIndex()
            if (iterator.previous() == element) return index
        }
        return -1
    }

    override fun listIterator(): ListIterator<E> = listIterator(0)

    override fun listIterator(index: Int): ListIterator<E> {
        if (index < 0 || index > size) throw IndexOutOfBoundsException("index: $index, size: $size")
        return ReadOnlyListIterator(this, index)
    }

    override fun subList(fromIndex: Int, toIndex: Int): List<E> {
        if (fromIndex < 0 || toIndex > size) throw IndexOutOfBoundsException("fromIndex: $fromIndex, toIndex: $toIndex, size: $size")
        if (fromIndex > toIndex) throw IllegalArgumentException("fromIndex: $fromIndex > toIndex: $toIndex")
        return ReadOnlySubList(this, fromIndex, toIndex - fromIndex)
    }

    override fun equals(other: Any?): Boolean {
        if (this === other) return true
        if (other !is List<*> || size != other.size) return false
        val left = iterator()
        val right: Iterator<Any?> = other.iterator()
        while (left.hasNext()) if (left.next() != right.next()) return false
        return true
    }

    override fun hashCode(): Int {
        var hash = 1
        for (element in this) hash = 31 * hash + (element?.hashCode() ?: 0)
        return hash
    }

    public open fun set(index: Int, element: @UnsafeVariance E): E = readOnlyList()
    public open fun add(index: Int, element: @UnsafeVariance E): Unit = readOnlyList()
    public open fun addAll(index: Int, elements: Collection<@UnsafeVariance E>): Boolean = readOnlyList()

    @kotlin.jvm.JvmName("remove")
    public open fun removeIndex(index: Int): E = readOnlyList()
}

private fun readOnlyList(): Nothing = throw UnsupportedOperationException("Operation is not supported for read-only collection")

private class ReadOnlyListIterator<E>(private val list: AbstractList<E>, private var index: Int) :
    ListIterator<E>, KMappedMarker {
    override fun hasNext(): Boolean = index < list.size
    override fun hasPrevious(): Boolean = index > 0
    override fun nextIndex(): Int = index
    override fun previousIndex(): Int = index - 1

    override fun next(): E {
        if (!hasNext()) throw NoSuchElementException()
        val value = list.get(index)
        index += 1
        return value
    }

    override fun previous(): E {
        if (!hasPrevious()) throw NoSuchElementException()
        index -= 1
        return list.get(index)
    }

    fun add(element: E): Unit = readOnlyList()
    fun set(element: E): Unit = readOnlyList()
    fun remove(): Unit = readOnlyList()
}

private class ReadOnlySubList<E>(private val list: AbstractList<E>, private val offset: Int, override val size: Int) :
    AbstractList<E>(), java.util.RandomAccess {
    override fun get(index: Int): E {
        if (index < 0 || index >= size) throw IndexOutOfBoundsException("index: $index, size: $size")
        return list.get(offset + index)
    }
}
