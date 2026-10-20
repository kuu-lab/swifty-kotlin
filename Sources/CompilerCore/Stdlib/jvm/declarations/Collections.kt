package kotlin.collections
interface Iterator<out T> { operator fun hasNext(): Boolean; operator fun next(): T }
interface Iterable<out T> { operator fun iterator(): Iterator<T> }
interface MutableIterator<out T>: Iterator<T> { fun remove() }
interface MutableIterable<out T>: Iterable<T> { override operator fun iterator(): MutableIterator<T> }
interface Collection<out T>: Iterable<T> {
    val size: Int
    fun isEmpty(): Boolean
    operator fun contains(element: @UnsafeVariance T): Boolean
}
interface List<out T>: Collection<T> { operator fun get(index: Int): T }
interface MutableCollection<T>: Collection<T> {
    fun add(element: T): Boolean
    fun remove(element: T): Boolean
    fun clear()
}
interface MutableList<T>: List<T>, MutableCollection<T> {
    operator fun set(index: Int, element: T): T
    fun removeAt(index: Int): T
}
interface Set<out T>: Collection<T>
interface MutableSet<T>: Set<T>, MutableCollection<T>
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
