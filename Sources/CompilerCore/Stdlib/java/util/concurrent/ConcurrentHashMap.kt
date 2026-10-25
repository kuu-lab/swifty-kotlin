package java.util.concurrent

import kotlinx.atomicfu.locks.SynchronizedObject

// KUU-3059: java.util.concurrent.ConcurrentHashMap over a lock-guarded
// kotlin.collections.HashMap. Views (keys/values/entries) are snapshots,
// which is sufficient for iteration under concurrency but does not reflect
// later map mutations like the JVM live views do.

public class ConcurrentHashMap<K, V> private constructor(
    private val storage: HashMap<K, V>
) : ConcurrentMap<K, V> {
    private val guard = SynchronizedObject()

    public constructor() : this(HashMap<K, V>())

    public constructor(initialCapacity: Int) : this(HashMap<K, V>(initialCapacity))

    public constructor(elements: Map<K, V>) : this(HashMap<K, V>(elements))

    override val size: Int
        get() = guard.guarded { storage.size }

    override fun isEmpty(): Boolean = guard.guarded { storage.isEmpty() }

    override fun containsKey(key: K): Boolean = guard.guarded { storage.containsKey(key) }

    override fun containsValue(value: V): Boolean = guard.guarded { storage.containsValue(value) }

    override fun get(key: K): V? = guard.guarded { storage[key] }

    public fun getOrDefault(key: K, defaultValue: V): V {
        guard.lock()
        try {
            val current = storage[key]
            return if (current == null) defaultValue else current
        } finally {
            guard.unlock()
        }
    }

    override val keys: MutableSet<K>
        get() = guard.guarded { storage.keys.toMutableSet() }

    override val values: MutableCollection<V>
        get() = guard.guarded { storage.values.toMutableList() }

    override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
        get() = guard.guarded {
            val snapshot = LinkedHashSet<MutableMap.MutableEntry<K, V>>()
            for (entry in storage.entries) {
                snapshot.add(ConcurrentEntry(entry.key, entry.value))
            }
            snapshot
        }

    override fun put(key: K, value: V): V? = guard.guarded { storage.put(key, value) }

    override fun putAll(from: Map<out K, V>) {
        guard.guarded { storage.putAll(from) }
    }

    override fun remove(key: K): V? = guard.guarded { storage.remove(key) }

    override fun clear() {
        guard.guarded { storage.clear() }
    }

    override fun putIfAbsent(key: K, value: V): V? = guard.guarded {
        val current = storage[key]
        if (current == null) storage.put(key, value) else current
    }

    override fun remove(key: K, value: V): Boolean = guard.guarded {
        if (storage[key] != value || !storage.containsKey(key)) {
            false
        } else {
            storage.remove(key)
            true
        }
    }

    override fun replace(key: K, oldValue: V, newValue: V): Boolean = guard.guarded {
        if (storage[key] != oldValue || !storage.containsKey(key)) {
            false
        } else {
            storage[key] = newValue
            true
        }
    }

    override fun replace(key: K, value: V): V? = guard.guarded {
        if (storage.containsKey(key)) storage.put(key, value) else null
    }

    public fun getOrPut(key: K, defaultValue: () -> V): V {
        guard.lock()
        try {
            val current = storage[key]
            if (current == null) {
                val created = defaultValue()
                storage[key] = created
                return created
            }
            return current
        } finally {
            guard.unlock()
        }
    }

    public fun computeIfAbsent(key: K, mappingFunction: (K) -> V?): V? = guard.guarded {
        val current = storage[key]
        if (current != null) {
            current
        } else {
            val mapped = mappingFunction(key)
            if (mapped != null) storage[key] = mapped
            mapped
        }
    }

    public fun keySet(): MutableSet<K> = keys

    override fun toString(): String = guard.guarded { storage.toString() }

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Map<*, *>) return false
        return guard.guarded { storage == other }
    }

    override fun hashCode(): Int = guard.guarded { storage.hashCode() }
}

private class ConcurrentEntry<K, V>(
    override val key: K,
    initialValue: V
) : MutableMap.MutableEntry<K, V> {
    private var current: V = initialValue

    override val value: V
        get() = current

    override fun setValue(newValue: V): V {
        val old = current
        current = newValue
        return old
    }
}

private inline fun <T> SynchronizedObject.guarded(block: () -> T): T {
    lock()
    try {
        return block()
    } finally {
        unlock()
    }
}
