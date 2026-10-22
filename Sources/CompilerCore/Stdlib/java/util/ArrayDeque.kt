package java.util

import kotlin.collections.Collection
import kotlin.collections.MutableCollection

public class ArrayDeque<E> private constructor(
    private val storage: kotlin.collections.ArrayDeque<E>
) : MutableCollection<E> by storage {
    public constructor() : this(kotlin.collections.ArrayDeque<E>())

    public constructor(initialCapacity: Int) : this(newArrayDeque<E>(initialCapacity))

    public constructor(elements: Collection<E>) : this(copyArrayDeque<E>(elements))

    override val size: Int
        get() = storage.size

    override fun isEmpty(): Boolean = storage.isEmpty()

    @IgnorableReturnValue
    override fun add(element: E): Boolean = offerLast(element)

    @IgnorableReturnValue
    override fun addAll(elements: Collection<E>): Boolean {
        var modified = false
        val iterator = elements.iterator()
        while (iterator.hasNext()) {
            addLast(iterator.next())
            modified = true
        }
        return modified
    }

    public fun addFirst(element: E) {
        requireNonNullElement<E>(element)
        storage.addFirst(element)
    }

    public fun addLast(element: E) {
        requireNonNullElement<E>(element)
        storage.addLast(element)
    }

    public fun offerFirst(element: E): Boolean {
        addFirst(element)
        return true
    }

    public fun offerLast(element: E): Boolean {
        addLast(element)
        return true
    }

    public fun removeFirst(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.removeFirst()
    }

    public fun removeLast(): E {
        if (isEmpty()) throw NoSuchElementException()
        return storage.removeLast()
    }

    public fun pollFirst(): E? = if (isEmpty()) null else storage.removeFirst()

    public fun pollLast(): E? = if (isEmpty()) null else storage.removeLast()

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

    public fun peekFirst(): E? = storage.firstOrNull()

    public fun peekLast(): E? = storage.lastOrNull()

    public fun removeFirstOccurrence(element: E): Boolean = storage.remove(element)

    public fun removeLastOccurrence(element: E): Boolean {
        val index = storage.lastIndexOf(element)
        if (index < 0) return false
        storage.removeAt(index)
        return true
    }

    public fun offer(element: E): Boolean = offerLast(element)

    public fun remove(): E = removeFirst()

    public fun poll(): E? = pollFirst()

    public fun element(): E = first

    public fun peek(): E? = peekFirst()

    public fun push(element: E) = addFirst(element)

    public fun pop(): E = removeFirst()

    override fun toString(): String =
        storage.joinToString(", ", "[", "]") { element ->
            if (element === this) "(this Collection)" else element.toString()
        }
}

private fun <E> newArrayDeque(initialCapacity: Int): kotlin.collections.ArrayDeque<E> {
    if (initialCapacity < 0) throw IllegalArgumentException()
    return kotlin.collections.ArrayDeque<E>()
}

private fun <E> copyArrayDeque(elements: Collection<E>): kotlin.collections.ArrayDeque<E> {
    val storage = kotlin.collections.ArrayDeque<E>()
    val iterator = elements.iterator()
    while (iterator.hasNext()) {
        val element = iterator.next()
        requireNonNullElement<E>(element)
        storage.addLast(element)
    }
    return storage
}

private fun <E> requireNonNullElement(element: E) {
    if (element == null) throw NullPointerException()
}
