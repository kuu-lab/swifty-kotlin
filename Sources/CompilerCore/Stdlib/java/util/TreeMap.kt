/*
 * KUU-1361: JVM java.util.TreeMap parity for the bundled stdlib.
 */

package java.util

import kotlin.collections.Map
import kotlin.collections.MutableCollection
import kotlin.collections.MutableMap
import kotlin.collections.MutableSet
import kotlin.internal.KsSymbolName
import kotlin.internal.__valuesEqual

// Construction is lowered to the runtime sorted-map entry points
// (`__kk_tree_map_new` for the empty/comparator forms,
// `__kk_tree_map_new_map`/`__kk_tree_map_new_sorted_map` for the copy forms)
// by `CollectionLiteralLoweringPass`; see TreeSet.kt for the `init`-attach
// rationale. Member externals mirror the HashMap.kt pattern so concrete
// `TreeMap<K, V>` receivers dispatch straight to the `__kk_map_*` /
// `__kk_mutable_map_*` bridges.

@KsSymbolName("__kk_tree_map_init")
private external fun <K, V> __kkTreeMapInit(map: TreeMap<K, V>, comparator: Comparator<in K>?)

/**
 * A key-sorted map backed by a runtime box — `java.util.TreeMap`.
 */
public open class TreeMap<K, V> : NavigableMap<K, V> {
    public constructor() {
        __kkTreeMapInit(this, null)
    }

    public constructor(comparator: Comparator<in K>?) {
        __kkTreeMapInit(this, null)
    }

    public constructor(original: Map<out K, V>) : this() { putAll(original) }

    public constructor(sortedMap: SortedMap<K, V>) : this(sortedMap.comparator()) { putAll(sortedMap) }

    @KsSymbolName("__kk_map_size")
    private external fun __treeMapSize(): Int

    @KsSymbolName("__kk_map_is_empty")
    private external fun __treeMapIsEmpty(): Boolean

    @KsSymbolName("__kk_map_get")
    private external fun __treeMapGet(key: K): V?

    @KsSymbolName("__kk_mutable_map_put")
    private external fun __treeMapPut(key: K, value: V): V?

    @KsSymbolName("__kk_mutable_map_putAll")
    private external fun __treeMapPutAll(from: Map<out K, V>)

    @KsSymbolName("__kk_mutable_map_remove")
    private external fun __treeMapRemove(key: K): V?

    @KsSymbolName("__kk_mutable_map_clear")
    private external fun __treeMapClear()

    @KsSymbolName("__kk_map_entries")
    private external fun __treeMapEntries(): MutableSet<MutableMap.MutableEntry<K, V>>

    @KsSymbolName("__kk_map_keys")
    private external fun __treeMapKeys(): MutableSet<K>

    @KsSymbolName("__kk_map_values")
    private external fun __treeMapValues(): MutableCollection<V>

    override fun clear() {
        __treeMapClear()
    }

    // `get` resolves keys through the map's comparator, matching
    // `java.util.TreeMap.containsKey` (which does not use `equals`).
    override fun containsKey(key: K): Boolean = __treeMapGet(key) != null

    override fun containsValue(value: V): Boolean {
        for (entry in entries) {
            if (__valuesEqual(entry.value, value)) return true
        }
        return false
    }

    override val entries: MutableSet<MutableMap.MutableEntry<K, V>>
        get() = __treeMapEntries()

    override fun equals(other: Any?): Boolean {
        if (other === this) return true
        if (other !is Map<*, *>) return false
        val thisEntries = entries
        val otherEntries = other.entries
        if (thisEntries.size != otherEntries.size) return false

        for (entry in thisEntries) {
            var found = false
            for (otherEntry in otherEntries) {
                if (__valuesEqual(entry.key, otherEntry.key)) {
                    if (!__valuesEqual(entry.value, otherEntry.value)) return false
                    found = true
                    break
                }
            }
            if (!found) return false
        }
        return true
    }

    override operator fun get(key: K): V? = __treeMapGet(key)

    override fun hashCode(): Int {
        var result = 0
        for (entry in entries) {
            val keyHash = entry.key?.hashCode() ?: 0
            val valueHash = entry.value?.hashCode() ?: 0
            result += keyHash xor valueHash
        }
        return result
    }

    override fun isEmpty(): Boolean = __treeMapIsEmpty()

    // `__kk_map_keys` returns a NavigableSet-tagged view for sorted maps,
    // matching `java.util.TreeMap.keySet()`.
    override val keys: MutableSet<K>
        get() = __treeMapKeys()

    @IgnorableReturnValue
    override fun put(key: K, value: V): V? = __treeMapPut(key, value)

    override fun putAll(from: Map<out K, V>) {
        __treeMapPutAll(from)
    }

    @IgnorableReturnValue
    override fun remove(key: K): V? = __treeMapRemove(key)

    override val size: Int
        get() = __treeMapSize()

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
        get() = __treeMapValues()
}
