package java.util.concurrent

import java.util.SortedMap
import java.util.TreeMap
import kotlin.collections.Map
import kotlin.collections.MutableCollection
import kotlin.collections.MutableMap
import kotlin.collections.MutableSet
import kotlin.internal.KsSymbolName
import kotlin.internal.__valuesEqual

// KUU-4118: java.util.concurrent.ConcurrentSkipListMap — a
// ConcurrentNavigableMap over the same sorted backing box TreeMap uses (the
// TreeSet delegation precedent: single-threaded execution makes the JVM
// skip-list's lock-free concurrency unobservable). Construction goes through
// the TreeMap init-attach path (`__kk_tree_map_init`), so MutableMap /
// SortedMap / NavigableMap members keep dispatching to the sorted runtime
// bridges on the subclass instance. The ConcurrentMap conditional updates
// are sequential versions of the JVM atomic semantics.
//
// JVM parity notes:
//  - Null keys and null values throw NullPointerException in put/get/
//    remove/containsKey/putIfAbsent/replace/containsValue and in the bulk
//    constructors, matching the JVM — bundled TreeMap permits null values,
//    so the guards live here. `remove(key, value)` returns false on a null
//    value instead of throwing, like the JVM. The guards are only reachable
//    through ConcurrentSkipListMap/ConcurrentMap-typed receivers: calls
//    through kotlin.collections interface receivers lower straight to the
//    `__kk_map_*` / `__kk_mutable_map_*` bridges, the same bypass the
//    sorted interfaces document in SortedMap.kt.
//  - `is java.util.TreeMap<*, *>` answers true on these instances; on the
//    JVM it is false but the source-level check is a compile error there.

public open class ConcurrentSkipListMap<K, V> : TreeMap<K, V>, ConcurrentNavigableMap<K, V> {
    public constructor() : super()

    public constructor(comparator: Comparator<in K>?) : super(comparator)

    public constructor(original: Map<out K, V>) : super() {
        // TreeMap's own `putAll(original)` would lower to the external
        // `__kk_mutable_map_putAll` bridge and skip the null guards below,
        // so the copy runs through this class's putAll.
        putAll(original)
    }

    public constructor(sortedMap: SortedMap<K, V>) : super(sortedMap.comparator()) {
        putAll(sortedMap)
    }

    @KsSymbolName("__kk_map_get")
    private external fun __cslmGet(key: K): V?

    @KsSymbolName("__kk_mutable_map_put")
    private external fun __cslmPut(key: K, value: V): V?

    @KsSymbolName("__kk_mutable_map_remove")
    private external fun __cslmRemove(key: K): V?

    @KsSymbolName("__kk_map_keys")
    private external fun __cslmKeys(): MutableSet<K>

    @KsSymbolName("__kk_map_values")
    private external fun __cslmValues(): MutableCollection<V>

    private fun requireNonNullKey(key: K) {
        if (key == null) throw NullPointerException()
    }

    override operator fun get(key: K): V? {
        requireNonNullKey(key)
        return __cslmGet(key)
    }

    override fun containsKey(key: K): Boolean {
        requireNonNullKey(key)
        return __cslmKeys().contains(key)
    }

    override fun containsValue(value: V): Boolean {
        if (value == null) throw NullPointerException()
        for (item in __cslmValues()) {
            if (__valuesEqual(item, value)) return true
        }
        return false
    }

    @IgnorableReturnValue
    override fun put(key: K, value: V): V? {
        if (key == null || value == null) throw NullPointerException()
        return __cslmPut(key, value)
    }

    override fun putAll(from: Map<out K, V>) {
        // Member-wise puts match the JVM AbstractMap path: the first null
        // key/value throws and earlier entries stay inserted.
        for (entry in from.entries) {
            put(entry.key, entry.value)
        }
    }

    @IgnorableReturnValue
    override fun remove(key: K): V? {
        requireNonNullKey(key)
        return __cslmRemove(key)
    }

    override fun putIfAbsent(key: K, value: V): V? {
        if (key == null || value == null) throw NullPointerException()
        val current = __cslmGet(key)
        if (current == null) {
            __cslmPut(key, value)
            return null
        }
        return current
    }

    override fun remove(key: K, value: V): Boolean {
        requireNonNullKey(key)
        if (value == null) return false
        val current = __cslmGet(key)
        if (current == null || !__valuesEqual(current, value)) return false
        __cslmRemove(key)
        return true
    }

    override fun replace(key: K, oldValue: V, newValue: V): Boolean {
        if (key == null || oldValue == null || newValue == null) throw NullPointerException()
        val current = __cslmGet(key)
        if (current == null || !__valuesEqual(current, oldValue)) return false
        __cslmPut(key, newValue)
        return true
    }

    @IgnorableReturnValue
    override fun replace(key: K, value: V): V? {
        if (key == null || value == null) throw NullPointerException()
        return if (containsKey(key)) __cslmPut(key, value) else null
    }

    /** JVM `Map.getOrDefault`; the null-key NPE comes from `get`. */
    public fun getOrDefault(key: K, defaultValue: V): V {
        requireNonNullKey(key)
        return __cslmGet(key) ?: defaultValue
    }

    /** JVM `clone()`: a fresh map carrying the same comparator and entries. */
    public fun clone(): ConcurrentSkipListMap<K, V> {
        val copy = ConcurrentSkipListMap<K, V>(comparator())
        copy.putAll(this)
        return copy
    }
}
