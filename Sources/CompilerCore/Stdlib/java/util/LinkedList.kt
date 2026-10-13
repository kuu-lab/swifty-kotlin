/*
 * KUU-1858: native java.util.LinkedList surface for Queue and Graph consumers.
 */

package java.util

import kotlin.collections.ArrayDeque
import kotlin.collections.Collection
import kotlin.collections.MutableList

/**
 * A mutable list with deque operations backed by the native ArrayDeque storage.
 */
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

    /** Adds [element] to the front of this list. */
    public fun push(element: E) {
        storage.addFirst(element)
    }

    /** Removes and returns the first element, or `null` when this list is empty. */
    public fun pollFirst(): E? = if (isEmpty()) null else storage.removeFirst()

    /** Removes and returns the first element, throwing when this list is empty. */
    public fun removeFirst(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.removeFirst()
    }

    /** Returns the first element, throwing when this list is empty. */
    public val first: E
        get() {
            if (isEmpty()) throw NoSuchElementException()
            return storage.first()
        }
}
