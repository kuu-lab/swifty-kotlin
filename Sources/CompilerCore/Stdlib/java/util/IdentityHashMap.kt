package java.util

import kotlin.internal.KsSymbolName

// Native storage preserves reference identity while the source class owns
// constructors, generic MutableMap conformance, and public member dispatch.
@KsSymbolName("__kk_identity_hash_map_init")
private external fun <K, V> __identityMapInit(map: IdentityHashMap<K, V>)

@KsSymbolName("kk_native_identityHashCode")
internal external fun __identityHashCode(value: Any?): Int

public open class IdentityHashMap<K, V> : MutableMap<K, V> {
    public constructor() {
        __identityMapInit(this)
    }

    public constructor(expectedMaxSize: Int) : this() {
        require(expectedMaxSize >= 0) { "expectedMaxSize is negative" }
    }

    public constructor(original: Map<out K, V>) : this() {
        putAll(original)
    }

    @KsSymbolName("__kk_map_size")
    private external fun __identityMapSize(): Int

    @KsSymbolName("__kk_map_is_empty")
    private external fun __identityMapIsEmpty(): Boolean

    @KsSymbolName("__kk_map_get")
    private external fun __identityMapGet(key: K): V?

    @KsSymbolName("__kk_mutable_map_put")
    private external fun __identityMapPut(key: K, value: V): V?

    @KsSymbolName("__kk_mutable_map_putAll")
    private external fun __identityMapPutAll(from: Map<out K, V>)

    @KsSymbolName("__kk_mutable_map_remove")
    private external fun __identityMapRemove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    private external fun __identityMapClear()

    @KsSymbolName("__kk_map_entries")
    private external fun __identityMapEntries(): MutableSet<MutableMap.MutableEntry<K, V>>

    @KsSymbolName("__kk_map_keys")
    private external fun __identityMapKeys(): MutableSet<K>

    @KsSymbolName("__kk_map_values")
    private external fun __identityMapValues(): MutableCollection<V>

    override fun clear() {
        __identityMapClear()
    }

    override fun containsKey(key: K): Boolean {
        for (entry in entries) {
            if (entry.key === key) return true
        }
        return false
    }

    override fun containsValue(value: V): Boolean {
        for (entry in entries) {
            if (entry.value === value) return true
        }
        return false
    }

    override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
        get() = __identityMapEntries()

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Map<*, *>) return false
        val thisEntries = entries
        val otherEntries = other.entries
        if (thisEntries.size != otherEntries.size) return false

        for (entry in thisEntries) {
            var found = false
            for (otherEntry in otherEntries) {
                if (entry.key === otherEntry.key) {
                    if (entry.value !== otherEntry.value) return false
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return true
    }

    override operator fun get(key: K): V? = __identityMapGet(key)

    override fun hashCode(): Int {
        var result = 0
        for (entry in entries) {
            val keyHash = __identityHashCode(entry.key)
            val valueHash = __identityHashCode(entry.value)
            result += keyHash xor valueHash
        }
        return result
    }

    override fun isEmpty(): Boolean = __identityMapIsEmpty()

    override val keys: MutableSet<K>
        get() = __identityMapKeys()

    @IgnorableReturnValue
    override fun put(key: K, value: V): V? = __identityMapPut(key, value)

    override fun putAll(from: Map<out K, V>) {
        __identityMapPutAll(from)
    }

    @IgnorableReturnValue
    override fun remove(key: K): V? = __identityMapRemove(key)

    override val size: Int
        get() = __identityMapSize()

    override fun toString(): String {
        val builder = StringBuilder()
        builder.append("{")
        var first = true
        for (entry in entries) {
            if (!first) builder.append(", ")
            first = false
            if (entry.key === this) {
                builder.append("(this Map)")
            } else {
                builder.append(entry.key?.toString() ?: "null")
            }
            builder.append("=")
            if (entry.value === this) {
                builder.append("(this Map)")
            } else {
                builder.append(entry.value?.toString() ?: "null")
            }
        }
        builder.append("}")
        return builder.toString()
    }

    override val values: MutableCollection<V>
        get() = __identityMapValues()
}
