package java.util

// JDK superclass contracts only; these bodies never enter the runtime JAR.
abstract class AbstractList<T> protected constructor() {
    open val size: Int get() = 0
    open fun isEmpty(): Boolean = false
    open fun contains(element: T): Boolean = false
    open fun get(index: Int): T = null!!
    open fun listIterator(): ListIterator<T> = null!!
    open fun listIterator(index: Int): ListIterator<T> = null!!
}
abstract class AbstractSet<T> protected constructor() {
    open val size: Int get() = 0
    open fun isEmpty(): Boolean = false
    open fun contains(element: T): Boolean = false
}
abstract class AbstractMap<K, V> protected constructor() {
    open val size: Int get() = 0
    open val keys: kotlin.collections.Set<K> get() = null!!
    open val values: kotlin.collections.Collection<V> get() = null!!
    open fun get(key: K): V? = null
    open fun containsKey(key: K): Boolean = false
    open fun isEmpty(): Boolean = false
    abstract fun entrySet(): kotlin.collections.Set<Any?>
    open fun keySet(): kotlin.collections.Set<K> = null!!
    open fun values(): kotlin.collections.Collection<V> = null!!
}
interface ListIterator<T>: kotlin.collections.Iterator<T> {
    fun hasPrevious(): Boolean
    fun previous(): T
    fun nextIndex(): Int
    fun previousIndex(): Int
    fun add(element: T)
    fun set(element: T)
    fun remove()
}

abstract class AbstractCollection<T> protected constructor() {
    open val size: Int get() = 0
    open fun isEmpty(): Boolean = false
    open fun contains(element: T): Boolean = false
    abstract fun iterator(): kotlin.collections.Iterator<T>
}
interface RandomAccess
interface MapEntry<K, V> {
    fun getKey(): K
    fun getValue(): V
    fun setValue(value: V): V
}
