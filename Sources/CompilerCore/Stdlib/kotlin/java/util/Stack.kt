package java.util

import kotlin.collections.ArrayList

public class EmptyStackException : RuntimeException()

public class Stack<E> {
    private val elements = ArrayList<E>()

    public val size: Int
        get() = elements.size

    public fun isEmpty(): Boolean = elements.isEmpty()

    public fun empty(): Boolean = isEmpty()

    public fun push(element: E): E {
        elements.add(element)
        return element
    }

    public fun pop(): E {
        if (isEmpty()) throw EmptyStackException()
        return elements.removeAt(elements.size - 1)
    }

    public fun peek(): E {
        if (isEmpty()) throw EmptyStackException()
        return elements[elements.size - 1]
    }

    /**
     * Returns the 1-based position of [element] from the top of the stack,
     * or -1 if the stack does not contain it.
     */
    public fun search(element: Any?): Int {
        val index = elements.indexOfLast { it == element }
        return if (index < 0) -1 else elements.size - index
    }

    public operator fun get(index: Int): E = elements[index]

    public override fun toString(): String =
        elements.joinToString(", ", "[", "]") { element ->
            if (element === this) "(this Collection)" else element.toString()
        }
}
