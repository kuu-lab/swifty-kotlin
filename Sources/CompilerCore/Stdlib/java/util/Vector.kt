package java.util

public typealias Vector<E> = ArrayList<E>

/**
 * JVM `Vector.elements()`: returns an [Enumeration] over the vector's elements.
 */
public fun <E> Vector<E>.elements(): Enumeration<E> =
    IteratorBackedEnumeration(this.iterator())

/** JVM `Vector.firstElement()`: returns the first element or throws [NoSuchElementException]. */
public fun <E> Vector<E>.firstElement(): E {
    if (isEmpty()) throw NoSuchElementException()
    return this[0]
}

/** JVM `Vector.lastElement()`: returns the last element or throws [NoSuchElementException]. */
public fun <E> Vector<E>.lastElement(): E {
    if (isEmpty()) throw NoSuchElementException()
    return this[size - 1]
}
