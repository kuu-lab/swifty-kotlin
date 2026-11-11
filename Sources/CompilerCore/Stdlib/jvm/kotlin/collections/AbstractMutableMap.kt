package kotlin.collections

import kotlin.jvm.internal.markers.KMutableMap

public abstract class AbstractMutableMap<K, V> protected constructor() :
    java.util.AbstractMap<K, V>(), KMutableMap {
    public abstract val entries: MutableSet<MutableMap.MutableEntry<K, V>>
    public abstract fun put(key: K, value: V): V?

    override val size: Int get() = entries.size
    override fun entrySet(): MutableSet<MutableMap.MutableEntry<K, V>> = entries
    override val keys: Set<K> get() = super.keySet()
    override fun keySet(): Set<K> = keys
    override val values: Collection<V> get() = super.values()
    override fun values(): Collection<V> = values
}
