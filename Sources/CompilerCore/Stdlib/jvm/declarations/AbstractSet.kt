package kotlin.collections

abstract class AbstractSet<out E> protected constructor(): Set<E>, Collection<E>, Iterable<E> {
    abstract override val size: Int
    abstract override fun iterator(): Iterator<E>
    open override fun isEmpty(): Boolean = false
    open override fun contains(element: @UnsafeVariance E): Boolean = false
}
