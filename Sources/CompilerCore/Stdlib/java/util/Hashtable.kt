package java.util

public typealias Hashtable<K, V> = HashMap<K, V>

public fun <K, V> Hashtable<K, V>.contains(value: Any?): Boolean {
    for (candidate in values) {
        if (candidate == value) return true
    }
    return false
}

public fun <K, V> Hashtable<K, V>.keys(): Enumeration<K> =
    IteratorBackedEnumeration(this.keys.iterator())

public fun <K, V> Hashtable<K, V>.elements(): Enumeration<V> =
    IteratorBackedEnumeration(this.values.iterator())

internal class IteratorBackedEnumeration<out E>(
    private val iterator: Iterator<E>,
) : Enumeration<E> {
    override fun hasMoreElements(): Boolean = iterator.hasNext()

    override fun nextElement(): E = iterator.next()
}
