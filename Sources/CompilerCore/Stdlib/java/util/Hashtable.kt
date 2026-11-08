package java.util

import kotlin.collections.Map

public open class Hashtable<K, V> : HashMap<K, V> {
    constructor() : super()
    constructor(initialCapacity: Int) : super(initialCapacity)
    constructor(initialCapacity: Int, loadFactor: Float) : super(initialCapacity, loadFactor)
    constructor(elements: Map<out K, V>) : super(elements)

    public fun contains(value: Any?): Boolean {
        for (candidate in values) {
            if (candidate == value) return true
        }
        return false
    }

    public fun keys(): Enumeration<K> =
        IteratorBackedEnumeration(keys.iterator())

    public fun elements(): Enumeration<V> =
        IteratorBackedEnumeration(values.iterator())
}

internal class IteratorBackedEnumeration<out E>(
    private val iterator: Iterator<E>,
) : Enumeration<E> {
    override fun hasMoreElements(): Boolean = iterator.hasNext()

    override fun nextElement(): E = iterator.next()
}
