package kotlin.collections

import kotlin.jvm.internal.__jvmMapEntries
import kotlin.jvm.internal.markers.KMappedMarker
import kotlin.jvm.internal.markers.KMutableMap

internal interface MapWithDefault<K, out V> : Map<K, V> {
    val map: Map<K, V>
    fun getOrImplicitDefault(key: K): V
}

internal interface MutableMapWithDefault<K, V> : MutableMap<K, V>, MapWithDefault<K, V> {
    val mutableMap: MutableMap<K, V>
}

internal class MapWithDefaultImpl<K, V>(
    override val map: Map<K, V>,
    private val default: (K) -> V
) : java.util.AbstractMap<K, V>(), MapWithDefault<K, V>, KMappedMarker {
    override val size: Int get() = map.size
    override val keys: Set<K> get() = map.keys
    override val values: Collection<V> get() = map.values
    @Suppress("UNCHECKED_CAST")
    override val entries: Set<Map.Entry<K, V>> get() = entrySet() as Set<Map.Entry<K, V>>
    override fun entrySet(): Set<Any?> = __jvmMapEntries(map)
    fun size(): Int = map.size
    override fun keySet(): Set<K> = map.keys
    override fun values(): Collection<V> = map.values
    override fun containsKey(key: K): Boolean = map.containsKey(key)
    override fun containsValue(value: V): Boolean = map.containsValue(value)
    override fun get(key: K): V? = map[key]
    override fun isEmpty(): Boolean = map.isEmpty()
    override fun equals(other: Any?): Boolean = map == other
    override fun hashCode(): Int = map.hashCode()
    override fun toString(): String = map.toString()

    fun put(key: K, value: V): V? = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun remove(key: K): V? = throw UnsupportedOperationException("Operation is not supported for read-only collection")
    fun putAll(values: Map<out K, V>) { throw UnsupportedOperationException("Operation is not supported for read-only collection") }
    fun clear() { throw UnsupportedOperationException("Operation is not supported for read-only collection") }

    override fun getOrImplicitDefault(key: K): V {
        val value = map[key]
        if (value != null || map.containsKey(key)) {
            @Suppress("UNCHECKED_CAST")
            return value as V
        }
        return default(key)
    }
}

internal class MutableMapWithDefaultImpl<K, V>(
    override val mutableMap: MutableMap<K, V>,
    private val default: (K) -> V
) : java.util.AbstractMap<K, V>(), MutableMapWithDefault<K, V>, KMutableMap {
    override val map: Map<K, V> get() = mutableMap
    override val size: Int get() = mutableMap.size
    override val keys: MutableSet<K> get() = mutableMap.keys
    override val values: MutableCollection<V> get() = mutableMap.values
    @Suppress("UNCHECKED_CAST")
    override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
        get() = entrySet() as MutableSet<MutableMap.MutableEntry<K, V>>
    override fun entrySet(): Set<Any?> = __jvmMapEntries(mutableMap)
    fun size(): Int = mutableMap.size
    override fun keySet(): MutableSet<K> = mutableMap.keys
    override fun values(): MutableCollection<V> = mutableMap.values
    override fun containsKey(key: K): Boolean = mutableMap.containsKey(key)
    override fun containsValue(value: V): Boolean = mutableMap.containsValue(value)
    override fun get(key: K): V? = mutableMap[key]
    override fun isEmpty(): Boolean = mutableMap.isEmpty()
    override fun put(key: K, value: V): V? = mutableMap.put(key, value)
    override fun set(key: K, value: V) { mutableMap.put(key, value) }
    override fun remove(key: K): V? = mutableMap.remove(key)
    override fun putAll(from: Map<out K, V>) { mutableMap.putAll(from) }
    override fun clear() { mutableMap.clear() }
    override fun equals(other: Any?): Boolean = mutableMap == other
    override fun hashCode(): Int = mutableMap.hashCode()
    override fun toString(): String = mutableMap.toString()

    override fun getOrImplicitDefault(key: K): V {
        val value = mutableMap[key]
        if (value != null || mutableMap.containsKey(key)) {
            @Suppress("UNCHECKED_CAST")
            return value as V
        }
        return default(key)
    }
}
