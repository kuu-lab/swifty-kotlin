package kotlin.collections

import kotlin.jvm.internal.markers.KMappedMarker

public abstract class AbstractCollection<out E> protected constructor() :
    java.util.AbstractCollection<@UnsafeVariance E>(), KMappedMarker {
    abstract override val size: Int

    public open fun add(element: Any?): Boolean = readOnly()
    public open fun remove(element: Any?): Boolean = readOnly()
    public open fun addAll(elements: Collection<*>): Boolean = readOnly()
    public open fun removeAll(elements: Collection<*>): Boolean = readOnly()
    public open fun retainAll(elements: Collection<*>): Boolean = readOnly()
    public open fun clear(): Unit = readOnly()

    private fun readOnly(): Nothing = throw UnsupportedOperationException("Operation is not supported for read-only collection")
}
