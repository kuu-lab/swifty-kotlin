package kotlin.collections

abstract class AbstractList<out E> protected constructor() : List<E>, Collection<E>, Iterable<E> {
    abstract override val size: Int
    abstract override fun get(index: Int): E
    override fun isEmpty(): Boolean = null!!
    override fun contains(element: @UnsafeVariance E): Boolean = null!!
    override fun containsAll(elements: Collection<@UnsafeVariance E>): Boolean = null!!
    override fun iterator(): Iterator<E> = null!!
    override fun indexOf(element: @UnsafeVariance E): Int = null!!
    override fun lastIndexOf(element: @UnsafeVariance E): Int = null!!
    override fun listIterator(): ListIterator<E> = null!!
    override fun listIterator(index: Int): ListIterator<E> = null!!
    override fun subList(fromIndex: Int, toIndex: Int): List<E> = null!!
}
