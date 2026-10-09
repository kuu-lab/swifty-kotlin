/*
 * KUU-1361: JVM java.util.NavigableMap parity for the bundled stdlib.
 */

package java.util

import kotlin.collections.MutableMap
import kotlin.internal.KsSymbolName

// Members stay bodiless: interface default bodies dispatch through the
// itable, which runtime-backed boxes do not populate.

/**
 * A [SortedMap] with navigation methods — `java.util.NavigableMap`.
 */
public interface NavigableMap<K, V> : SortedMap<K, V> {
    @KsSymbolName("__kk_sorted_map_lower_key")
    public fun lowerKey(key: K): K?

    @KsSymbolName("__kk_sorted_map_floor_key")
    public fun floorKey(key: K): K?

    @KsSymbolName("__kk_sorted_map_ceiling_key")
    public fun ceilingKey(key: K): K?

    @KsSymbolName("__kk_sorted_map_higher_key")
    public fun higherKey(key: K): K?

    @KsSymbolName("__kk_sorted_map_first_entry")
    public fun firstEntry(): MutableMap.MutableEntry<K, V>?

    @KsSymbolName("__kk_sorted_map_last_entry")
    public fun lastEntry(): MutableMap.MutableEntry<K, V>?

    @KsSymbolName("__kk_sorted_map_poll_first_entry")
    public fun pollFirstEntry(): MutableMap.MutableEntry<K, V>?

    @KsSymbolName("__kk_sorted_map_poll_last_entry")
    public fun pollLastEntry(): MutableMap.MutableEntry<K, V>?

    @KsSymbolName("__kk_sorted_map_descending")
    public fun descendingMap(): NavigableMap<K, V>

    @KsSymbolName("__kk_sorted_map_descending_key_set")
    public fun descendingKeySet(): NavigableSet<K>
}
