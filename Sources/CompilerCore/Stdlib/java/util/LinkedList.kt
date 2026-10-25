package java.util

import kotlin.collections.ArrayDeque
import kotlin.collections.Collection
import kotlin.collections.MutableIterator
import kotlin.collections.MutableList
import kotlin.internal.__valuesEqual

public class LinkedList<E> private constructor(
    private val storage: ArrayDeque<E>
) : MutableList<E> by storage {
    public constructor() : this(ArrayDeque<E>())

    public constructor(elements: Collection<E>) : this(ArrayDeque<E>(elements))

    override val size: Int
        get() = storage.size

    override fun isEmpty(): Boolean = storage.isEmpty()

    @IgnorableReturnValue
    override fun add(element: E): Boolean = storage.add(element)

    @IgnorableReturnValue
    override fun addAll(elements: Collection<E>): Boolean = storage.addAll(elements)

    override fun clear() {
        storage.clear()
    }

    // KUU-3260: delegate-synthesized members lose `operator`, so the indexed
    // and membership operators are redeclared explicitly.
    override operator fun get(index: Int): E = storage[index]

    @IgnorableReturnValue
    override operator fun set(index: Int, element: E): E = storage.set(index, element)

    override operator fun contains(element: E): Boolean = storage.contains(element)

    public fun addFirst(element: E) {
        storage.addFirst(element)
    }

    public fun addLast(element: E) {
        storage.addLast(element)
    }

    @IgnorableReturnValue
    public fun offer(element: E): Boolean = offerLast(element)

    @IgnorableReturnValue
    public fun offerFirst(element: E): Boolean {
        storage.addFirst(element)
        return true
    }

    @IgnorableReturnValue
    public fun offerLast(element: E): Boolean {
        storage.addLast(element)
        return true
    }

    public fun peek(): E? = peekFirst()

    public fun peekFirst(): E? = storage.firstOrNull()

    public fun peekLast(): E? = storage.lastOrNull()

    public fun poll(): E? = pollFirst()

    public fun pollFirst(): E? = if (isEmpty()) null else storage.removeFirst()

    public fun pollLast(): E? = storage.removeLastOrNull()

    public fun element(): E = getFirst()

    public fun getFirst(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.first()
    }

    public fun getLast(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.last()
    }

    public fun remove(): E = removeFirst()

    public fun removeFirst(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.removeFirst()
    }

    public fun removeLast(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.removeLast()
    }

    public fun push(element: E) {
        storage.addFirst(element)
    }

    public fun pop(): E = removeFirst()

    @IgnorableReturnValue
    public fun removeFirstOccurrence(element: Any?): Boolean {
        var index = 0
        while (index < storage.size) {
            if (__valuesEqual(storage[index], element)) {
                storage.removeAt(index)
                return true
            }
            index += 1
        }
        return false
    }

    @IgnorableReturnValue
    public fun removeLastOccurrence(element: Any?): Boolean {
        var index = storage.size - 1
        while (index >= 0) {
            if (__valuesEqual(storage[index], element)) {
                storage.removeAt(index)
                return true
            }
            index -= 1
        }
        return false
    }

    public fun descendingIterator(): MutableIterator<E> = DescendingIterator(this)

    // Any members are not covered by the `MutableList` delegation and must be
    // forwarded explicitly, matching the JVM AbstractList contract.
    override fun toString(): String = storage.toString()

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        // `other is LinkedList` is checked first because stdlib-internal
        // `other is List` does not yet see LinkedList instances through the
        // precompiled-artifact path; the delegate comparison handles every
        // other List implementation.
        if (other is LinkedList<*>) return storage == other.storage
        return storage == other
    }

    override fun hashCode(): Int = storage.hashCode()

    public val first: E
        get() {
            if (isEmpty()) throw NoSuchElementException()
            return storage.first()
        }

    public val last: E
        get() {
            if (isEmpty()) throw NoSuchElementException()
            return storage.last()
        }

    // Index-based walk over the ring buffer; the remove() cursor mirrors
    // ListIteratorImpl's convention of rewinding past the removed slot.
    private class DescendingIterator<T>(private val owner: LinkedList<T>) : MutableIterator<T> {
        private var cursor = owner.storage.size
        private var lastReturned = -1

        override fun hasNext(): Boolean = cursor > 0

        override fun next(): T {
            if (!hasNext()) throw NoSuchElementException()
            cursor -= 1
            lastReturned = cursor
            return owner.storage[cursor]
        }

        override fun remove() {
            if (lastReturned < 0) throw IllegalStateException()
            owner.storage.removeAt(lastReturned)
            cursor = lastReturned
            lastReturned = -1
        }
    }
}
