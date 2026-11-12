package kotlin.collections

import kotlin.jvm.internal.markers.KMappedMarker

public abstract class AbstractMap<K, out V> protected constructor() :
    java.util.AbstractMap<K, @UnsafeVariance V>(), Map<K, V>, KMappedMarker {
    abstract override val entries: Set<Map.Entry<K, V>>

    override val size: Int get() = entries.size

    override fun entrySet(): Set<Map.Entry<K, V>> = entries

    override val keys: Set<K> get() = super.keySet()
    override fun keySet(): Set<K> = keys

    override val values: Collection<V> get() = super.values()
    override fun values(): Collection<V> = values

    public open fun put(key: K, value: @UnsafeVariance V): V? =
        throw UnsupportedOperationException("Operation is not supported for read-only collection")

    public open fun remove(key: K): V? =
        throw UnsupportedOperationException("Operation is not supported for read-only collection")

    public open fun putAll(values: Map<out K, @UnsafeVariance V>) {
        throw UnsupportedOperationException("Operation is not supported for read-only collection")
    }

    public open fun clear() {
        throw UnsupportedOperationException("Operation is not supported for read-only collection")
    }
}
