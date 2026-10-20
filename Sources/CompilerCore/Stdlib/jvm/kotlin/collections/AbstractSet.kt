package kotlin.collections

import kotlin.jvm.internal.markers.KMappedMarker

// The JDK base supplies the complete Collection ABI and set equality/hashCode.
// The Kotlin marker and mutators retain the read-only AbstractSet contract.
public abstract class AbstractSet<out E> protected constructor(): java.util.AbstractSet<E>(), Set<E>, Collection<E>, Iterable<E>, KMappedMarker {
    abstract override val size: Int
    fun size(): Int = size
    abstract override fun iterator(): Iterator<E>

    open fun add(element: Any?): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    open fun remove(element: Any?): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    open fun addAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    open fun removeAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    open fun retainAll(elements: Collection<*>): Boolean = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    open fun clear(): Unit = throw UnsupportedOperationException("Operation is not supported for read-only collection")
}
