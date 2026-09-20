/*
 * Copyright 2010-2024 JetBrains s.r.o. and Kotlin Programming Language contributors.
 * Licensed under the Apache License, Version 2.0.
 *
 * Derived from kotlin-stdlib libraries/stdlib/src/kotlin/collections/AbstractList.kt.
 */

package kotlin.collections

// KSP-700: source-backed nominal shell and default read-only list behavior.
// Concrete subclasses only need to provide indexed access and size.
public abstract class AbstractList<out E> protected constructor() : AbstractCollection<E>(), List<E> {
    public abstract override operator fun get(index: Int): E

    override fun iterator(): Iterator<E> = IteratorImpl(this)

    public fun indexOf(element: @UnsafeVariance E): Int {
        var index = 0
        val iterator = listIterator()
        while (iterator.hasNext()) {
            if (iterator.next() == element) return index
            index += 1
        }
        return -1
    }

    public fun lastIndexOf(element: @UnsafeVariance E): Int {
        val iterator = listIterator(size)
        while (iterator.hasPrevious()) {
            if (iterator.previous() == element) return iterator.nextIndex()
        }
        return -1
    }

    override fun listIterator(): ListIterator<E> = listIterator(0)

    override fun listIterator(index: Int): ListIterator<E> = ListIteratorImpl(this, index)

    public fun subList(fromIndex: Int, toIndex: Int): List<E> = SubList(this, fromIndex, toIndex)

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is List<*>) return false
        return abstractListOrderedEquals(this, other)
    }

    override fun hashCode(): Int = abstractListOrderedHashCode(this)

    private open class IteratorImpl<T>(private val list: AbstractList<T>) : Iterator<T> {
        private var index = 0

        override fun hasNext(): Boolean = index < list.size

        override fun next(): T {
            if (!hasNext()) throw NoSuchElementException()
            val value = list.get(index)
            index += 1
            return value
        }
    }

    private class ListIteratorImpl<T>(
        private val list: AbstractList<T>,
        index: Int
    ) : ListIterator<T> {
        private var cursor = 0

        init {
            abstractListCheckPositionIndex(index, list.size)
            cursor = index
        }

        override fun hasNext(): Boolean = cursor < list.size

        override fun next(): T {
            if (!hasNext()) throw NoSuchElementException()
            val value = list.get(cursor)
            cursor += 1
            return value
        }

        override fun hasPrevious(): Boolean = cursor > 0

        override fun nextIndex(): Int = cursor

        override fun previous(): T {
            if (!hasPrevious()) throw NoSuchElementException()
            cursor -= 1
            return list.get(cursor)
        }

        override fun previousIndex(): Int = cursor - 1
    }

    private class SubList<T>(
        private val list: AbstractList<T>,
        private val fromIndex: Int,
        toIndex: Int
    ) : AbstractList<T>(), RandomAccess {
        private var subListSize: Int = 0

        init {
            abstractListCheckRangeIndexes(fromIndex, toIndex, list.size)
            subListSize = toIndex - fromIndex
        }

        override fun get(index: Int): T {
            abstractListCheckElementIndex(index, subListSize)
            return list.get(fromIndex + index)
        }

        override val size: Int
            get() = subListSize
    }
}

private fun abstractListCheckElementIndex(index: Int, size: Int) {
    if (index < 0 || index >= size) {
        throw IndexOutOfBoundsException("index: $index, size: $size")
    }
}

private fun abstractListCheckPositionIndex(index: Int, size: Int) {
    if (index < 0 || index > size) {
        throw IndexOutOfBoundsException("index: $index, size: $size")
    }
}

private fun abstractListCheckRangeIndexes(fromIndex: Int, toIndex: Int, size: Int) {
    if (fromIndex < 0 || toIndex > size) {
        throw IndexOutOfBoundsException("fromIndex: $fromIndex, toIndex: $toIndex, size: $size")
    }
    if (fromIndex > toIndex) {
        throw IllegalArgumentException("fromIndex: $fromIndex > toIndex: $toIndex")
    }
}

private fun abstractListOrderedHashCode(collection: Collection<*>): Int {
    var hashCode = 1
    for (element in collection) {
        hashCode = 31 * hashCode + (element?.hashCode() ?: 0)
    }
    return hashCode
}

private fun abstractListOrderedEquals(collection: Collection<*>, other: Collection<*>): Boolean {
    if (collection.size != other.size) return false

    val otherIterator = other.iterator()
    for (element in collection) {
        if (element != otherIterator.next()) return false
    }
    return true
}
