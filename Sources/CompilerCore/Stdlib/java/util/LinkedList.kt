package java.util

import kotlin.collections.ArrayDeque
import kotlin.collections.Collection
import kotlin.collections.MutableList

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

    public fun push(element: E) {
        storage.addFirst(element)
    }

    public fun pollFirst(): E? = if (isEmpty()) null else storage.removeFirst()

    public fun peekLast(): E? = storage.lastOrNull()

    public fun removeFirst(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.removeFirst()
    }

    public val first: E
        get() {
            if (isEmpty()) throw NoSuchElementException()
            return storage.first()
        }

    override fun toString(): String =
        storage.joinToString(", ", "[", "]") { element ->
            if (element === this) "(this Collection)" else element.toString()
        }
}
