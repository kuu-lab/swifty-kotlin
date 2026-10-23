package kotlin.collections
interface Iterator<out T> { operator fun hasNext(): Boolean; operator fun next(): T }
interface Iterable<out E> { operator fun iterator(): Iterator<E> }
interface MutableIterator<out T>: Iterator<T> { fun remove() }
interface MutableIterable<out T>: Iterable<T> { override operator fun iterator(): MutableIterator<T> }
interface Collection<out E>: Iterable<E> {
    val size: Int
    fun isEmpty(): Boolean
    operator fun contains(element: @UnsafeVariance E): Boolean
}
interface List<out E>: Collection<E> { operator fun get(index: Int): E }
interface MutableCollection<E>: Collection<E> {
    fun add(element: E): Boolean
    fun remove(element: E): Boolean
    fun clear()
}
interface MutableList<E>: List<E>, MutableCollection<E> {
    operator fun set(index: Int, element: E): E
    fun removeAt(index: Int): E
}
interface Set<out E>: Collection<E>
interface MutableSet<E>: Set<E>, MutableCollection<E>
interface Map<K, out V> {
    val size: Int
    val keys: Set<K>
    val values: Collection<V>
    operator fun get(key: K): V?
    fun containsKey(key: K): Boolean
    fun isEmpty(): Boolean
}
interface MutableMap<K, V>: Map<K, V> {
    fun put(key: K, value: V): V?
    operator fun set(key: K, value: V)
    fun remove(key: K): V?
    fun clear()
}

external operator fun <K, V> Map.Entry<K, V>.component1(): K
external operator fun <K, V> Map.Entry<K, V>.component2(): V
