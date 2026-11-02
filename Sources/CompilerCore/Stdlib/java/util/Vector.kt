package java.util

public typealias Vector<E> = ArrayList<E>

/**
 * JVM `Vector.elements()`: returns an [Enumeration] over the vector's elements.
 */
public fun <E> Vector<E>.elements(): Enumeration<E> =
    IteratorBackedEnumeration(this.iterator())
