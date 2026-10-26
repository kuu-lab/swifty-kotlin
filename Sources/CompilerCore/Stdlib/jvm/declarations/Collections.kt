package kotlin.collections

import java.util.Spliterator
import java.util.stream.Stream

interface Iterator<out T> { operator fun hasNext(): Boolean; operator fun next(): T }
interface Iterable<out E> {
    operator fun iterator(): Iterator<E>
    fun spliterator(): Spliterator<@UnsafeVariance E> = null!!
}
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
    fun stream(): Stream<@UnsafeVariance E> = null!!
    fun parallelStream(): Stream<@UnsafeVariance E> = null!!
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
    interface Entry<out K, out V> {
        val key: K
        val value: V
    }
    val size: Int
    val keys: Set<K>
    val values: Collection<V>
    val entries: Set<Entry<K, V>>
    operator fun get(key: K): V?
    fun containsKey(key: K): Boolean
    fun containsValue(value: @UnsafeVariance V): Boolean
    fun isEmpty(): Boolean
}
interface MutableMap<K, V>: Map<K, V> {
    interface MutableEntry<K, V>: Map.Entry<K, V> {
        fun setValue(value: V): V
    }
    override val entries: MutableSet<MutableEntry<K, V>>
    fun put(key: K, value: V): V?
    operator fun set(key: K, value: V)
    fun remove(key: K): V?
    fun clear()
}

external operator fun <K, V> Map.Entry<K, V>.component1(): K
external operator fun <K, V> Map.Entry<K, V>.component2(): V
