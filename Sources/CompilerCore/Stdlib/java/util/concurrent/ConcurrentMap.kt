package java.util.concurrent

public interface ConcurrentMap<K, V> : MutableMap<K, V> {
    public fun putIfAbsent(key: K, value: V): V?

    public fun remove(key: K, value: V): Boolean

    public fun replace(key: K, oldValue: V, newValue: V): Boolean

    public fun replace(key: K, value: V): V?
}
