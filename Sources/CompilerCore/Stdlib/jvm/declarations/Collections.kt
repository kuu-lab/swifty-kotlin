package kotlin.collections
interface Iterator<out T> { operator fun hasNext(): Boolean; operator fun next(): T }
interface Iterable<out E> { operator fun iterator(): Iterator<E> }
interface MutableIterator<out T>: Iterator<T> { fun remove() }
interface MutableIterable<out T>: Iterable<T> { override operator fun iterator(): MutableIterator<T> }
interface ListIterator<out T>: Iterator<T> {
    fun hasPrevious(): Boolean
    fun previous(): T
    fun nextIndex(): Int
    fun previousIndex(): Int
}
interface MutableListIterator<T>: ListIterator<T>, MutableIterator<T> {
    fun add(element: T)
    fun set(element: T)
}
interface Collection<out E>: Iterable<E> {
    val size: Int
    fun isEmpty(): Boolean
    operator fun contains(element: @UnsafeVariance E): Boolean
    fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean
}
interface List<out E>: Collection<E> {
    operator fun get(index: Int): E
    fun indexOf(element: @UnsafeVariance E): Int
    fun lastIndexOf(element: @UnsafeVariance E): Int
    fun listIterator(): ListIterator<E>
    fun listIterator(index: Int): ListIterator<E>
    fun subList(fromIndex: Int, toIndex: Int): List<E>
}
interface MutableCollection<E>: Collection<E> {
    fun add(element: E): Boolean
    fun addAll(elements: Collection<out E>): Boolean
    fun remove(element: E): Boolean
    fun removeAll(elements: Collection<out E>): Boolean
    fun retainAll(elements: Collection<out E>): Boolean
    fun clear()
}
interface MutableList<E>: List<E>, MutableCollection<E> {
    operator fun set(index: Int, element: E): E
    fun add(index: Int, element: E)
    fun addAll(index: Int, elements: Collection<out E>): Boolean
    fun removeAt(index: Int): E
    override fun listIterator(): MutableListIterator<E>
    override fun listIterator(index: Int): MutableListIterator<E>
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E>
}
interface Set<out E>: Collection<E>
interface MutableSet<E>: Set<E>, MutableCollection<E>
interface Map<K, out V> {
    val size: Int
    val keys: Set<K>
    val values: Collection<V>
    operator fun get(key: K): V?
    fun containsKey(key: K): Boolean
    fun containsValue(value: @UnsafeVariance V): Boolean
    fun isEmpty(): Boolean
}
interface MutableMap<K, V>: Map<K, V> {
    fun put(key: K, value: V): V?
    operator fun set(key: K, value: V)
    fun remove(key: K): V?
    fun clear()
}
