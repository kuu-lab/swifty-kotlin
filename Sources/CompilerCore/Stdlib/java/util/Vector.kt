package java.util

import kotlin.collections.Collection

public open class Vector<E> : ArrayList<E> {
    constructor() : super()
    constructor(initialCapacity: Int) : super(initialCapacity)
    constructor(elements: Collection<E>) : super(elements)

    public fun elements(): Enumeration<E> =
        IteratorBackedEnumeration(iterator())

    public fun firstElement(): E {
        if (isEmpty()) throw NoSuchElementException()
        return this[0]
    }

    public fun lastElement(): E {
        if (isEmpty()) throw NoSuchElementException()
        return this[size - 1]
    }
}
