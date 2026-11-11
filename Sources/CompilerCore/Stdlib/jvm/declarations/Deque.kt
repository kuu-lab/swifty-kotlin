package kotlin.collections

class ArrayDeque<E> : MutableList<E> {
    constructor()
    constructor(initialCapacity: Int)
    constructor(elements: Collection<E>)

    override val size: Int get() = 0
    override fun isEmpty(): Boolean = false
    override fun contains(element: E): Boolean = false
    override fun containsAll(elements: Collection<E>): Boolean = false
    override fun iterator(): MutableIterator<E> = null!!
    override operator fun get(index: Int): E = null!!
    override operator fun set(index: Int, element: E): E = null!!
    override fun indexOf(element: E): Int = -1
    override fun lastIndexOf(element: E): Int = -1
    override fun listIterator(): MutableListIterator<E> = null!!
    override fun listIterator(index: Int): MutableListIterator<E> = null!!
    override fun subList(fromIndex: Int, toIndex: Int): MutableList<E> = null!!
    override fun add(element: E): Boolean = false
    override fun add(index: Int, element: E) {}
    override fun addAll(elements: Collection<out E>): Boolean = false
    override fun addAll(index: Int, elements: Collection<out E>): Boolean = false
    override fun remove(element: E): Boolean = false
    override fun removeAt(index: Int): E = null!!
    override fun removeAll(elements: Collection<out E>): Boolean = false
    override fun retainAll(elements: Collection<out E>): Boolean = false
    override fun clear() {}

    fun first(): E = null!!
    fun firstOrNull(): E? = null
    fun last(): E = null!!
    fun lastOrNull(): E? = null
    fun addFirst(element: E) {}
    fun addLast(element: E) {}
    fun removeFirst(): E = null!!
    fun removeFirstOrNull(): E? = null
    fun removeLast(): E = null!!
    fun removeLastOrNull(): E? = null
}
