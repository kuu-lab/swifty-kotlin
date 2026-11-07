package java.util

import kotlin.collections.Collection

public open class Vector<E> : ArrayList<E> {
    constructor() : super()
    constructor(initialCapacity: Int) : super(initialCapacity)
    constructor(elements: Collection<E>) : super(elements)

    /**
     * JVM `Vector.elements()`: returns an [Enumeration] over the vector's elements.
     */
    public fun elements(): Enumeration<E> =
        IteratorBackedEnumeration(iterator())

    /** JVM `Vector.firstElement()`: returns the first element or throws [NoSuchElementException]. */
    public fun firstElement(): E {
        if (isEmpty()) throw NoSuchElementException()
        return this[0]
    }

    /** JVM `Vector.lastElement()`: returns the last element or throws [NoSuchElementException]. */
    public fun lastElement(): E {
        if (isEmpty()) throw NoSuchElementException()
        return this[size - 1]
    }
}
